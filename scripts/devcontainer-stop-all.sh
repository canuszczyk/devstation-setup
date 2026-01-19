#!/usr/bin/env bash
set -euo pipefail

# devcontainer-stop-all.sh
# Stop all running devcontainers (identified by com.devcontainer.repo label)

echo "Finding running devcontainers..."

mapfile -t cids < <(docker ps -q --filter "label=com.devcontainer.repo" 2>/dev/null || true)

if (( ${#cids[@]} == 0 )); then
  echo "No running devcontainers found."
  exit 0
fi

echo "Found ${#cids[@]} running devcontainer(s):"
for cid in "${cids[@]}"; do
  name=$(docker inspect -f '{{index .Config.Labels "com.devcontainer.repo"}}' "$cid" 2>/dev/null || echo "unknown")
  ws=$(docker inspect -f '{{range .Mounts}}{{if eq .Type "bind"}}{{.Destination}}{{end}}{{end}}' "$cid" 2>/dev/null | grep -o '/workspaces/[^/]*' | head -1 || echo "unknown")
  echo "  $cid - ${ws##*/} ($name)"
done

echo
read -p "Stop all? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "Stopping containers..."
  docker stop "${cids[@]}"
  echo "Done."
else
  echo "Aborted."
fi
