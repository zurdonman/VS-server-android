#!/usr/bin/env bash
# VS Code Server Android — actualizar desde GitHub.
# Hace `git pull` y solo recompila lo que haya cambiado (si no cambió nada de
# código, es instantáneo). Instalado en el PATH como comando `vs-update`.
set -euo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.."

# Toda la salida se guarda en un log (mismo sistema que la instalacion).
DL="$HOME/storage/downloads"
if [[ -d $DL ]]; then
  LOG_DIR="$DL/log"
else
  LOG_DIR="$PWD/log"
fi
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/update.log"
: > "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

on_exit() {
  local code=$?
  if [[ $code -ne 0 ]]; then
    echo ""
    echo "=============================================================="
    echo " ACTUALIZACION FALLIDA (codigo $code)"
    echo " Copia SOLO este bloque final y mandamelo (es suficiente):"
    echo "--------------------------------------------------------------"
    tail -n 25 "$LOG_FILE"
    echo "--------------------------------------------------------------"
    echo " (el log completo esta en: $LOG_FILE)"
    echo "=============================================================="
  fi
}
trap on_exit EXIT

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
  if grep -qE '^(package\.json|package-lock\.json|npm-shrinkwrap\.json|scripts/termux-deps\.sh)$' <<<"$CHANGED"; then
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
    bash scripts/termux-deps.sh
  fi

  if [[ $NEED_CS == 1 ]]; then
    echo "==> Recompilando code-server (minutos)"
    npm run build
  fi

  if [[ $NEED_VSCODE == 1 ]]; then
    if [[ -f .prebuilt-install ]]; then
      echo "==> Instalacion precopilada: actualizando descargando el nuevo build"
      bash scripts/termux-fast-setup.sh
    else
      echo "==> Reconstruyendo VS Code (lento: 20-60 min)"
      if [[ -d lib/vscode/.git || -f lib/vscode/.git ]]; then
        git -C lib/vscode reset --hard >/dev/null 2>&1 || true
        git -C lib/vscode clean -fdq -e node_modules || true
      fi
      rm -f .patches-applied
      bash scripts/apply-patches.sh
      bash scripts/build-vscode-web.sh
    fi
  fi

  if [[ $NEED_CS == 1 || $NEED_VSCODE == 1 ]]; then
    echo "==> Reensamblando release/"
    bash scripts/assemble-release.sh
  fi
fi

# Si no hay compilacion (o quedo a medias), compilarla ahora: sin ella el
# servidor no puede arrancar.
if [[ ! -f release/out/node/entry.js ]]; then
  if [[ -f .prebuilt-install ]]; then
    echo "==> No hay build. Descargando el precopilado (rapido)"
    bash scripts/termux-fast-setup.sh
  else
    echo "==> No hay build (release/). Preparando dependencias y compilando... (paso largo: 20-60 min)"
    bash scripts/termux-deps.sh
    npm run build
    bash scripts/build-vscode-web.sh
    bash scripts/assemble-release.sh
  fi
fi

# Si no hay nada compilado en local, la via rapida es el paquete precompilado.
if [[ ! -f release/out/node/entry.js ]] && [[ ! -f .prebuilt-install ]]; then
  echo ""
  echo "No hay build local. Puedes instalar el precompilado (un comando):"
  echo "    bash scripts/termux-install-npm.sh"
fi

# El servidor lee el product.json al arrancar (de ahi sale la ruta del cliente
# web y el bundle que sirve). Si estaba en marcha hay que reiniciarlo para que
# use el build nuevo; si no, el navegador se queda con el bundle viejo (que
# cachea durante un ano) y no se ve ningun cambio.
if pgrep -f "release/out/node/entry.js" >/dev/null 2>&1; then
  echo ""
  echo "==> Deteniendo el servidor para que arranque con el build nuevo"
  pkill -f "release/out/node/entry.js" >/dev/null 2>&1 || true
  sleep 2
  echo "    Vuelve a lanzarlo con:  vs-server"
  echo "    y RECARGA la pagina del navegador (la URL lleva ahora el build nuevo)."
fi

# La URL del cliente incluye el id del build: si cambia, el navegador
# descarga el bundle nuevo (el workbench se sirve con una cache de un ano).
BUILD_COMMIT=""
if [[ -f release/lib/vscode/product.json ]]; then
  BUILD_COMMIT="$(sed -n 's/.*"commit"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' release/lib/vscode/product.json | head -n 1)"
fi
if [[ -n $BUILD_COMMIT ]]; then
  echo "    URL del cliente: http://localhost:8080/stable-$BUILD_COMMIT/"
  echo "    (abre esa URL: asi el navegador descarga el bundle nuevo)"
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
ln -sf "$ROOT/bin/vs-code" "$BIN_DIR/vs-code"
ln -sf "$ROOT/bin/vs-code-debug" "$BIN_DIR/vs-code-debug"
ln -sf "$ROOT/bin/colab-fix" "$BIN_DIR/colab-fix"

echo ""
echo "=============================================================="
echo " Listo. Comandos disponibles:"
echo "     vs-server        (arranca el servidor)"
echo "     vs-server-debug  (modo debug: logs en Descargas/log/)"
echo "     vs-update        (actualiza desde GitHub)"
echo "     (alias: vs-code y vs-code-debug hacen lo mismo)"
echo "=============================================================="
