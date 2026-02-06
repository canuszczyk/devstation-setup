#!/usr/bin/env bash
set -euo pipefail

# devcontainer-stop.sh
# Stop a single devcontainer by repo path
# Usage: devcontainer-stop.sh ~/code/REPO

if [ $# -eq 0 ] || [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
  echo "Usage: devcontainer-stop.sh <repo_path>"
  echo "  Stop the devcontainer for the given repository."
  echo
  echo "Examples:"
  echo "  devcontainer-stop.sh ~/code/my-repo"
  echo "  devcontainer-stop.sh ."
  exit 0
fi

input_path="${1:-.}"
repo_path="$input_path"

# Resolve to absolute path and find git root
repo_path="$(cd "$repo_path" 2>/dev/null && pwd)" || { echo "Invalid path: $input_path"; exit 1; }
if git -C "$repo_path" rev-parse --show-toplevel >/dev/null 2>&1; then
  repo_path="$(git -C "$repo_path" rev-parse --show-toplevel)"
fi

# Calculate label (same logic as devcontainer-rebuild.sh / dexec)
remote=""
if git -C "$repo_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  remote="$(git -C "$repo_path" config --get remote.origin.url || true)"
fi

basis=""
if [ -n "$remote" ]; then
  basis="$remote"
  basis="${basis#ssh://}"
  basis="${basis#https://}"
  basis="${basis#http://}"
  basis="${basis%.git}"
  basis="${basis%/}"
else
  basis="$(basename "$repo_path")"
fi

hash="$(printf '%s' "$basis" | sha256sum | cut -c1-16)"
label="com.devcontainer.repo=repo-${hash}"

ws_name="$(basename "$repo_path")"

# Find container (running or stopped)
cid="$(docker ps -aq --filter "label=$label" | head -n1)"
if [ -z "$cid" ]; then
  echo "No container found for: $ws_name"
  echo "Label: $label"
  exit 1
fi

# Check if already stopped
running="$(docker inspect -f '{{.State.Running}}' "$cid" 2>/dev/null || echo "false")"
if [ "$running" != "true" ]; then
  echo "Container for $ws_name is already stopped."
  exit 0
fi

echo "Stopping container for $ws_name ($cid)..."
docker stop "$cid" >/dev/null
echo "Stopped."
