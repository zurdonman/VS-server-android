#!/usr/bin/env bash
# VS Code Server Android — actualizar desde GitHub.
# Hace `git pull` y solo recompila lo que haya cambiado (si no cambió nada de
# código, es instantáneo). Instalado en el PATH como comando `vs-update`.
set -euo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.."

echo "==> Buscando actualizaciones (git pull)..."
OLD=$(git rev-parse HEAD)
if ! git pull --ff-only; then
  echo "No se pudo actualizar automaticamente." >&2
  echo "Si no has hecho cambios locales, ejecuta:" >&2
  echo "    git reset --hard origin/$(git rev-parse --abbrev-ref HEAD)" >&2
  echo "y vuelve a lanzar vs-update." >&2
  exit 1
fi
NEW=$(git rev-parse HEAD)

if [[ $OLD == "$NEW" ]]; then
  echo "Ya estas al dia (commit ${NEW:0:7})."
else
  echo "Actualizado: ${OLD:0:7} -> ${NEW:0:7}"
  CHANGED=$(git diff --name-only "$OLD" "$NEW")

  NEED_NPM=0
  NEED_CS=0
  NEED_VSCODE=0
  if grep -qE '^(package\.json|package-lock\.json|npm-shrinkwrap\.json)$' <<<"$CHANGED"; then
    NEED_NPM=1
  fi
  if grep -qE '^(src/|tsconfig|package\.json)' <<<"$CHANGED"; then
    NEED_CS=1
  fi
  if grep -qE '^(patches/|lib/vscode)' <<<"$CHANGED"; then
    NEED_VSCODE=1
  fi

  if [[ $NEED_NPM == 0 && $NEED_CS == 0 && $NEED_VSCODE == 0 ]]; then
    echo "Solo cambian docs/scripts: no hace falta recompilar."
  fi

  if [[ $NEED_NPM == 1 ]]; then
    echo "==> Actualizando dependencias npm"
    export npm_config_runtime=node
    export npm_config_target="$(node -p 'process.version.slice(1)')"
    export npm_config_disturl="https://nodejs.org/dist"
    export npm_config_build_from_source=true
    export npm_config_nodedir="${PREFIX:-/data/data/com.termux/files/usr}"
    export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
    export FOUNDRY_LOCAL_SKIP_INSTALL=1
    export ELECTRON_SKIP_BINARY_DOWNLOAD=1
    npm install --no-audit --no-fund
  fi

  if [[ $NEED_CS == 1 ]]; then
    echo "==> Recompilando code-server (minutos)"
    npm run build
  fi

  if [[ $NEED_VSCODE == 1 ]]; then
    echo "==> Reconstruyendo VS Code (lento: 20-60 min)"
    if [[ -d lib/vscode/.git || -f lib/vscode/.git ]]; then
      git -C lib/vscode reset --hard >/dev/null 2>&1 || true
      git -C lib/vscode clean -fdq -e node_modules || true
    fi
    rm -f .patches-applied
    bash scripts/apply-patches.sh
    bash scripts/build-vscode-web.sh
  fi

  if [[ $NEED_CS == 1 || $NEED_VSCODE == 1 ]]; then
    echo "==> Reensamblando release/"
    bash scripts/assemble-release.sh
  fi
fi

# (Re)instalar los comandos cortos por si el proyecto se movio de carpeta.
ROOT="$PWD"
BIN_DIR="${PREFIX:-/data/data/com.termux/files/usr}/bin"
if [[ ! -d $BIN_DIR || ! -w $BIN_DIR ]]; then
  BIN_DIR="$HOME/.local/bin"
  mkdir -p "$BIN_DIR"
fi
ln -sf "$ROOT/bin/vs-server" "$BIN_DIR/vs-server"
ln -sf "$ROOT/bin/vs-server-debug" "$BIN_DIR/vs-server-debug"
ln -sf "$ROOT/bin/vs-update" "$BIN_DIR/vs-update"

echo ""
echo "=============================================================="
echo " Listo. Comandos disponibles:"
echo "     vs-server  |  vs-server-debug  |  vs-update"
echo "=============================================================="
