#!/usr/bin/env bash
# Assemble a runnable release/ directory from the built pieces, mirroring
# ci/build/build-release.sh (without rsync) so release/ matches the layout
# code-server expects at runtime:
#   release/out                -> code-server server (tsc output)
#   release/src/browser/...    -> code-server web assets (login, icons, robots)
#   release/lib/vscode         -> VS Code reh-web build (out/, extensions/, ...)
#   release/package.json       -> trimmed code-server package.json
# On top of the NPM release we keep node_modules so the directory can be run
# straight from a Termux clone.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
RELEASE="$ROOT/release"
VSCODE_TARGET="${VSCODE_TARGET:-linux-x64}"
REH="$ROOT/lib/vscode-reh-web-$VSCODE_TARGET"

if [ ! -f "$REH/out/server-main.js" ]; then
  echo "VS Code build is missing ($REH/out/server-main.js)." >&2
  echo "Build it first: npm run gulp core-ci && npm run gulp vscode-reh-web-$VSCODE_TARGET-min-ci" >&2
  exit 1
fi
if [ ! -f "$ROOT/out/node/entry.js" ]; then
  echo "code-server is not built (out/node/entry.js). Run: npm run build" >&2
  exit 1
fi

echo "Assembling $RELEASE"
rm -rf "$RELEASE"
mkdir -p "$RELEASE/lib"

# code-server out/ (tsc).
cp -a "$ROOT/out" "$RELEASE/out"

# code-server web assets (login/error pages, icons, robots.txt).
mkdir -p "$RELEASE/src/browser/pages"
cp -a "$ROOT/src/browser/media" "$RELEASE/src/browser/media"
cp -a "$ROOT/src/browser/pages/." "$RELEASE/src/browser/pages/"
cp -a "$ROOT/src/browser/robots.txt" "$RELEASE/src/browser/robots.txt"

# VS Code: hardlink-copy the reh-web build (fallback to a real copy), then drop
# the bundled Node binary (the launcher runs under the system/Termux node).
if ! cp -al "$REH/." "$RELEASE/lib/vscode" 2>/dev/null; then
  cp -a "$REH/." "$RELEASE/lib/vscode"
fi
rm -f "$RELEASE/lib/vscode/node" "$RELEASE/lib/vscode/node.exe"

# Merge the remote package.json (runtime dependencies) like build-release.sh.
jq --slurp '.[0] * .[1] | .name = "code-oss"' \
  "$ROOT/lib/vscode/remote/package.json" \
  "$RELEASE/lib/vscode/package.json" > "$RELEASE/lib/vscode/package.json.merged"
mv "$RELEASE/lib/vscode/package.json.merged" "$RELEASE/lib/vscode/package.json"
# npm-shrinkwrap files are generated from the lockfiles (build-release.sh runs
# `npm shrinkwrap`; the contents are equivalent for our purposes).
cp "$ROOT/lib/vscode/remote/package-lock.json" "$RELEASE/lib/vscode/npm-shrinkwrap.json"

# Global extension dependencies.
cp "$ROOT/lib/vscode/extensions/package.json" "$RELEASE/lib/vscode/extensions/package.json"
cp "$ROOT/lib/vscode/extensions/package-lock.json" "$RELEASE/lib/vscode/extensions/npm-shrinkwrap.json"
cp "$ROOT/lib/vscode/extensions/postinstall.mjs" "$RELEASE/lib/vscode/extensions/postinstall.mjs"

# code-server package.json (no scripts/devDependencies) + npm postinstall helper.
jq --slurp '(.[0] | del(.scripts,.jest,.devDependencies)) * .[1]' \
  "$ROOT/package.json" <(
  cat << EOF
{
  "version": "0.0.0",
  "commit": "$(git -C "$ROOT" rev-parse HEAD)",
  "scripts": {
    "postinstall": "sh ./postinstall.sh"
  }
}
EOF
) > "$RELEASE/package.json"
cp "$ROOT/ci/build/npm-postinstall.sh" "$RELEASE/postinstall.sh"

# Quick sanity check (same as build-release.sh).
if ! jq -e .commit "$RELEASE/lib/vscode/product.json" >/dev/null; then
  echo "'commit' is missing from release/lib/vscode/product.json" >&2
  exit 1
fi

echo "release/ ready:"
echo "  release/out/node/entry.js"
echo "  release/lib/vscode/out/server-main.js"
du -sh "$RELEASE" | sed 's/^/  /'
