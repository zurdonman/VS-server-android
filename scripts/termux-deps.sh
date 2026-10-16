#!/usr/bin/env bash
# VS Code Server Android — instalar dependencias npm en Termux.
#
# Arreglos para Android:
#  - Bionic no implementa pthread_cancel (usa pthread_detach, misma firma).
#    native-keymap lo llama en su ruta X11 de escritorio; el servidor web no lo
#    usa, pero npm exige que compile.
#  - Se compilan primero los módulos imprescindibles para el servidor (terminal,
#    logs, base de datos, ficheros de búsqueda) y el resto no bloquea.
#
# Lo usan termux-setup.sh y termux-update.sh.
set -euo pipefail

cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.."

export PYTHON=python3
export npm_config_runtime=node
export npm_config_target="$(node -p 'process.version.slice(1)')"
export npm_config_disturl="https://nodejs.org/dist"
export npm_config_build_from_source=true
export npm_config_nodedir="${PREFIX:-/data/data/com.termux/files/usr}"
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
export FOUNDRY_LOCAL_SKIP_INSTALL=1
export ELECTRON_SKIP_BINARY_DOWNLOAD=1
# Por si otro módulo usa pthread_cancel (no existe en Android):
export CFLAGS="${CFLAGS:-} -Dpthread_cancel=pthread_detach"
export CXXFLAGS="${CXXFLAGS:-} -Dpthread_cancel=pthread_detach"

# Compila los nativos de un directorio node_modules: los esenciales a huevo y el
# resto como mejor se pueda (son opcionales en el servidor web).
staged_natives() {
  local dir=$1
  shift
  [[ -d $dir/node_modules ]] || return 0
  pushd "$dir" >/dev/null
  # Arreglo Android: pthread_cancel -> pthread_detach (misma firma POSIX).
  find node_modules/native-keymap/src \( -name '*.cc' -o -name '*.h' \) \
    -exec sed -i 's/\bpthread_cancel\b/pthread_detach/g' {} + 2>/dev/null || true
  local m
  for m in "$@"; do
    if [[ -d node_modules/$m ]]; then
      echo "    compilando $m ($dir)"
      npm rebuild "$m"
    fi
  done
  npm rebuild >/dev/null 2>&1 || true
  popd >/dev/null
}

echo "==> Dependencias de code-server (raiz)"
# SKIP_SUBMODULE_DEPS: lib/vscode se instala mas abajo con control propio.
SKIP_SUBMODULE_DEPS=1 npm install --no-audit --no-fund

echo "==> Dependencias de lib/vscode (extraccion sin scripts + compilacion)"
pushd lib/vscode >/dev/null
npm install --ignore-scripts --no-audit --no-fund
popd >/dev/null

staged_natives lib/vscode \
  esbuild node-pty @vscode/spdlog @vscode/sqlite3 @parcel/watcher @vscode/ripgrep-universal

echo "==> Dependencias anidadas de VS Code (build/, remote/, extensions/...)"
pushd lib/vscode >/dev/null
# VSCODE_FORCE_INSTALL: sin esto, postinstall puede saltarse todo creyendo que
# ya esta instalado (y faltan paquetes como esbuild en extensions/).
VSCODE_FORCE_INSTALL=1 npm_config_ignore_scripts=true node build/npm/postinstall.ts
popd >/dev/null

# esbuild (binario Go estatico) necesario para empaquetar.
if [[ -d lib/vscode/build/node_modules/esbuild ]]; then
  echo "    compilando esbuild (lib/vscode/build)"
  (cd lib/vscode/build && npm rebuild esbuild)
fi
if [[ -d lib/vscode/extensions/node_modules ]]; then
  echo "    compilando esbuild (lib/vscode/extensions)"
  (cd lib/vscode/extensions && npm rebuild esbuild)
fi

# remote/: de aqui sale el node_modules del release; sus nativos importan.
staged_natives lib/vscode/remote \
  node-pty @vscode/spdlog @vscode/sqlite3 @parcel/watcher

echo "==> Dependencias npm listas"
