#!/usr/bin/env bash
# =============================================================================
# build-base-image.sh — Build the devstation-base:latest Docker image
# =============================================================================
# Usage:
#   ~/build-base-image.sh              # normal build (uses cache)
#   ~/build-base-image.sh --no-cache   # fresh build (no Docker layer cache)
# =============================================================================
set -euo pipefail

REAL_SCRIPT="$(readlink -f "$0")"
SCRIPT_DIR="$(cd "$(dirname "$REAL_SCRIPT")" && pwd)"
DOCKERFILE_DIR="${SCRIPT_DIR}/../templates/base"
IMAGE_NAME="devstation-base:latest"

# Parse flags
DOCKER_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --no-cache) DOCKER_ARGS+=("--no-cache") ;;
    *) echo "Unknown argument: $arg"; exit 1 ;;
  esac
done

echo "============================================"
echo "  Building ${IMAGE_NAME}"
echo "  Dockerfile: ${DOCKERFILE_DIR}/Dockerfile"
if [[ ${#DOCKER_ARGS[@]} -gt 0 ]]; then
  echo "  Flags: ${DOCKER_ARGS[*]}"
fi
echo "============================================"
echo ""

BUILD_START=$SECONDS

docker build \
  ${DOCKER_ARGS[@]+"${DOCKER_ARGS[@]}"} \
  -t "${IMAGE_NAME}" \
  -f "${DOCKERFILE_DIR}/Dockerfile" \
  "${DOCKERFILE_DIR}"

BUILD_DURATION=$((SECONDS - BUILD_START))

echo ""
echo "============================================"
echo "  Build complete in ${BUILD_DURATION}s"
echo "  Image: ${IMAGE_NAME}"
echo "  Size:  $(docker image inspect "${IMAGE_NAME}" --format='{{.Size}}' | awk '{printf "%.0f MB\n", $1/1024/1024}')"
echo "============================================"
