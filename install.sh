#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Devstation Setup - Interactive Installer
# =============================================================================
# This script sets up a fresh Linux VM as a devcontainer development station.
# It installs Docker, Node.js, devcontainer CLI, clones repos, and configures
# management scripts and shell customizations.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODE_DIR="${HOME}/code"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# =============================================================================
# OS Detection and Validation
# =============================================================================

detect_os() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_VERSION="${VERSION_ID:-unknown}"
    OS_NAME="${PRETTY_NAME:-$ID $VERSION_ID}"
  else
    log_error "Cannot detect OS (no /etc/os-release)"
    exit 1
  fi
}

validate_os() {
  detect_os
  log_info "Detected OS: $OS_NAME"

  case "$OS_ID" in
    ubuntu|debian)
      log_success "Supported OS detected"
      ;;
    *)
      log_error "Unsupported OS: $OS_ID"
      log_error "This installer requires Ubuntu or Debian."
      exit 1
      ;;
  esac
}

# =============================================================================
# Package Installation
# =============================================================================

install_base_packages() {
  log_info "Installing base packages..."

  sudo apt-get update
  sudo apt-get install -y \
    curl wget ca-certificates gnupg lsb-release \
    git git-lfs \
    build-essential gcc g++ make \
    jq unzip

  git lfs install --system 2>/dev/null || true
  log_success "Base packages installed"
}

install_docker() {
  if command -v docker &>/dev/null; then
    log_info "Docker already installed: $(docker --version)"
    return 0
  fi

  log_info "Installing Docker CE..."

  # Add Docker's official GPG key
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/${OS_ID}/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  # Add the repository
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS_ID} \
    $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # Add current user to docker group
  sudo usermod -aG docker "$USER"
  log_warn "Added $USER to docker group. You may need to log out and back in for this to take effect."

  log_success "Docker installed: $(docker --version)"
}

install_nodejs() {
  if command -v node &>/dev/null; then
    local node_ver
    node_ver=$(node --version)
    local major_ver="${node_ver%%.*}"
    major_ver="${major_ver#v}"

    if [[ "$major_ver" -ge 18 ]]; then
      log_info "Node.js already installed: $node_ver"
      return 0
    fi
  fi

  log_info "Installing Node.js 20 LTS..."

  # NodeSource setup
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y nodejs

  log_success "Node.js installed: $(node --version)"
}

install_gh_cli() {
  if command -v gh &>/dev/null; then
    log_info "GitHub CLI already installed: $(gh --version | head -1)"
    return 0
  fi

  log_info "Installing GitHub CLI..."

  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
    sudo tee /usr/share/keyrings/githubcli-archive-keyring.gpg > /dev/null
  sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
    sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null

  sudo apt-get update
  sudo apt-get install -y gh

  log_success "GitHub CLI installed: $(gh --version | head -1)"
}

install_devcontainer_cli() {
  if command -v devcontainer &>/dev/null; then
    log_info "@devcontainers/cli already installed: $(devcontainer --version)"
    return 0
  fi

  log_info "Installing @devcontainers/cli..."
  sudo npm install -g @devcontainers/cli

  log_success "@devcontainers/cli installed: $(devcontainer --version)"
}

# =============================================================================
# GitHub Authentication
# =============================================================================

check_gh_auth() {
  if gh auth status &>/dev/null; then
    log_success "GitHub CLI is authenticated"
    return 0
  fi

  log_warn "GitHub CLI is not authenticated"
  echo ""
  echo "Please run: gh auth login"
  echo "Choose: GitHub.com > HTTPS > Authenticate with a web browser"
  echo ""
  read -rp "Press Enter after you've authenticated, or Ctrl+C to skip repo selection..."

  if ! gh auth status &>/dev/null; then
    log_error "Still not authenticated. Skipping repo selection."
    return 1
  fi
  return 0
}

# =============================================================================
# Repository Discovery and Selection
# =============================================================================

