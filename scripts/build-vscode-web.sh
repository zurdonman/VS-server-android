#!/usr/bin/env bash
# Build VS Code for the web/remote server only (Android/Termux friendly).
#
# Mirrors ci/build/build-vscode.sh but uses our `core-ci-web` gulp task, which
# bundles only the server-web target. The stock `core-ci` also builds the
# desktop and node server bundles, which can run out of memory on phones.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

export BUILD_SOURCEVERSION="${BUILD_SOURCEVERSION:-$(git -C "$ROOT" rev-parse HEAD)}"
export VSCODE_TARGET="${VSCODE_TARGET:-linux-x64}"
export VSCODE_QUALITY="${VSCODE_QUALITY:-stable}"
export VERSION="${VERSION:-0.0.0}"

# Identificador unico de esta compilacion. Se usa como "commit" del
# product.json: la ruta del cliente web (/stable-<commit>/) y por tanto la URL
# del bundle cambian en cada build, asi el navegador descarga el bundle nuevo
# en vez de usar el que tiene cacheado (el workbench se sirve con max-age de
# un ano, asi que sin esto el movil nunca veria las actualizaciones).
BUILD_ID="${BUILD_ID:-$(date -u +%Y%m%d%H%M%S)}"
echo "Build ID: $BUILD_ID"

cd lib/vscode

# Set the product.json branding (same overlay as ci/build/build-vscode.sh).
# Code embeds this into the client-side bundle at build time.
git checkout product.json
cp product.json product.original.json
jq --slurp '.[0] * .[1]' product.original.json <(cat << JSON

{
  "enableTelemetry": true,
  "quality": "stable",
  "codeServerVersion": "$VERSION",
  "nameShort": "code-server",
  "nameLong": "code-server",
  "applicationName": "code-server",
  "dataFolderName": ".code-server",
  "win32MutexName": "codeserver",
  "licenseUrl": "https://github.com/coder/code-server/blob/main/LICENSE",
  "win32DirName": "code-server",
  "win32NameVersion": "code-server",
  "win32AppUserModelId": "coder.code-server",
  "win32ShellNameShort": "c&ode-server",
  "darwinBundleIdentifier": "com.coder.code.server",
  "linuxIconName": "com.coder.code.server",
  "reportIssueUrl": "https://github.com/coder/code-server/issues/new",
  "documentationUrl": "https://go.microsoft.com/fwlink/?LinkID=533484#vscode",
  "keyboardShortcutsUrlMac": "https://go.microsoft.com/fwlink/?linkid=832143",
  "keyboardShortcutsUrlLinux": "https://go.microsoft.com/fwlink/?linkid=832144",
  "keyboardShortcutsUrlWin": "https://go.microsoft.com/fwlink/?linkid=832145",
  "introductoryVideosUrl": "https://go.microsoft.com/fwlink/?linkid=832146",
  "tipsAndTricksUrl": "https://go.microsoft.com/fwlink/?linkid=852118",
  "newsletterSignupUrl": "https://www.research.net/r/vsc-newsletter",
  "linkProtectionTrustedDomains": ["https://open-vsx.org"],
  "trustedExtensionAuthAccess": [
    "vscode.git", "vscode.github", "github.vscode-pull-request-github",
    "github.copilot", "github.copilot-chat"
  ],
  "aiConfig": { "ariaKey": "code-server" },
  "extensionPointExtensionKind": { "typescriptServerPlugins": ["workspace"] },
  "mobileUiKind": "desktop",
  "commit": "mobile-build-$BUILD_ID"
}
JSON
) > product.json
rm product.original.json

# CS_SKIP_MARKETPLACE_EXT=1: omite las extensiones que el build descarga de
# GitHub (js-debug y compania). Util en entornos sin acceso a esos assets:
# el producto funciona igual, solo sin debugger de JavaScript.
if [[ ${CS_SKIP_MARKETPLACE_EXT:-0} == 1 ]]; then
  jq '.builtInExtensions = [] | .webBuiltInExtensions = []' product.json > product.tmp.json
  mv product.tmp.json product.json
fi

# Un fallo del typecheck (tsgo) no debe bloquear la compilacion en el movil;
# se registra el error real pero el build continua.
export VSCODE_TSGO_NONFATAL=1

# esbuild esta escrito en Go: al minificar el bundle completo puede RSS de
# >2.5 GB y morir por OOM (matarlo el kernel) en equipos con poca memoria
# (moviles, CI). Limitando su recolector de basura baja el pico de memoria.
# En equipos con >= 6 GB dejamos los valores por defecto (build mas rapido).
AVAIL_MB="$(awk '/^MemAvailable:/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 8192)"
if [[ -z "${GOMEMLIMIT:-}" && "${AVAIL_MB}" -lt 6144 ]]; then
  export GOMEMLIMIT="${CS_GOMEMLIMIT:-$((AVAIL_MB * 45 / 100))MiB}"
  export GOGC="${CS_GOGC:-25}"
  echo "==> Memoria limitada: GOMEMLIMIT=$GOMEMLIMIT GOGC=$GOGC (RAM disponible: ${AVAIL_MB} MB)"
fi

# Empaquetado de extensiones: se limita el numero de procesos esbuild en
# paralelo (por defecto 3) para no agotar la memoria.
export VSCODE_BUILD_EXTENSIONS_CONCURRENCY="${VSCODE_BUILD_EXTENSIONS_CONCURRENCY:-3}"

# Llamamos a gulp directamente con un limite de heap sensato: el script npm de
# VS Code pide --max-old-space-size=32384 (32 GB) y en un movil el gestor de
# memoria de Android puede matar el proceso antes de tiempo.
GULP=(node --experimental-strip-types "--max-old-space-size=${CS_BUILD_MEMORY:-6144}" ./node_modules/gulp/bin/gulp.js)

echo "==> Bundling web client (core-ci-web)"
"${GULP[@]}" core-ci-web

echo "==> Packaging server (vscode-reh-web-$VSCODE_TARGET-min-ci)"
"${GULP[@]}" "vscode-reh-web-$VSCODE_TARGET-min-ci"

# Reset so development after building is not stuck with the release commit.
git checkout product.json

echo "VS Code web build ready: lib/vscode-reh-web-$VSCODE_TARGET"
