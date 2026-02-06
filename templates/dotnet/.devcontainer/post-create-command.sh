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

# --- Fix Volume Permissions ---
# Docker volumes may be created with different UID ownership
# Fix npm cache and nuget cache permissions if they exist
fix_permissions() {
  log_info "Fixing volume permissions..."
  # Fix Docker volumes
  if [[ -d "$HOME/.npm" ]]; then
    sudo chown -R "$(id -u):$(id -g)" "$HOME/.npm" 2>/dev/null || true
  fi
  if [[ -d "$HOME/.nuget" ]]; then
    sudo chown -R "$(id -u):$(id -g)" "$HOME/.nuget" 2>/dev/null || true
  fi
  if [[ -d "$HOME/.npm-global" ]]; then
    sudo chown -R "$(id -u):$(id -g)" "$HOME/.npm-global" 2>/dev/null || true
  fi
  # NOTE: Do NOT chown ~/.claude or ~/.codex - they are bind mounts from host
  # Changing their ownership would lock out the host user
  # Create ~/.local/bin for Claude CLI
  mkdir -p "$HOME/.local/bin" 2>/dev/null || true
}

fix_permissions

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

# --- Language Servers for Claude Code ---
install_language_servers() {
  log_info "Installing language servers for Claude Code plugins..."

  # Ensure dotnet tools and npm-global are in PATH for all processes (including Claude)
  DOTNET_TOOLS="$HOME/.dotnet/tools"
  NPM_GLOBAL="$HOME/.npm-global/bin"

  # Update /etc/environment for all processes
  if [[ -f /etc/environment ]] && ! grep -q "$NPM_GLOBAL" /etc/environment 2>/dev/null; then
    log_info "Adding $NPM_GLOBAL to /etc/environment PATH"
    sudo sed -i "s|PATH=\"\\(.*\\)\"|PATH=\"$NPM_GLOBAL:\\1\"|" /etc/environment 2>/dev/null || true
  fi

  # Also add to .bashrc for interactive shells
  if [[ -f "$HOME/.bashrc" ]] && ! grep -q '\.dotnet/tools' "$HOME/.bashrc" 2>/dev/null; then
    log_info "Adding ~/.dotnet/tools to .bashrc"
    echo 'export PATH="$HOME/.dotnet/tools:$PATH"' >> "$HOME/.bashrc"
  fi

  # Set PATH for current session
  if [[ ":$PATH:" != *":$DOTNET_TOOLS:"* ]]; then
    export PATH="$DOTNET_TOOLS:$PATH"
  fi
  if [[ ":$PATH:" != *":$NPM_GLOBAL:"* ]]; then
    export PATH="$NPM_GLOBAL:$PATH"
  fi

  # C# Language Server (requires .NET 8.0 runtime - already in base image)
  if ! command -v csharp-ls >/dev/null 2>&1; then
    log_info "Installing csharp-ls..."
    if dotnet tool install --global csharp-ls 2>&1; then
      log_info "csharp-ls installed"
    else
      log_err "FAILED: csharp-ls installation"
      FAILED_STEPS+=("csharp-ls")
    fi
  else
    log_info "csharp-ls already installed."
  fi

  # TypeScript Language Server (dotnet template has Node.js for frontend)
  if ! command -v typescript-language-server >/dev/null 2>&1; then
    log_info "Installing typescript-language-server..."
    if npm install -g typescript-language-server typescript 2>&1; then
      log_info "typescript-language-server installed"
    else
      log_err "FAILED: typescript-language-server installation"
      FAILED_STEPS+=("typescript-language-server")
    fi
  else
    log_info "typescript-language-server already installed."
  fi
}

# --- Main ---
main() {
  setup_postgres

  if [[ "$QUICK_MODE" == "0" ]]; then
    restore_dotnet
    install_npm
    install_language_servers
  fi

  # Check for failures and exit with error if any failed
  if [[ "$QUICK_MODE" != "1" ]] && (( ${#FAILED_STEPS[@]} > 0 )); then
    log_err "=========================================="
    log_err "POST-CREATE FAILED: installation errors"
    log_err "Failed steps: ${FAILED_STEPS[*]}"
    log_err "=========================================="
    exit 1
  fi

  echo "=== Post-Create Complete ==="
}

main "$@"
