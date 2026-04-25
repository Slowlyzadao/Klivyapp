#!/usr/bin/env bash
#
# bin/cleanup-prod-images.sh
#
# Remove LOCAL mamedes/klivy-prod images, keeping only the N most recent
# versioned tags (vX.Y.Z.W). Does NOT touch 'latest' or any non-versioned tag.
# Does NOT touch Docker Hub — that must be done via hub.docker.com UI.
#
# Usage:
#   bin/cleanup-prod-images.sh           # keeps the last 3 versions (default)
#   bin/cleanup-prod-images.sh 5         # keeps the last 5 versions
#   DRY_RUN=1 bin/cleanup-prod-images.sh # preview, do not delete
#
# Safe: only removes images whose tag matches vX.Y.Z.W. The 'latest' tag and
# other images (chatwoot, postgres, etc.) are never touched by this script.

set -euo pipefail

IMAGE="mamedes/klivy-prod"
KEEP="${1:-3}"

if ! [[ "$KEEP" =~ ^[0-9]+$ ]] || [[ "$KEEP" -lt 1 ]]; then
  echo "Error: KEEP must be a positive integer. Got: '$KEEP'" >&2
  exit 1
fi

TAGS=$(docker images "$IMAGE" --format '{{.Tag}}' \
  | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
  | sort -V -r \
  || true)

if [[ -z "$TAGS" ]]; then
  echo "No versioned images of $IMAGE found locally."
  exit 0
fi

TOTAL=$(echo "$TAGS" | wc -l)
TO_KEEP=$(echo "$TAGS" | head -n "$KEEP")
TO_REMOVE=$(echo "$TAGS" | tail -n +$((KEEP + 1)))

echo "======================================================================"
echo "Local images of $IMAGE: $TOTAL versioned tag(s)"
echo "======================================================================"
echo ""
echo "Keeping the $KEEP most recent:"
echo "$TO_KEEP" | sed 's/^/  ✓ /'

if [[ -z "$TO_REMOVE" ]]; then
  echo ""
  echo "Nothing to remove. Done."
  exit 0
fi

COUNT_REMOVE=$(echo "$TO_REMOVE" | wc -l)
echo ""
echo "Will remove $COUNT_REMOVE older version(s):"
echo "$TO_REMOVE" | sed 's/^/  ✗ /'

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo ""
  echo "DRY_RUN=1 — not removing. Run without DRY_RUN to actually delete."
  exit 0
fi

echo ""
echo "----------------------------------------------------------------------"
echo "Removing..."
echo "----------------------------------------------------------------------"

while IFS= read -r tag; do
  [[ -z "$tag" ]] && continue
  echo "> docker rmi $IMAGE:$tag"
  docker rmi "$IMAGE:$tag" 2>&1 || echo "  (failed — may be referenced by a running container, skipping)"
done <<< "$TO_REMOVE"

echo ""
echo "----------------------------------------------------------------------"
echo "Cleanup finished."
echo ""
echo "Tip: run 'docker image prune' to also remove dangling (untagged) layers."
echo "     Run 'docker system df' to see total disk usage."
echo "----------------------------------------------------------------------"
