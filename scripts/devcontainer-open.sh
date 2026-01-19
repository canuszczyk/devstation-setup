#!/usr/bin/env bash
set -euo pipefail

# Start/attach to existing devcontainer(s) for a repo (auto-detects repo root).
# Does NOT launch VS Code.
# If the container doesn't exist, exits non-zero.
#
# If <path> is a directory containing multiple repos (subdirs with .devcontainer),
# all existing containers will be started.

INPUT_PATH="${1:-.}"
INPUT_PATH="$(cd "$INPUT_PATH" && pwd)"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1"
    exit 1
  }
}

find_repo_root() {
  local p="$1"

  if git -C "$p" rev-parse --show-toplevel >/dev/null 2>&1; then
    git -C "$p" rev-parse --show-toplevel
    return 0
  fi

  local cur="$p"
  while true; do
    if [ -f "$cur/.devcontainer/devcontainer.json" ]; then
      echo "$cur"
      return 0
    fi
    if [ "$cur" = "/" ]; then
      break
    fi
    cur="$(dirname "$cur")"
  done

  echo ""
  return 1
}

calc_id_label() {
  local root="$1"

  local key="${DEVCONTAINER_ID_LABEL_KEY:-com.devcontainer.repo}"
  local remote=""
  if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    remote="$(git -C "$root" config --get remote.origin.url || true)"
  fi

  local basis=""
  if [ -n "$remote" ]; then
    basis="$remote"
    basis="${basis#ssh://}"
    basis="${basis#https://}"
    basis="${basis#http://}"
    basis="${basis%.git}"
    basis="${basis%/}"
  else
    basis="$(basename "$root")"
  fi

  local hash=""
  if command -v sha256sum >/dev/null 2>&1; then
    hash="$(printf '%s' "$basis" | sha256sum | awk '{print $1}' | cut -c1-16)"
  elif command -v shasum >/dev/null 2>&1; then
    hash="$(printf '%s' "$basis" | shasum -a 256 | awk '{print $1}' | cut -c1-16)"
  else
    hash="$(printf '%s' "$basis" | cksum | awk '{print $1}')"
  fi

  local val="${DEVCONTAINER_ID_LABEL_PREFIX:-repo}-${hash}"
  echo "${key}=${val}"
}

# Find all repos with devcontainers in a directory
find_repos_in_dir() {
  local dir="$1"
  local repos=()

  for subdir in "$dir"/*/; do
    if [[ -d "$subdir" && -f "${subdir}.devcontainer/devcontainer.json" ]]; then
      repos+=("${subdir%/}")
    fi
  done

  printf '%s\n' "${repos[@]}"
}

# Check if path is itself a repo or a parent of multiple repos
is_multi_repo_dir() {
  local dir="$1"

  # If this directory itself has a devcontainer, it's a single repo
  if [[ -f "$dir/.devcontainer/devcontainer.json" ]]; then
    return 1
  fi

  # If this directory is inside a git repo, it's a single repo
  if git -C "$dir" rev-parse --show-toplevel >/dev/null 2>&1; then
    return 1
  fi

  # Check if any subdirectories have devcontainers
  for subdir in "$dir"/*/; do
    if [[ -d "$subdir" && -f "${subdir}.devcontainer/devcontainer.json" ]]; then
      return 0
    fi
  done

  return 1
}

# Open a single repo's container
open_single_repo() {
  local repo_root="$1"
  local prefix="${2:-}"

  local id_label
  id_label="$(calc_id_label "$repo_root")"

  local key="${id_label%%=*}"
  local val="${id_label#*=}"

  local cid
  cid="$(docker ps -aq --filter "label=$key=$val" | head -n 1 || true)"
  if [ -z "${cid:-}" ]; then
    echo "${prefix}No existing devcontainer found for:"
    echo "${prefix}  $repo_root"
    echo "${prefix}Expected docker container labeled:"
    echo "${prefix}  $id_label"
    return 1
  fi

  echo "${prefix}Repo root: $repo_root"
  echo "${prefix}Using id-label: $id_label"
  echo "${prefix}Found container: $cid"

  # Ensure it's running
  local running
  running="$(docker inspect -f '{{.State.Running}}' "$cid" 2>/dev/null || echo "false")"
  if [ "$running" != "true" ]; then
    echo "${prefix}Starting container..."
    docker start "$cid" >/dev/null
  fi

  # Optional: run your "post start" behavior (your script supports --quick)
  if [ "${DEVCONTAINER_SKIP_QUICK:-0}" != "1" ]; then
    local ws_in_container="${DEVCONTAINER_WORKSPACE_FOLDER:-/workspaces/$(basename "$repo_root")}"
    if docker exec "$cid" test -f "$ws_in_container/scripts/post-create-command.sh" >/dev/null 2>&1; then
      echo "${prefix}Running quick bootstrap in container..."
      docker exec -u vscode -w "$ws_in_container" "$cid" bash -lc "chmod +x scripts/post-create-command.sh && bash scripts/post-create-command.sh --quick" || true
    fi
  fi

  return 0
}

