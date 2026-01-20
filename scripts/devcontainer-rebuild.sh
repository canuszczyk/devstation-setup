#!/usr/bin/env bash
set -euo pipefail

# devcontainer-rebuild.sh
# Rebuild + start a devcontainer for a repo (auto-detects repo root).
# Does NOT launch VS Code.
#
# Usage:
#   devcontainer-rebuild.sh [--force] [--prune] <path>
#   devcontainer-rebuild.sh [--force] [--prune]            # defaults to "."
#
# If <path> is a directory containing multiple repos (subdirs with .devcontainer),
# all repos will be built in parallel with the same flags.
#
# Flags:
#   --force  : remove existing container(s), images, and volumes + rebuild with no Docker cache
#   --prune  : additionally run "docker image prune -f" after removing labeled images (more aggressive)

INPUT_PATH="."
FORCE=0
PRUNE=0
SKIP_AI_CLIS=0
SKIP_PLAYWRIGHT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --prune) PRUNE=1; shift ;;
    --skip-ai-clis) SKIP_AI_CLIS=1; shift ;;
    --skip-playwright) SKIP_PLAYWRIGHT=1; shift ;;
    --fast) SKIP_AI_CLIS=1; SKIP_PLAYWRIGHT=1; shift ;;
    -h|--help)
      echo "Usage: $0 [--force] [--prune] [--skip-ai-clis] [--skip-playwright] [--fast] [path]"
      echo ""
      echo "If path contains multiple repos (subdirs with .devcontainer), all will be built."
      echo ""
      echo "Flags:"
      echo "  --force          Remove containers/images/volumes and rebuild with no cache"
      echo "  --prune          Additionally prune dangling images after removal"
      echo "  --skip-ai-clis   Skip installing AI CLIs (claude, gemini, codex)"
      echo "  --skip-playwright Skip installing Playwright browser"
      echo "  --fast           Skip both AI CLIs and Playwright (fastest rebuild)"
      exit 0
      ;;
    *)
      INPUT_PATH="$1"
      shift
      ;;
  esac
done

INPUT_PATH="$(cd "$INPUT_PATH" && pwd)"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1"
    exit 1
  }
}

