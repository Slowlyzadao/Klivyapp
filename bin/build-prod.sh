#!/usr/bin/env bash
#
# bin/build-prod.sh
#
# Build and push the production Docker image `mamedes/klivy-prod`.
# Captures full stdout/stderr to `build_production.log` (overwritten each run)
# so the log always reflects the most recent build.
#
# Usage:
#   bin/build-prod.sh <new_version> [previous_version]
#
# Examples:
#   bin/build-prod.sh v1.4.4.53                 # auto-detects previous from local images
#   bin/build-prod.sh v1.4.4.53 v1.4.4.52       # explicit previous for --cache-from
#
# Flags (env):
#   SKIP_PUSH=1   build only, do not push to Docker Hub (useful for dry-run)
#   NO_CACHE=1    skip --cache-from (forces full rebuild)

set -euo pipefail

IMAGE="mamedes/klivy-prod"
LOG_FILE="build_production.log"

# Move to project root regardless of where the script was invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <new_version> [previous_version]" >&2
  echo "Example: $0 v1.4.4.53 v1.4.4.52" >&2
  exit 1
fi

NEW_VERSION="$1"
PREV_VERSION="${2:-}"

if [[ ! "$NEW_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: NEW_VERSION must match vX.Y.Z.W (e.g. v1.4.4.53). Got: '$NEW_VERSION'" >&2
  exit 1
fi

# Redirect all output (stdout + stderr) to the log file AND the terminal.
# Every line below this point is captured, including docker's progress output.
exec > >(tee "$LOG_FILE") 2>&1

if [[ -z "$PREV_VERSION" && "${NO_CACHE:-0}" != "1" ]]; then
  PREV_VERSION=$(docker images "$IMAGE" --format '{{.Tag}}' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
    | grep -v "^${NEW_VERSION}$" \
    | sort -V -r \
    | head -n 1 \
    || true)
  if [[ -n "$PREV_VERSION" ]]; then
    echo "Auto-detected previous version for cache: $PREV_VERSION"
  else
    echo "Warning: no previous version found locally — building without --cache-from"
  fi
fi

echo "======================================================================"
echo "Build started:   $(date -Iseconds)"
echo "Project root:    $PROJECT_ROOT"
echo "Image:           $IMAGE"
echo "New version:     $NEW_VERSION"
echo "Previous (cache): ${PREV_VERSION:-<none>}"
echo "SKIP_PUSH:       ${SKIP_PUSH:-0}"
echo "NO_CACHE:        ${NO_CACHE:-0}"
echo "======================================================================"

if [[ -n "$PREV_VERSION" && "${NO_CACHE:-0}" != "1" ]]; then
  echo "> Pulling previous image for cache (best effort)..."
  docker pull "$IMAGE:$PREV_VERSION" || echo "(previous image unavailable — continuing without cache)"
fi

BUILD_ARGS=(--platform linux/amd64 -t "$IMAGE:$NEW_VERSION")
if [[ -n "$PREV_VERSION" && "${NO_CACHE:-0}" != "1" ]]; then
  BUILD_ARGS+=(--cache-from "$IMAGE:$PREV_VERSION")
fi

echo "> docker build ${BUILD_ARGS[*]} ."
docker build "${BUILD_ARGS[@]}" .

if [[ "${SKIP_PUSH:-0}" == "1" ]]; then
  echo "> SKIP_PUSH=1 — not pushing to Docker Hub."
else
  echo "> docker push $IMAGE:$NEW_VERSION"
  docker push "$IMAGE:$NEW_VERSION"
fi

echo "======================================================================"
echo "Build finished: $(date -Iseconds)"
echo "Tag published:  $IMAGE:$NEW_VERSION"
echo "Log file:       $LOG_FILE"
echo "======================================================================"
