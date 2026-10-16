#!/usr/bin/env bash
# VS Server Android — installer for Termux.
#
# Builds this fork of code-server (with the mobile input patches) from source
# inside Termux on your phone. Run it from the repository root:
#
#   bash scripts/termux-setup.sh
#
# Requirements: Termux from F-Droid, ~6 GB free storage, a few GB of RAM and a
# lot of patience (compiling VS Code on a phone takes a while).
set -euo pipefail

cd "$(dirname "$0")/.."

# Toda la salida se guarda en un log para poder diagnosticar sin copiar todo.
DL="$HOME/storage/downloads"
if [[ -d $DL ]]; then
  LOG_DIR="$DL/log"
else
  LOG_DIR="$PWD/log"
fi
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/setup.log"
: > "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "==> La salida completa se guarda en: $LOG_FILE"

on_exit() {
  local code=$?
  if [[ $code -ne 0 ]]; then
    echo ""
    echo "=============================================================="
    echo " INSTALACION FALLIDA (codigo $code)"
    echo " Copia SOLO este bloque final y mandamelo (es suficiente):"
    echo "--------------------------------------------------------------"
    tail -n 25 "$LOG_FILE"
    echo "--------------------------------------------------------------"
    echo " (el log completo esta en: $LOG_FILE)"
    echo "=============================================================="
  else
    echo ""
    echo "==> INSTALACION OK (log guardado en: $LOG_FILE)"
  fi
}
trap on_exit EXIT

echo "==> [1/6] Installing Termux packages"
pkg update -y
# x11-repo: libx11/libxkbfile son necesarias para compilar native-keymap
pkg install -y x11-repo || true
pkg update -y || true
pkg install -y \
  git \
  nodejs-lts \
  python \
  make \
  clang \
  pkg-config \
  binutils \
  patch \
  jq \
  libsecret \
  ripgrep \
  krb5 \
  libx11 \
  libxkbfile \
  || pkg install -y git nodejs python make clang pkg-config binutils patch jq ripgrep krb5 libx11 libxkbfile \
  || pkg install -y git nodejs python make clang pkg-config binutils patch jq ripgrep

echo "    Node: $(node -v)"
python3 -m pip install --quiet --upgrade pip >/dev/null 2>&1 || true
# npm 11+ (Node 24) rechaza `npm config set python`; node-gyp usa la variable
# de entorno PYTHON, que vale para todas las versiones.
export PYTHON=python3

echo "==> [2/6] Fetching the VS Code source tree"
bash scripts/fetch-vscode.sh

echo "==> [3/6] Applying the patch stack (upstream + mobile fixes)"
bash scripts/apply-patches.sh

echo "==> [4/6] Installing npm dependencies"
bash scripts/termux-deps.sh

echo "==> [5/6] Fixing ripgrep for Android (prebuilt binary is glibc-only)"
for RG in \
  "lib/vscode/node_modules/@vscode/ripgrep/bin/rg" \
  "lib/vscode/node_modules/@vscode/ripgrep-universal/bin/linux-x64/rg" \
  "lib/vscode/node_modules/@vscode/ripgrep-universal/bin/linux-arm64/rg" \
  "lib/vscode/remote/node_modules/@vscode/ripgrep/bin/rg" \
  "lib/vscode/remote/node_modules/@vscode/ripgrep-universal/bin/linux-x64/rg" \
  "lib/vscode/remote/node_modules/@vscode/ripgrep-universal/bin/linux-arm64/rg"
do
  if [[ -e $RG || -L $RG ]] && ! "$RG" --version >/dev/null 2>&1; then
    echo "    Replacing the bundled ripgrep with Termux's ripgrep ($RG)"
    rm -f "$RG"
    cat > "$RG" << 'WRAP'
#!/data/data/com.termux/files/usr/bin/sh
exec /data/data/com.termux/files/usr/bin/rg "$@"
WRAP
    chmod +x "$RG"
  fi
done

rm -f .prebuilt-install   # esto es una compilacion completa, no precopilada
echo "==> [6/6] Building code-server + VS Code web (this is the slow part)"
npm run build
VERSION="${VERSION:-0.0.0}" bash scripts/build-vscode-web.sh

echo "==> Assembling the runnable release"
bash scripts/assemble-release.sh

echo "==> Installing quick commands: vs-server / vs-server-debug"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="${PREFIX:-/data/data/com.termux/files/usr}/bin"
if [[ ! -d $BIN_DIR || ! -w $BIN_DIR ]]; then
  BIN_DIR="$HOME/.local/bin"
  mkdir -p "$BIN_DIR"
  echo "    ($BIN_DIR no esta en el PATH habitual; se instalara alli igualmente)"
fi
ln -sf "$ROOT/bin/vs-server" "$BIN_DIR/vs-server"
ln -sf "$ROOT/bin/vs-server-debug" "$BIN_DIR/vs-server-debug"
ln -sf "$ROOT/bin/vs-update" "$BIN_DIR/vs-update"
ln -sf "$ROOT/bin/vs-code" "$BIN_DIR/vs-code"
ln -sf "$ROOT/bin/vs-code-debug" "$BIN_DIR/vs-code-debug"
echo "    Comandos instalados en: $BIN_DIR"

echo ""
echo "=============================================================="
echo " ¡Listo! Abre VS Code Server con un solo comando:"
echo ""
echo "     vs-server            (arranca el servidor)"
echo "     vs-server-debug      (modo debug: logs en Descargas/log/)"
echo "     vs-update            (actualiza el proyecto desde GitHub)"
echo ""
echo " y abre http://localhost:8080 en el navegador."
echo " (Si los comandos no se encuentran, cierra y vuelve a abrir Termux)"
echo "=============================================================="
