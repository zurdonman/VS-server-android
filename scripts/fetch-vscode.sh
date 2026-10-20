#!/usr/bin/env bash
# Fetches the VS Code source tree pinned by this fork into lib/vscode.
set -euo pipefail

cd "$(dirname "$0")/.."

# The VS Code commit this fork is based on (microsoft/vscode @ code-server v4.141.0).
VSCODE_SHA="${VSCODE_SHA:-2a59476c9bfcb90b3ddc372c36762471b7dfad1c}"

if [[ -f lib/vscode/package.json ]]; then
  echo "lib/vscode already present."
  exit 0
fi

mkdir -p lib/vscode
cd lib/vscode
git init -q .
git remote add origin https://github.com/microsoft/vscode 2>/dev/null || true
echo "Fetching VS Code at $VSCODE_SHA (shallow)..."
git fetch --depth 1 origin "$VSCODE_SHA"
git checkout -q FETCH_HEAD
echo "VS Code $(node -p "require('./package.json').version") ready."
