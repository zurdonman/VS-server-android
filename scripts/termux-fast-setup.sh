#!/usr/bin/env bash
# VS Server Android — instalacion RAPIDA.
#
# Descarga el build precopilado de VS Code (GitHub Releases) y solo compila en
# el movil las piezas nativas (~10 min), igual que hace el code-server oficial.
# Si prefieres compilarlo todo tu mismo: bash scripts/termux-setup.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

REPO_URL="https://github.com/zurdonman/VS-server-android"
ASSET_URL="$REPO_URL/releases/latest/download/vs-server-android-prebuilt.tar.gz"

echo "==> [1/5] Paquetes de Termux"
pkg update -y
pkg install -y x11-repo || true
pkg update -y || true
pkg install -y \
  git nodejs-lts python make clang pkg-config binutils patch jq \
  libsecret ripgrep krb5 libx11 libxkbfile \
  || pkg install -y git nodejs python make clang pkg-config binutils patch jq ripgrep krb5

echo "==> [2/5] Descargando el build precopilado"
echo "    $ASSET_URL"
if ! curl -fL --retry 2 -o /tmp/vs-server-prebuilt.tar.gz "$ASSET_URL"; then
  echo ""
  echo "No se pudo descargar el precopilado (¿aun no hay publicado?)."
  echo "Compilalo en el movil con:  bash scripts/termux-setup.sh"
  exit 1
fi

echo "==> [3/5] Descomprimiendo"
rm -rf release
tar -xzf /tmp/vs-server-prebuilt.tar.gz
rm -f /tmp/vs-server-prebuilt.tar.gz

echo "==> [4/5] Compilando las piezas nativas en el movil (~10 min)"
export PYTHON=python3
export npm_config_runtime=node
export npm_config_target="$(node -p 'process.version.slice(1)')"
export npm_config_disturl="https://nodejs.org/dist"
export npm_config_build_from_source=true
export npm_config_nodedir="${PREFIX:-/data/data/com.termux/files/usr}"
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
export FOUNDRY_LOCAL_SKIP_INSTALL=1
export ELECTRON_SKIP_BINARY_DOWNLOAD=1

# Dependencias del servidor (argon2, etc.). Su postinstall oficial instala
# tambien las de lib/vscode (node-pty, spdlog, sqlite3...): es exactamente lo
# que hace el code-server oficial al instalarse en Termux.
(cd release && npm install --omit=dev --no-audit --no-fund)
# Por si el postinstall no llego:
(cd release/lib/vscode && npm install --omit=dev --no-audit --no-fund)

# El ripgrep precompilado es glibc: se envuelve con el rg de Termux.
for RG in \
  "release/lib/vscode/node_modules/@vscode/ripgrep/bin/rg" \
  "release/lib/vscode/node_modules/@vscode/ripgrep-universal/bin/linux-x64/rg" \
  "release/lib/vscode/node_modules/@vscode/ripgrep-universal/bin/linux-arm64/rg"
do
  if [[ -e $RG || -L $RG ]] && ! "$RG" --version >/dev/null 2>&1; then
    echo "    Envolviendo ripgrep con Termux: $RG"
    rm -f "$RG"
    cat > "$RG" << 'WRAP'
#!/data/data/com.termux/files/usr/bin/sh
exec /data/data/com.termux/files/usr/bin/rg "$@"
WRAP
    chmod +x "$RG"
  fi
done

echo "==> [5/5] Instalando comandos"
BIN_DIR="${PREFIX:-/data/data/com.termux/files/usr}/bin"
if [[ ! -d $BIN_DIR || ! -w $BIN_DIR ]]; then
  BIN_DIR="$HOME/.local/bin"
  mkdir -p "$BIN_DIR"
fi
for c in vs-server vs-server-debug vs-update vs-code vs-code-debug; do
  ln -sf "$ROOT/bin/$c" "$BIN_DIR/$c"
done
touch "$ROOT/.prebuilt-install"

echo ""
echo "=============================================================="
echo " INSTALACION RAPIDA OK"
echo ""
echo "     vs-server            (arranca el servidor)"
echo "     vs-server-debug      (modo debug: logs en Descargas/log/)"
echo ""
echo " y abre http://localhost:8080 en el navegador."
echo "=============================================================="
