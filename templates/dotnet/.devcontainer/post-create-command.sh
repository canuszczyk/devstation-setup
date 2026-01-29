#!/usr/bin/env bash
set -euo pipefail

# Post-create command for .NET devcontainer
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

# --- PostgreSQL Setup ---
setup_postgres() {
  echo "Setting up PostgreSQL..."

  local pgdata="${PGDATA:-/workspaces/$(basename "$PWD")/.devcontainer/pgdata}"

  # Initialize if needed
  if [[ ! -d "$pgdata" || ! -f "$pgdata/PG_VERSION" ]]; then
    echo "Initializing PostgreSQL data directory..."
    mkdir -p "$pgdata"
    initdb -D "$pgdata" --auth=trust --encoding=UTF8
  fi

  # Start PostgreSQL if not running
  if ! pg_isready -q 2>/dev/null; then
    echo "Starting PostgreSQL..."
    pg_ctl -D "$pgdata" -l "$pgdata/logfile" start -w -t 30 || true
  fi

  # Wait for PostgreSQL to be ready
  for i in {1..30}; do
    if pg_isready -q 2>/dev/null; then
      echo "PostgreSQL is ready"
      return 0
    fi
    sleep 1
  done

  echo "Warning: PostgreSQL may not be ready"
}

# --- .NET Restore ---
restore_dotnet() {
  if [[ -f "*.sln" ]] || ls *.csproj 1>/dev/null 2>&1; then
    echo "Restoring .NET packages..."
    dotnet restore || true
  fi
}

# --- npm Install ---
install_npm() {
  if [[ -f "package.json" ]]; then
    echo "Installing npm packages..."
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

  # Claude: use official installer (installs to ~/.local/bin)
  # Note: Download script first, then run - timeout doesn't work with piped commands
  if ! command -v claude >/dev/null 2>&1; then
    log_info "Installing Claude CLI…"
    CLAUDE_SCRIPT=$(mktemp)
    if timeout 30 curl -fsSL https://claude.ai/install.sh -o "$CLAUDE_SCRIPT" 2>/dev/null; then
      if timeout 120 bash "$CLAUDE_SCRIPT"; then
        log_info "Claude CLI installed: $(command -v claude || echo 'not in PATH yet')"
      else
        log_err "FAILED: Claude CLI installation (installer failed or timed out)"
        FAILED_STEPS+=("claude-cli")
      fi
    else
      log_err "FAILED: Claude CLI installation (could not download installer)"
      FAILED_STEPS+=("claude-cli")
    fi
    rm -f "$CLAUDE_SCRIPT"
  else
    log_info "Claude CLI already installed."
  fi

  # Gemini CLI via npm (timeout 600s - large package with 500+ deps, slow on constrained CPUs)
  log_info "Installing Gemini CLI (this may take several minutes)…"
  if ! timeout 600 npm install -g @google/gemini-cli 2>&1; then
    log_err "FAILED: Gemini CLI installation (npm install failed)"
    FAILED_STEPS+=("gemini-cli")
  elif ! command -v gemini >/dev/null 2>&1; then
    log_err "FAILED: Gemini CLI installation (binary not found after install)"
    log_err "  npm prefix: $(npm config get prefix)"
    log_err "  PATH: $PATH"
    FAILED_STEPS+=("gemini-cli")
  else
    log_info "Gemini CLI installed: $(command -v gemini)"
  fi

  # Codexaw (forked) - install first, then rename binary (timeout 120s)
  log_info "Installing Codexaw CLI…"
  if timeout 120 npm install -g https://github.com/digitalsoftwaresolutionsrepos/codex/releases/latest/download/codexaw.tgz; then
    if [ -x "$bin_dir/codex" ]; then
      mv "$bin_dir/codex" "$bin_dir/codexaw" >/dev/null 2>&1 || true
    fi
  else
    log_err "FAILED: Codexaw CLI installation"
    FAILED_STEPS+=("codexaw-cli")
  fi

  # Official Codex (upstream) (timeout 120s)
  log_info "Installing Codex CLI…"
  if ! timeout 120 npm install -g @openai/codex; then
    log_err "FAILED: Codex CLI installation"
    FAILED_STEPS+=("codex-cli")
  fi

  # Verify AI CLI binaries are available
  log_info "Verifying AI CLI installations…"
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
  setup_postgres

  if [[ "$QUICK_MODE" == "0" ]]; then
    restore_dotnet
    install_npm
    install_ai_clis
  fi

  # Check for AI CLI failures and exit with error if any failed (unless skipped or quick mode)
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
