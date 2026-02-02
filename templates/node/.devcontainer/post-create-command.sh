#!/usr/bin/env bash
set -euo pipefail

# Post-create command for Node.js devcontainer
# Usage: ./post-create-command.sh [--quick]

QUICK_MODE=0
if [[ "${1:-}" == "--quick" ]]; then
  QUICK_MODE=1
fi

# Track failed steps for final exit code determination
declare -a FAILED_STEPS=()

log_err() { printf "\033[1;31m[err]\033[0m %s\n" "$*"; }
log_info() { printf "\033[0;36m[info]\033[0m %s\n" "$*"; }

echo "=== Post-Create Command (quick=$QUICK_MODE) ==="

# --- Fix Volume Permissions ---
fix_permissions() {
  log_info "Fixing volume permissions..."
  # Fix Docker volumes
  if [[ -d "$HOME/.npm" ]]; then
    sudo chown -R "$(id -u):$(id -g)" "$HOME/.npm" 2>/dev/null || true
  fi
  if [[ -d "$HOME/.npm-global" ]]; then
    sudo chown -R "$(id -u):$(id -g)" "$HOME/.npm-global" 2>/dev/null || true
  fi
  # NOTE: Do NOT chown ~/.claude or ~/.codex - they are bind mounts from host
  # Changing their ownership would lock out the host user
  # Create ~/.local/bin for Claude CLI
  mkdir -p "$HOME/.local/bin" 2>/dev/null || true

  # Create symlink for host username so Claude plugin paths work
  # (plugins store paths like /home/hostuser/.claude/... which need to resolve in container)
  if [[ -d "$HOME/.claude/plugins" ]]; then
    HOST_USER=$(stat -c '%U' "$HOME/.claude" 2>/dev/null || true)
    if [[ -n "$HOST_USER" && "$HOST_USER" != "$(whoami)" && ! -e "/home/$HOST_USER" ]]; then
      sudo ln -sf "$HOME" "/home/$HOST_USER" 2>/dev/null || true
      log_info "Created symlink /home/$HOST_USER -> $HOME for plugin paths"
    fi
  fi
}

fix_permissions

# --- npm Install ---
install_npm() {
  if [[ -f "package.json" ]]; then
    log_info "Installing npm packages..."
    npm install || true
  fi
}

# --- AI CLIs ---
install_ai_clis() {
  echo "Installing AI CLIs..."

  if [[ "${SKIP_AI_CLIS:-0}" == "1" ]]; then
    log_info "Skipping AI CLI installation (SKIP_AI_CLIS=1)"
    return 0
  fi

  npm_prefix="${NPM_CONFIG_PREFIX:-$HOME/.npm-global}"
  bin_dir="$npm_prefix/bin"
  mkdir -p "$npm_prefix" "$bin_dir" 2>/dev/null || true
  npm config set prefix "$npm_prefix" >/dev/null 2>&1 || true

  # Ensure npm global bin and ~/.local/bin are in PATH for this session
  if [[ ":$PATH:" != *":$bin_dir:"* ]]; then
    export PATH="$bin_dir:$PATH"
  fi
  if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    export PATH="$HOME/.local/bin:$PATH"
  fi

  # Persist PATH additions to .bashrc for interactive shells
  BASHRC="$HOME/.bashrc"
  if [[ -f "$BASHRC" ]]; then
    if ! grep -q '\.local/bin' "$BASHRC" 2>/dev/null; then
      log_info "Adding ~/.local/bin to .bashrc"
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$BASHRC"
    fi
    if ! grep -q '\.npm-global/bin' "$BASHRC" 2>/dev/null; then
      log_info "Adding ~/.npm-global/bin to .bashrc"
      echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$BASHRC"
    fi
  fi

  log_info "PATH for AI CLI installs: $PATH"

  # Claude CLI via npm
  if ! command -v claude >/dev/null 2>&1; then
    log_info "Installing Claude CLI via npm..."
    if timeout 120 npm install -g @anthropic-ai/claude-code 2>&1; then
      log_info "Claude CLI installed: $(command -v claude || echo 'not in PATH yet')"
    else
      log_err "FAILED: Claude CLI installation"
      FAILED_STEPS+=("claude-cli")
    fi
  else
    log_info "Claude CLI already installed."
  fi

  # Gemini CLI via npm (timeout 600s - large package)
  log_info "Installing Gemini CLI (this may take several minutes)..."
  if ! timeout 600 npm install -g @google/gemini-cli 2>&1; then
    log_err "FAILED: Gemini CLI installation (npm install failed)"
    FAILED_STEPS+=("gemini-cli")
  elif ! command -v gemini >/dev/null 2>&1; then
    log_err "FAILED: Gemini CLI installation (binary not found after install)"
    FAILED_STEPS+=("gemini-cli")
  else
    log_info "Gemini CLI installed: $(command -v gemini)"
  fi

  # Codexaw (forked)
  log_info "Installing Codexaw CLI..."
  if timeout 120 npm install -g https://github.com/digitalsoftwaresolutionsrepos/codex/releases/latest/download/codexaw.tgz; then
    if [ -x "$bin_dir/codex" ]; then
      mv "$bin_dir/codex" "$bin_dir/codexaw" >/dev/null 2>&1 || true
    fi
  else
    log_err "FAILED: Codexaw CLI installation"
    FAILED_STEPS+=("codexaw-cli")
  fi

  # Official Codex (upstream)
  log_info "Installing Codex CLI..."
  if ! timeout 120 npm install -g @openai/codex; then
    log_err "FAILED: Codex CLI installation"
    FAILED_STEPS+=("codex-cli")
  fi

  # Verify AI CLI binaries are available
  log_info "Verifying AI CLI installations..."
  if ! command -v claude >/dev/null 2>&1; then
    log_err "VERIFICATION FAILED: claude not found in PATH"
    FAILED_STEPS+=("claude-verify")
  fi
  if ! command -v gemini >/dev/null 2>&1; then
    log_err "VERIFICATION FAILED: gemini not found in PATH"
    FAILED_STEPS+=("gemini-verify")
  fi
  if ! command -v codex >/dev/null 2>&1; then
    log_err "VERIFICATION FAILED: codex not found in PATH"
    FAILED_STEPS+=("codex-verify")
  fi
}

# --- Main ---
main() {
  if [[ "$QUICK_MODE" == "0" ]]; then
    install_npm
    install_ai_clis
  fi

  # Check for AI CLI failures
  if [[ "$QUICK_MODE" != "1" ]] && [[ "${SKIP_AI_CLIS:-0}" != "1" ]] && (( ${#FAILED_STEPS[@]} > 0 )); then
    log_err "=========================================="
    log_err "POST-CREATE FAILED: AI CLI installation errors"
    log_err "Failed steps: ${FAILED_STEPS[*]}"
    log_err "=========================================="
    exit 1
  fi

  echo "=== Post-Create Complete ==="
}

main "$@"
