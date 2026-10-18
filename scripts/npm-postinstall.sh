#!/usr/bin/env bash
# postinstall del paquete npm "vs-server-android".
#
# El VS Code ya viene compilado dentro del paquete; aqui solo se compilan los
# modulos nativos PEQUEÑOS para Android (Bionic/aarch64): node-pty, spdlog,
# sqlite3 y @parcel/watcher. Es exactamente lo que hace el code-server oficial
# al instalarse en Termux, pero con un binario de node ya compilado.
#
# Toda la salida va a Descargas/log/setup.log y, si algo falla, se imprime
# solo un bloque corto que se puede copiar y pegar.
set -uo pipefail

PKG="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
RELEASE="$PKG/release"

DL="$HOME/storage/downloads"
if [[ ! -d $DL ]] && command -v termux-setup-storage >/dev/null 2>&1; then
  termux-setup-storage >/dev/null 2>&1 || true
  sleep 2
fi
if [[ -d $DL ]]; then
  LOG_DIR="$DL/log"
else
  LOG_DIR="$PKG/log"
fi
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/setup.log"

echo "==> Compilando las piezas nativas para Android (~10 min)"
echo "    Log: $LOG_FILE"
{
  echo ""
  echo "===== vs-server-android postinstall $(date) ====="
} >> "$LOG_FILE"

exec > >(tee -a "$LOG_FILE") 2>&1

export PYTHON=python3
export npm_config_runtime=node
export npm_config_target="$(node -p 'process.version.slice(1)' 2>/dev/null || echo 24.0.0)"
export npm_config_disturl="https://nodejs.org/dist"
export npm_config_build_from_source=true
export npm_config_nodedir="${PREFIX:-/data/data/com.termux/files/usr}"
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
export FOUNDRY_LOCAL_SKIP_INSTALL=1
export ELECTRON_SKIP_BINARY_DOWNLOAD=1

FAILED=0

run_install() {
  local dir="$1"
  echo ""
  echo "--- npm install --omit=dev en $dir"
  ( cd "$dir" && npm install --omit=dev --no-audit --no-fund ) || return 1
  return 0
}

# 1) Dependencias del servidor + postinstall oficial (que instala lib/vscode y
#    las extensiones, compilando los nativos).
if run_install "$RELEASE"; then
  echo "Dependencias del servidor instaladas."
else
  echo "AVISO: fallo el install del servidor; se intenta el de lib/vscode."
  FAILED=1
fi

# 2) Por si el postinstall oficial no llego (o fallo a medias).
if [[ ! -d "$RELEASE/lib/vscode/node_modules/@vscode" ]] && [[ ! -d "$RELEASE/lib/vscode/node_modules/node-pty" ]]; then
  run_install "$RELEASE/lib/vscode" || FAILED=1
fi

# 3) El ripgrep precompilado es glibc: en Android usamos el rg de Termux.
if command -v rg >/dev/null 2>&1; then
  for RG in \
    "$RELEASE/lib/vscode/node_modules/@vscode/ripgrep/bin/rg" \
    "$RELEASE/lib/vscode/node_modules/@vscode/ripgrep-universal/bin/linux-x64/rg" \
    "$RELEASE/lib/vscode/node_modules/@vscode/ripgrep-universal/bin/linux-arm64/rg"
  do
    if [[ -f "$RG" ]]; then
      printf '#!/usr/bin/env bash\nexec rg "$@"\n' > "$RG"
      chmod +x "$RG"
    fi
  done
  echo "ripgrep: se usa el rg de Termux."
fi

if [[ $FAILED -eq 0 ]]; then
  touch "$RELEASE/.native-install-ok"
  echo ""
  echo "=============================================================="
  echo " INSTALACION CORRECTA"
  echo "   Arranca el servidor con:  vs-server"
  echo "   (http://localhost:8080 — usuario: con la clave de code-server)"
  echo "   Modo depuracion:         vs-server-debug"
  echo "   Log de esta instalacion:  $LOG_FILE"
  echo "=============================================================="
else
  echo ""
  echo "=============================================================="
  echo " INSTALACION FALLIDA (las piezas nativas)"
  echo " Copia este bloque y mandamelo:"
  echo "--------------------------------------------------------------"
  tail -n 25 "$LOG_FILE"
  echo "--------------------------------------------------------------"
  echo " Log completo: $LOG_FILE"
  echo " Reintentar:   npm install -g https://github.com/zurdonman/VS-server-android/releases/latest/download/vs-server-android-npm.tar.gz --force"
  echo "=============================================================="
fi

# Salimos con 0 para que npm no desinstale el paquete si algo falla: asi el
# usuario puede reintentar sin volver a descargarlo todo.
exit 0