discover_repos_with_devcontainer() {
  local gh_target="$1"  # username or org
  local repos=()

  log_info "Searching for repos with .devcontainer/ in $gh_target..."

  # Get all repos for the user/org
  local all_repos
  all_repos=$(gh repo list "$gh_target" --limit 100 --json name,isArchived --jq '.[] | select(.isArchived == false) | .name' 2>/dev/null || echo "")

  if [[ -z "$all_repos" ]]; then
    log_warn "No repos found for $gh_target"
    return
  fi

  # Check each repo for .devcontainer folder
  local count=0
  local total
  total=$(echo "$all_repos" | wc -l)

  while IFS= read -r repo; do
    ((count++)) || true
    printf "\r  Checking repo %d/%d: %-50s" "$count" "$total" "$repo"

    # Try to list .devcontainer directory
    if gh api "repos/$gh_target/$repo/contents/.devcontainer" &>/dev/null; then
      repos+=("$repo")
    fi
  done <<< "$all_repos"

  echo ""  # Clear the progress line

  if [[ ${#repos[@]} -eq 0 ]]; then
    log_warn "No repos with .devcontainer/ found"
  else
    log_success "Found ${#repos[@]} repos with devcontainer configs"
    echo ""
    printf '%s\n' "${repos[@]}"
  fi
}

select_repos() {
  local gh_target="$1"
  shift
  local repos=("$@")
  local selected=()

  if [[ ${#repos[@]} -eq 0 ]]; then
    return
  fi

  echo ""
  echo "Select repos to clone (space to toggle, Enter to confirm):"
  echo ""

  local checked=()
  for ((i=0; i<${#repos[@]}; i++)); do
    checked[$i]=0
  done

  local current=0
  local done=0

  # Simple selection interface
  while [[ $done -eq 0 ]]; do
    # Clear and redraw
    echo -e "\033[2J\033[H"  # Clear screen
    echo "Select repos to clone from $gh_target:"
    echo "(Use number to toggle, 'a' for all, 'n' for none, Enter to confirm)"
    echo ""

    for ((i=0; i<${#repos[@]}; i++)); do
      local marker="[ ]"
      if [[ ${checked[$i]} -eq 1 ]]; then
        marker="[x]"
      fi
      echo "  $((i+1)). $marker ${repos[$i]}"
    done

    echo ""
    read -rp "Selection (1-${#repos[@]}/a/n/Enter): " choice

    case "$choice" in
      "")
        done=1
        ;;
      a|A)
        for ((i=0; i<${#repos[@]}; i++)); do
          checked[$i]=1
        done
        ;;
      n|N)
        for ((i=0; i<${#repos[@]}; i++)); do
          checked[$i]=0
        done
        ;;
      [0-9]*)
        local idx=$((choice - 1))
        if [[ $idx -ge 0 && $idx -lt ${#repos[@]} ]]; then
          if [[ ${checked[$idx]} -eq 0 ]]; then
            checked[$idx]=1
          else
            checked[$idx]=0
          fi
        fi
        ;;
    esac
  done

  # Collect selected repos
  for ((i=0; i<${#repos[@]}; i++)); do
    if [[ ${checked[$i]} -eq 1 ]]; then
      selected+=("${repos[$i]}")
    fi
  done

  printf '%s\n' "${selected[@]}"
}

clone_repos() {
  local gh_target="$1"
  shift
  local repos=("$@")

  if [[ ${#repos[@]} -eq 0 ]]; then
    log_info "No repos selected for cloning"
    return
  fi

  mkdir -p "$CODE_DIR"

  log_info "Cloning ${#repos[@]} repos to $CODE_DIR..."

  for repo in "${repos[@]}"; do
    local repo_path="$CODE_DIR/$repo"
    if [[ -d "$repo_path" ]]; then
      log_info "  $repo - already exists, skipping"
    else
      log_info "  Cloning $repo..."
      gh repo clone "$gh_target/$repo" "$repo_path" -- --depth=1
    fi
  done

  log_success "Repos cloned to $CODE_DIR"
}

# =============================================================================
# Script and Config Installation
# =============================================================================

install_scripts() {
  log_info "Installing management scripts to ~/ (as symlinks)"

  local scripts=(
    "devcontainer-rebuild.sh"
    "devcontainer-open.sh"
    "devcontainer-stop-all.sh"
    "devcontainer-cleanup.sh"
    "devcontainer-start-all.sh"
    "dexec"
  )

  for script in "${scripts[@]}"; do
    if [[ -f "$SCRIPT_DIR/scripts/$script" ]]; then
      # Remove existing file/symlink and create new symlink
      rm -f "$HOME/$script"
      ln -s "$SCRIPT_DIR/scripts/$script" "$HOME/$script"
      log_success "  Linked ~/$script -> $SCRIPT_DIR/scripts/$script"
    else
      log_warn "  Script not found: $script"
    fi
  done
}

install_bashrc_additions() {
  local bashrc="$HOME/.bashrc"
  local marker="# === DEVSTATION CUSTOMIZATIONS ==="

  if grep -q "$marker" "$bashrc" 2>/dev/null; then
    log_info "Bashrc customizations already present"
    return
  fi

  log_info "Adding customizations to ~/.bashrc..."

  {
    echo ""
    echo "$marker"
    cat "$SCRIPT_DIR/config/bashrc-additions"
    echo "$marker END"
  } >> "$bashrc"

  log_success "Bashrc customizations added"
}

generate_repo_aliases() {
  local bashrc="$HOME/.bashrc"

  if [[ ! -d "$CODE_DIR" ]]; then
    return
  fi

  log_info "Generating repo-specific aliases..."

  local aliases=""
  for repo_path in "$CODE_DIR"/*/; do
    if [[ -d "${repo_path}.devcontainer" ]]; then
      local name
      name=$(basename "$repo_path")
      local alias_name
      # Convert to lowercase and replace non-alphanumeric with dashes
      alias_name=$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')
      aliases+="alias dexec-${alias_name}='dexec ~/code/${name}'\n"
    fi
  done

  if [[ -n "$aliases" ]]; then
    # Remove old generated aliases section if it exists
    sed -i '/^# === GENERATED REPO ALIASES ===/,/^# === GENERATED REPO ALIASES END ===/d' "$bashrc" 2>/dev/null || true

    # Add new aliases
    {
      echo ""
      echo "# === GENERATED REPO ALIASES ==="
      echo -e "$aliases"
      echo "# === GENERATED REPO ALIASES END ==="
    } >> "$bashrc"

    log_success "Generated dexec aliases for repos in ~/code"
  fi
}

# =============================================================================
# Optional: Initial Build
# =============================================================================

prompt_initial_build() {
  echo ""
  read -rp "Build devcontainers now? This can take a while. (y/N): " choice

  case "$choice" in
    y|Y)
      log_info "Starting devcontainer builds..."
      if [[ -x "$HOME/devcontainer-rebuild.sh" ]]; then
        "$HOME/devcontainer-rebuild.sh" "$CODE_DIR" --fast
      else
        log_warn "devcontainer-rebuild.sh not found"
      fi
      ;;
    *)
      echo ""
      echo "You can build later with:"
      echo "  ~/devcontainer-rebuild.sh ~/code"
      echo ""
      ;;
  esac
}

# =============================================================================
# Main
# =============================================================================

main() {
  echo ""
  echo "=============================================="
  echo "  Devstation Setup - Interactive Installer"
  echo "=============================================="
  echo ""

  # Step 1: Validate OS
  validate_os

  # Step 2: Install packages
  echo ""
  echo "--- Installing Dependencies ---"
  install_base_packages
  install_docker
  install_nodejs
  install_gh_cli
  install_devcontainer_cli

  # Step 3: GitHub auth and repo selection
  echo ""
  echo "--- GitHub Repository Setup ---"

  if check_gh_auth; then
    read -rp "Enter GitHub username or organization: " gh_target

    if [[ -n "$gh_target" ]]; then
      # Discover repos
      mapfile -t discovered_repos < <(discover_repos_with_devcontainer "$gh_target")

      if [[ ${#discovered_repos[@]} -gt 0 ]]; then
        # Select repos
        mapfile -t selected_repos < <(select_repos "$gh_target" "${discovered_repos[@]}")

        # Clone selected repos
        clone_repos "$gh_target" "${selected_repos[@]}"
      fi
    fi
  else
    log_warn "Skipping repo discovery (not authenticated)"
  fi

  # Step 4: Install scripts and configs
  echo ""
  echo "--- Installing Scripts and Configuration ---"
  install_scripts
  install_bashrc_additions
  generate_repo_aliases

  # Step 5: Optional build
  prompt_initial_build

  # Done
  echo ""
  echo "=============================================="
  echo "  Setup Complete!"
  echo "=============================================="
  echo ""
  echo "Next steps:"
  echo "  1. Log out and back in (for docker group)"
  echo "  2. Run: source ~/.bashrc"
  echo "  3. Build containers: ~/devcontainer-rebuild.sh ~/code"
  echo "  4. Shell into a container: ~/dexec ~/code/MyRepo"
  echo ""
  echo "See ~/devstation-setup/docs/ for more documentation."
  echo ""
}

main "$@"
