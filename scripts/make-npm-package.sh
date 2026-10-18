#!/usr/bin/env bash
# Crea el paquete instalable con npm a partir del release precompilado.
#
#   npm install -g https://github.com/zurdonman/VS-server-android/releases/latest/download/vs-server-android-npm.tar.gz
#
# Es el mismo modelo que el code-server oficial: el paquete trae el VS Code
# ya compilado y en el movil solo se compilan los modulos nativos pequenos
# (node-pty, spdlog, sqlite3, watcher) para Bionic/aarch64.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
RELEASE="$ROOT/release"
OUT="${1:-$ROOT/vs-server-android-npm.tar.gz}"
VERSION="${VS_SERVER_VERSION:-1.0.0}"

if [[ ! -f "$RELEASE/out/node/entry.js" ]]; then
  echo "Falta el release compilado (release/out/node/entry.js)." >&2
  echo "Ejecuta antes: bash scripts/assemble-release.sh" >&2
  exit 1
fi

TMP="$(mktemp -d)"
PKG="$TMP/package"
mkdir -p "$PKG/bin" "$PKG/scripts" "$PKG/misc"

echo "==> Copiando el release precompilado"
tar -C "$RELEASE" --exclude='node_modules' --exclude='lib/vscode/node_modules' \
    --exclude='lib/vscode/node' --exclude='lib/vscode/node.exe' \
    -cf - . | tar -C "$PKG/release" -xf - 2>/dev/null || {
  mkdir -p "$PKG/release"
  tar -C "$RELEASE" --exclude='node_modules' --exclude='lib/vscode/node_modules' \
      --exclude='lib/vscode/node' --exclude='lib/vscode/node.exe' \
      -cf - . | tar -C "$PKG/release" -xf -
}

[[ -f "$ROOT/misc/android-as-linux.js" ]] && cp "$ROOT/misc/android-as-linux.js" "$PKG/misc/"

cat > "$PKG/package.json" << EOF
{
  "name": "vs-server-android",
  "version": "$VERSION",
  "description": "VS Code Server (code-server) para Android/Termux con parches moviles: teclado virtual, barra tactil flotante, zoom y depuracion.",
  "homepage": "https://github.com/zurdonman/VS-server-android",
  "bugs": { "url": "https://github.com/zurdonman/VS-server-android/issues" },
  "repository": { "type": "git", "url": "https://github.com/zurdonman/VS-server-android.git" },
  "license": "MIT",
  "bin": {
    "vs-server": "bin/vs-server",
    "vs-server-debug": "bin/vs-server-debug",
    "vs-code": "bin/vs-server",
    "vs-code-debug": "bin/vs-server-debug",
    "vs-update": "bin/vs-update"
  },
  "scripts": {
    "postinstall": "sh ./scripts/postinstall.sh"
  },
  "engines": { "node": ">=24" }
}
EOF

cat > "$PKG/bin/vs-server" << 'EOF'
#!/usr/bin/env bash
# VS Code Server para Android/Termux — arranque normal (http://localhost:8080)
set -euo pipefail
PKG="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
if [[ ! -f "$PKG/release/out/node/entry.js" ]]; then
  echo "Instalacion incompleta. Reinstala:" >&2
  echo "  npm install -g https://github.com/zurdonman/VS-server-android/releases/latest/download/vs-server-android-npm.tar.gz --force" >&2
  exit 1
fi
# En Android el marketplace no soporta la plataforma "android": se hace pasar
# por linux (mismo truco que usa el code-server oficial en Termux).
if [[ "${CS_ANDROID_AS_LINUX:-1}" == "1" && -f "$PKG/misc/android-as-linux.js" ]]; then
  export NODE_OPTIONS="${NODE_OPTIONS:-} --require $PKG/misc/android-as-linux.js"
fi
export NODE_OPTIONS="${NODE_OPTIONS:-} --max-old-space-size=${CS_MAX_MEMORY:-4096}"
exec node "$PKG/release/out/node/entry.js" \
  --bind-addr "0.0.0.0:${CS_PORT:-8080}" \
  --auth "${CS_AUTH:-password}" "$@"
EOF

cat > "$PKG/bin/vs-server-debug" << 'EOF'
#!/usr/bin/env bash
# VS Code Server para Android/Termux — modo depuracion (logs en Descargas/log/)
set -euo pipefail
PKG="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
DL="$HOME/storage/downloads"
if [[ ! -d $DL ]] && command -v termux-setup-storage >/dev/null 2>&1; then
  echo "Pidiendo permiso de almacenamiento (acepta el permiso de Android)..."
  termux-setup-storage >/dev/null 2>&1 || true
  sleep 2
fi
if [[ -d $DL ]]; then LOG_DIR="$DL/log"; else LOG_DIR="$PKG/log"; fi
mkdir -p "$LOG_DIR"
export CS_DEBUG_LOG_DIR="$LOG_DIR"
SESSION="$(date +%Y%m%d-%H%M%S)"
{
  echo ""
  echo "===== session $SESSION pid $$ node $(node -v) ====="
} >> "$LOG_DIR/server.log"
copy_workbench_logs() {
  local src="$HOME/.local/share/code-server/logs"
  if [[ -d $src ]]; then cp -a "$src" "$LOG_DIR/vscode-logs-$SESSION" 2>/dev/null || true; fi
}
trap copy_workbench_logs EXIT
echo "=============================================================="
echo " DEBUG MODE — logs en: $LOG_DIR"
echo "   server.log  (servidor: errores y trazas)"
echo "   vscode-logs-$SESSION/ (logs internos de VS Code)"
echo "=============================================================="
if [[ "${CS_ANDROID_AS_LINUX:-1}" == "1" && -f "$PKG/misc/android-as-linux.js" ]]; then
  export NODE_OPTIONS="${NODE_OPTIONS:-} --require $PKG/misc/android-as-linux.js"
fi
export NODE_OPTIONS="${NODE_OPTIONS:-} --max-old-space-size=${CS_MAX_MEMORY:-4096}"
node "$PKG/release/out/node/entry.js" \
  --bind-addr "0.0.0.0:${CS_PORT:-8080}" \
  --auth "${CS_AUTH:-password}" --log trace "$@" 2>&1 | tee -a "$LOG_DIR/server.log"
EOF

cat > "$PKG/bin/vs-update" << 'EOF'
#!/usr/bin/env bash
# VS Code Server para Android/Termux — actualiza a la ultima version publicada
set -euo pipefail
PKG="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
URL="https://github.com/zurdonman/VS-server-android/releases/latest/download/vs-server-android-npm.tar.gz"
echo "==> Actualizando VS Code Server Android"
echo "    $URL"
npm install -g "$URL" --force
echo ""
echo "Listo. Arranca con:  vs-server"
EOF

cp "$ROOT/scripts/npm-postinstall.sh" "$PKG/scripts/postinstall.sh"
chmod +x "$PKG/bin/"* "$PKG/scripts/postinstall.sh"

echo "==> Empaquetando"
rm -f "$OUT"
tar -C "$TMP" -czf "$OUT" package
rm -rf "$TMP"
ls -lh "$OUT"
echo "=== NPM_PACKAGE_OK ==="