find_repo_root() {
  local p="$1"

  # 1) If in a git repo, use git root
  if git -C "$p" rev-parse --show-toplevel >/dev/null 2>&1; then
    git -C "$p" rev-parse --show-toplevel
    return 0
  fi

  # 2) Walk up looking for .devcontainer/devcontainer.json
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

remove_labeled_containers_and_images() {
  local id_label="$1"
  local repo_root="$2"
  local key="${id_label%%=*}"
  local val="${id_label#*=}"

  # Containers (running or stopped)
  mapfile -t cids < <(docker ps -aq --filter "label=$key=$val" || true)
  if (( ${#cids[@]} > 0 )); then
    echo "Removing existing container(s) for label $id_label:"
    printf '  %s\n' "${cids[@]}"
    docker rm -f "${cids[@]}" >/dev/null 2>&1 || true
  fi

  # Images built for this devcontainer label (best-effort)
  mapfile -t iids < <(docker images -q --filter "label=$key=$val" || true)
  if (( ${#iids[@]} > 0 )); then
    echo "Removing existing image(s) for label $id_label:"
    printf '  %s\n' "${iids[@]}"
    docker rmi -f "${iids[@]}" >/dev/null 2>&1 || true
  fi

  # Remove associated Docker volumes (nuget, npm cache, etc.) to ensure clean rebuild
  local folder_basename
  folder_basename="$(basename "$repo_root")"
  local volume_prefix="${folder_basename}-"
  mapfile -t vols < <(docker volume ls -q --filter "name=${volume_prefix}" 2>/dev/null || true)
  if (( ${#vols[@]} > 0 )); then
    echo "Removing associated Docker volume(s) for prefix '$volume_prefix':"
    printf '  %s\n' "${vols[@]}"
    docker volume rm "${vols[@]}" >/dev/null 2>&1 || true
  fi

  if [[ "$PRUNE" == "1" ]]; then
    echo "Pruning dangling images (docker image prune -f)..."
    docker image prune -f >/dev/null 2>&1 || true
  fi
}

# Verify that required tools are available in the container
# Returns: "OK" on success, "MISSING: tool1 tool2" on failure
verify_container() {
  local cid="$1"
  local skip_ai="${2:-0}"

  local verify_cmd='
    # Ensure common install locations are in PATH
    export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"
    MISSING=()
    for cmd in dotnet node npm; do
      command -v "$cmd" >/dev/null 2>&1 || MISSING+=("$cmd")
    done
    if [[ "'"$skip_ai"'" != "1" ]]; then
      for cmd in claude gemini codex; do
        command -v "$cmd" >/dev/null 2>&1 || MISSING+=("$cmd")
      done
    fi
    if (( ${#MISSING[@]} > 0 )); then
      echo "MISSING: ${MISSING[*]}"
      exit 1
    fi
    echo "OK"
  '
  docker exec "$cid" bash -c "$verify_cmd" 2>/dev/null
}

# Build a single repo - used for both single and multi-repo modes
# Sets BUILD_VERIFY_RESULT to "OK" or "MISSING: ..." after build
build_single_repo() {
  local repo_root="$1"
  local force="$2"
  local prune="$3"
  local prefix="${4:-}"  # Optional prefix for output (e.g., "[RepoName] ")

  local id_label
  id_label="$(calc_id_label "$repo_root")"

  echo "${prefix}Repo root: $repo_root"
  echo "${prefix}Using id-label: $id_label"

  if [[ "$force" == "1" ]]; then
    echo "${prefix}FORCE=1: removing labeled containers + images + volumes and rebuilding with --build-no-cache"
    # Temporarily set PRUNE for the removal function
    PRUNE="$prune" remove_labeled_containers_and_images "$id_label" "$repo_root"
  fi

  echo "${prefix}Starting devcontainer up..."
  if [[ "$force" == "1" ]]; then
    devcontainer up \
      --workspace-folder "$repo_root" \
      --id-label "$id_label" \
      --remove-existing-container \
      --build-no-cache
  else
    devcontainer up \
      --workspace-folder "$repo_root" \
      --id-label "$id_label" \
      --remove-existing-container
  fi

  echo "${prefix}Devcontainer is up."

  # Verify container has required tools
  local key="${id_label%%=*}"
  local val="${id_label#*=}"
  local cid
  cid="$(docker ps -aq --filter "label=$key=$val" | head -n 1 || true)"

  if [ -n "${cid:-}" ]; then
    echo "${prefix}Verifying container tools..."
    BUILD_VERIFY_RESULT="$(verify_container "$cid" "${SKIP_AI_CLIS:-0}")"
    if [[ "$BUILD_VERIFY_RESULT" == "OK" ]]; then
      echo "${prefix}Verification: all tools present"
    else
      echo "${prefix}Verification FAILED: $BUILD_VERIFY_RESULT"
      return 1
    fi
  else
    BUILD_VERIFY_RESULT="MISSING: container not found"
    echo "${prefix}Verification FAILED: could not find container"
    return 1
  fi
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

main() {
  require devcontainer
  require docker
  require git

  # Check if we're in multi-repo mode
  if is_multi_repo_dir "$INPUT_PATH"; then
    echo "=== Multi-repo mode ==="
    echo "Building all devcontainers in: $INPUT_PATH"
    echo "Flags: FORCE=$FORCE PRUNE=$PRUNE SKIP_AI_CLIS=$SKIP_AI_CLIS SKIP_PLAYWRIGHT=$SKIP_PLAYWRIGHT"
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

    # Create temp dir for results tracking
    local result_dir
    result_dir="$(mktemp -d)"

    local pids=()
    local repo_paths=()

    # Start all builds in parallel - output streams directly to terminal with prefix
    for repo in "${repos[@]}"; do
      local name
      name="$(basename "$repo")"
      repo_paths+=("$repo")

      echo "[$name] Starting build..."
      (
        set -o pipefail
        export SKIP_AI_CLIS="$SKIP_AI_CLIS"
        export SKIP_PLAYWRIGHT="$SKIP_PLAYWRIGHT"
        export BUILD_VERIFY_RESULT=""
        # Run build and prefix all output with repo name
        if build_single_repo "$repo" "$FORCE" "$PRUNE" "" 2>&1 | sed "s/^/[$name] /"; then
          touch "$result_dir/$name.success"
          echo "all tools verified" > "$result_dir/$name.verify"
        else
          touch "$result_dir/$name.failed"
          # Try to capture verification failure reason from build output
          echo "build or verification failed" > "$result_dir/$name.verify"
        fi
      ) &
      pids+=($!)
    done

    # Wait for all builds
    for i in "${!pids[@]}"; do
      local pid="${pids[$i]}"
      local repo="${repo_paths[$i]}"
      local name
      name="$(basename "$repo")"
      wait "$pid" || true
      if [[ -f "$result_dir/$name.success" ]]; then
        echo "[$name] *** Build completed successfully ***"
      else
        echo "[$name] *** Build FAILED ***"
      fi
    done

    local log_dir="$result_dir"  # For compatibility with cleanup

    echo ""
    echo "=== Build Summary ==="
    echo ""

    local success_count=0
    local fail_count=0

    for repo in "${repo_paths[@]}"; do
      local name
      name="$(basename "$repo")"
      local verify_info=""
      if [[ -f "$log_dir/$name.verify" ]]; then
        verify_info="$(cat "$log_dir/$name.verify")"
      fi
      if [[ -f "$log_dir/$name.success" ]]; then
        ((success_count++)) || true
        echo "✓ $name - $verify_info"
      else
        ((fail_count++)) || true
        echo "✗ $name - $verify_info"
      fi
    done

    echo ""
    echo "Results: $success_count succeeded, $fail_count failed"
    echo ""

    # Show attach instructions for successful builds
    if (( success_count > 0 )); then
      echo "=== Attach Instructions ==="
      echo ""
      for repo in "${repo_paths[@]}"; do
        local name
        name="$(basename "$repo")"
        if [[ -f "$log_dir/$name.success" ]]; then
          echo "$name:"
          echo "  /home/vscode/dexec $repo"
          echo ""
        fi
      done
    fi

    # Note: Build output is shown in real-time above (prefixed with repo name)
    # Failed builds are visible immediately - no need to replay logs

    # Cleanup
    rm -rf "$log_dir"

    if (( fail_count > 0 )); then
      exit 1
    fi
  else
    # Single repo mode (original behavior)
    local repo_root
    repo_root="$(find_repo_root "$INPUT_PATH")" || true
    if [ -z "${repo_root:-}" ]; then
      echo "Could not determine repo root from: $INPUT_PATH"
      echo "Expected either:"
      echo "  - to be inside a git repo, or"
      echo "  - to find .devcontainer/devcontainer.json by walking upward"
      echo "  - or a directory containing multiple repos with devcontainers"
      exit 2
    fi

    if [ ! -f "$repo_root/.devcontainer/devcontainer.json" ]; then
      echo "No devcontainer found at: $repo_root/.devcontainer/devcontainer.json"
      exit 3
    fi

    export SKIP_AI_CLIS="$SKIP_AI_CLIS"
    export SKIP_PLAYWRIGHT="$SKIP_PLAYWRIGHT"
    export BUILD_VERIFY_RESULT=""

    if ! build_single_repo "$repo_root" "$FORCE" "$PRUNE"; then
      echo ""
      echo "=== Build Summary ==="
      echo "✗ $(basename "$repo_root") - build or verification failed"
      exit 1
    fi

    # Print attach instructions
    local id_label
    id_label="$(calc_id_label "$repo_root")"
    local key="${id_label%%=*}"
    local val="${id_label#*=}"
    local cid
    cid="$(docker ps -aq --filter "label=$key=$val" | head -n 1 || true)"

    echo ""
    echo "=== Build Summary ==="
    echo "✓ $(basename "$repo_root") - all tools verified"
    echo ""

    if [ -n "${cid:-}" ]; then
      echo "Container: $cid"
      echo "Attach:"
      echo "  /home/vscode/dexec $repo_root"
    fi
  fi
}

main "$@"
