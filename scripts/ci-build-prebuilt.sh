#!/usr/bin/env bash
# Construye el release PRECOMPILADO para Android/Termux en CI (GitHub Actions).
#
# Aqui se compila TODO lo pesado (el motor de VS Code). En el movil solo queda
# compilar los modulos nativos pequenos (node-pty, spdlog, sqlite3, watcher),
# exactamente igual que hace el code-server oficial al instalarse.
#
# Salida: vs-server-android-prebuilt.tar.gz (sin node_modules).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
export FOUNDRY_LOCAL_SKIP_INSTALL=1
export ELECTRON_SKIP_BINARY_DOWNLOAD=1
export PYTHON=python3

# Compilacion: solo la variante web (server-web), sin node de escritorio.
export VSCODE_TARGET="${VSCODE_TARGET:-linux-x64}"
export VSCODE_TSGO_NONFATAL=1
export VSCODE_SKIP_NODE_DOWNLOAD=1
export CS_SKIP_MARKETPLACE_EXT=1
export VSCODE_BUILD_EXTENSIONS_CONCURRENCY=3

# Log completo + anotacion de error en el job (util para depurar sin abrir
# los logs completos de Actions).
LOG_FILE="${LOG_FILE:-ci-build.log}"
: > "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1
on_error() {
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "::error title=Fallo en el build precompilado::$(tail -n 25 "$LOG_FILE" | sed 's/%/%25/g; s/\r//g' | tr '\n' '%0A')"
  fi
  exit $rc
}
trap on_error EXIT

echo "==> [1/7] Codigo fuente de VS Code"
bash scripts/fetch-vscode.sh

echo "==> [2/7] Parches moviles"
bash scripts/apply-patches.sh

echo "==> [3/7] Tipos de electron (evita una descarga que falla en algunos entornos)"
if [[ ! -f lib/vscode/.build/typings/electron.d.ts ]]; then
  mkdir -p lib/vscode/.build/typings
  TMPDIR_E="$(mktemp -d)"
  (cd "$TMPDIR_E" && npm pack electron@43.7.7 --silent >/dev/null && tar xzf electron-43.7.7.tgz && cp package/electron.d.ts "$ROOT/lib/vscode/.build/typings/electron.d.ts")
  rm -rf "$TMPDIR_E"
fi

echo "==> [4/7] Dependencias npm"
# code-server: con devDependencies (tsc) pero sin los scripts de instalacion
# (los nativos se compilan en el movil); luego se reconstruye lo que lo necesite.
SKIP_SUBMODULE_DEPS=1 npm install --no-audit --no-fund --ignore-scripts
npm rebuild --no-audit --no-fund || true

# lib/vscode: el postinstall oficial instala los ~50 directorios anidados.
(cd lib/vscode && npm install --ignore-scripts --no-audit --no-fund)
(cd lib/vscode && VSCODE_FORCE_INSTALL=1 npm_config_ignore_scripts=true node build/npm/postinstall.ts)
(cd lib/vscode/build && npm rebuild esbuild)
(cd lib/vscode/extensions && npm rebuild esbuild)

echo "==> [5/7] code-server (tsc -> out/)"
npm run build

echo "==> [6/7] VS Code compilado para web"
bash scripts/build-vscode-web.sh

echo "==> [7/7] Empaquetado del release"
bash scripts/assemble-release.sh

rm -f vs-server-android-prebuilt.tar.gz
tar --exclude='release/node_modules' \
    --exclude='release/lib/vscode/node_modules' \
    --exclude='release/lib/vscode/node' \
    --exclude='release/lib/vscode/node.exe' \
    --exclude='release/lib/vscode/.build' \
    -czf vs-server-android-prebuilt.tar.gz release
ls -lh vs-server-android-prebuilt.tar.gz
echo "=== CI_PREBUILT_OK ==="
