#!/usr/bin/env bash
set -euo pipefail

# Post-create command for .NET devcontainer
# Usage: ./post-create-command.sh [--quick]

QUICK_MODE=0
if [[ "${1:-}" == "--quick" ]]; then
  QUICK_MODE=1
fi

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

# --- Main ---
main() {
  setup_postgres

  if [[ "$QUICK_MODE" == "0" ]]; then
    restore_dotnet
    install_npm
  fi

  echo "=== Post-Create Complete ==="
}

main "$@"
