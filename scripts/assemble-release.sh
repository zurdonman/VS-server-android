#!/usr/bin/env bash
# VS Server Android — assembles the runnable release layout in release/.
#
# code-server expects the VS Code build at lib/vscode/out; when building from
# source that output lives in lib/vscode-reh-web-<os>-<arch>/. This script
# packages everything into release/ the same way the upstream npm release does,
# so scripts/termux-start.sh (and any plain `node release/out/node/entry.js`)
# works out of the box.
set -euo pipefail

cd "$(dirname "$0")/.."

ARCH="$(uname -m)"
case "$ARCH" in
  aarch64) ARCH=arm64 ;;
  x86_64) ARCH=x64 ;;
esac
SRC="lib/vscode-reh-web-linux-$ARCH"

if [[ ! -d $SRC/out ]]; then
  echo "Missing $SRC. Build first:" >&2
  echo "  npm run build && VERSION=0.0.0 npm run build:vscode" >&2
  exit 1
fi

echo "==> Assembling release/ from $SRC"
rm -rf release
mkdir -p release/lib release/src/browser

cp -a out release/
cp -a src/browser/media src/browser/pages src/browser/robots.txt release/src/browser/ 2>/dev/null || true
cp -a "$SRC/." release/lib/vscode/
rm -f release/lib/vscode/node release/lib/vscode/node.exe

# Hardlink to save space; fall back to a real copy across filesystems.
cp -al node_modules release/node_modules 2>/dev/null || cp -a node_modules release/node_modules

COMMIT="$(git rev-parse HEAD 2>/dev/null || echo development)"
jq --slurp '(.[0] | del(.scripts,.jest,.devDependencies)) * .[1]' package.json \
  <(printf '{"version":"0.0.0","commit":"%s","scripts":{}}' "$COMMIT") > release/package.json

echo "==> release/ ready. Start with: bash scripts/termux-start.sh"