main() {
  require devcontainer
  require docker

  # Check if we're in multi-repo mode
  if is_multi_repo_dir "$INPUT_PATH"; then
    echo "=== Multi-repo mode ==="
    echo "Opening all devcontainers in: $INPUT_PATH"
    echo ""

    mapfile -t repos < <(find_repos_in_dir "$INPUT_PATH")

    if (( ${#repos[@]} == 0 )); then
      echo "No repos with devcontainers found in: $INPUT_PATH"
      exit 1
    fi

    echo "Found ${#repos[@]} repo(s):"
    for repo in "${repos[@]}"; do
      echo "  - $(basename "$repo")"
    done
    echo ""

    # Track results using simple arrays (more reliable than associative arrays)
    local success_repos=()
    local missing_repos=()

    for repo in "${repos[@]}"; do
      local name
      name="$(basename "$repo")"

      echo "[$name] Opening..."
      if open_single_repo "$repo" "[$name] "; then
        success_repos+=("$repo")
        echo "[$name] Container started"
      else
        missing_repos+=("$repo")
        echo "[$name] No container found (run rebuild first)"
      fi
      echo ""
    done

    echo "=== Summary ==="
    echo ""

    local success_count=${#success_repos[@]}
    local missing_count=${#missing_repos[@]}

    for repo in "${success_repos[@]}"; do
      echo "✓ $(basename "$repo")"
    done
    for repo in "${missing_repos[@]}"; do
      echo "✗ $(basename "$repo") (no container)"
    done

    echo ""
    echo "Results: $success_count running, $missing_count missing"
    echo ""

    # Show attach instructions for running containers
    if (( success_count > 0 )); then
      echo "=== Attach Instructions ==="
      echo ""
      for repo in "${success_repos[@]}"; do
        echo "$(basename "$repo"):"
        echo "  /home/vscode/dexec $repo"
        echo ""
      done
    fi

    # Show rebuild hint for missing containers
    if (( missing_count > 0 )); then
      echo "To build missing containers:"
      echo "  ~/devcontainer-rebuild.sh $INPUT_PATH"
    fi

    if (( success_count == 0 )); then
      exit 1
    fi
  else
    # Single repo mode (original behavior)
    local repo_root
    repo_root="$(find_repo_root "$INPUT_PATH")" || true
    if [ -z "${repo_root:-}" ]; then
      echo "Could not determine repo root from: $INPUT_PATH"
      exit 2
    fi

    if [ ! -f "$repo_root/.devcontainer/devcontainer.json" ]; then
      echo "No devcontainer found at: $repo_root/.devcontainer/devcontainer.json"
      exit 3
    fi

    local id_label
    id_label="$(calc_id_label "$repo_root")"

    local key="${id_label%%=*}"
    local val="${id_label#*=}"

    local cid
    cid="$(docker ps -aq --filter "label=$key=$val" | head -n 1 || true)"
    if [ -z "${cid:-}" ]; then
      echo "No existing devcontainer found for:"
      echo "  $repo_root"
      echo "Expected docker container labeled:"
      echo "  $id_label"
      echo
      echo "Run rebuild/start first, e.g.:"
      echo "  $(dirname "$0")/devcontainer-rebuild.sh \"$repo_root\""
      exit 4
    fi

    echo "Repo root: $repo_root"
    echo "Using id-label: $id_label"
    echo "Found container: $cid"

    # Ensure it's running
    local running
    running="$(docker inspect -f '{{.State.Running}}' "$cid" 2>/dev/null || echo "false")"
    if [ "$running" != "true" ]; then
      echo "Starting container..."
      docker start "$cid" >/dev/null
    fi

    # Optional: run your "post start" behavior (your script supports --quick)
    if [ "${DEVCONTAINER_SKIP_QUICK:-0}" != "1" ]; then
      local ws_in_container="${DEVCONTAINER_WORKSPACE_FOLDER:-/workspaces/$(basename "$repo_root")}"
      if docker exec "$cid" test -f "$ws_in_container/scripts/post-create-command.sh" >/dev/null 2>&1; then
        echo "Running quick bootstrap in container..."
        docker exec -u vscode -w "$ws_in_container" "$cid" bash -lc "chmod +x scripts/post-create-command.sh && bash scripts/post-create-command.sh --quick" || true
      fi
    fi

    echo
    echo "Shell into it:"
    echo "  /home/vscode/dexec $repo_root"
  fi
}

main "$@"
