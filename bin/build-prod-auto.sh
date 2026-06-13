#!/usr/bin/env bash
#
# bin/build-prod-auto.sh
#
# Detecta a última versão local de mamedes/klivy-prod (vX.Y.Z.W), incrementa
# o último número, mostra preview e pede confirmação antes de buildar + push.
#
# Sem argumentos: incrementa o último número (.90 -> .91).
#
# Flags (env):
#   SKIP_PUSH=1   build only, no push
#   NO_CACHE=1    skip --cache-from (full rebuild)

set -euo pipefail

IMAGE="mamedes/klivy-prod"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# --- Detectar última versão local --------------------------------------------
LATEST=$(docker images "$IMAGE" --format '{{.Tag}}' \
  | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
  | sort -V -r \
  | head -n 1 \
  || true)

if [[ -z "$LATEST" ]]; then
  echo "❌ Nenhuma versão local de $IMAGE encontrada." >&2
  echo "   Use bin/build-prod.sh vX.Y.Z.W pra fazer o primeiro build." >&2
  exit 1
fi

# --- Parsear e incrementar ---------------------------------------------------
if [[ ! "$LATEST" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "❌ Versão local '$LATEST' não bate com vX.Y.Z.W" >&2
  exit 1
fi

MAJOR="${BASH_REMATCH[1]}"
MINOR="${BASH_REMATCH[2]}"
PATCH="${BASH_REMATCH[3]}"
BUILD="${BASH_REMATCH[4]}"
NEXT_BUILD=$((BUILD + 1))
NEXT_VERSION="v${MAJOR}.${MINOR}.${PATCH}.${NEXT_BUILD}"

# --- Preview -----------------------------------------------------------------
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  🔍 PREVIEW DO BUILD"
echo "════════════════════════════════════════════════════════════"
echo "  Imagem:          $IMAGE"
echo "  Última local:    $LATEST"
echo "  Próxima versão:  $NEXT_VERSION"
if [[ "${NO_CACHE:-0}" == "1" ]]; then
  echo "  Cache from:      (nenhum — NO_CACHE=1)"
else
  echo "  Cache from:      $LATEST"
fi
echo "  Push:            $([[ "${SKIP_PUSH:-0}" == "1" ]] && echo 'NÃO (SKIP_PUSH=1)' || echo 'SIM')"
echo ""
echo "  Comandos que serão executados:"
if [[ "${NO_CACHE:-0}" == "1" ]]; then
  echo "    docker build --platform linux/amd64 \\"
  echo "      -t $IMAGE:$NEXT_VERSION ."
else
  echo "    docker pull $IMAGE:$LATEST    # best-effort, pra cache"
  echo "    docker build --platform linux/amd64 \\"
  echo "      --cache-from $IMAGE:$LATEST \\"
  echo "      -t $IMAGE:$NEXT_VERSION ."
fi
if [[ "${SKIP_PUSH:-0}" != "1" ]]; then
  echo "    docker push $IMAGE:$NEXT_VERSION"
fi
echo "════════════════════════════════════════════════════════════"
echo ""

# --- Confirmar ---------------------------------------------------------------
read -r -p "Confirmar build de $NEXT_VERSION? [y/N] " ANSWER
case "$ANSWER" in
  [yY]|[yY][eE][sS]|[sS]|[sS][iI][mM])
    echo "✅ Confirmado — iniciando build..."
    echo ""
    ;;
  *)
    echo "❌ Cancelado — você não respondeu 'y'."
    exit 0
    ;;
esac

# --- Delegar pro build-prod.sh ------------------------------------------------
exec "$SCRIPT_DIR/build-prod.sh" "$NEXT_VERSION" "$LATEST"
