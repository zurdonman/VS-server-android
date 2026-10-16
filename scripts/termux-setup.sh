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

echo "==> [1/6] Installing Termux packages"
pkg update -y
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
  || pkg install -y git nodejs python make clang pkg-config binutils patch jq ripgrep krb5 \
  || pkg install -y git nodejs python make clang pkg-config binutils patch jq ripgrep

echo "    Node: $(node -v)"
python3 -m pip install --quiet --upgrade pip >/dev/null 2>&1 || true
npm config set python python3

echo "==> [2/6] Fetching the VS Code source tree"
bash scripts/fetch-vscode.sh

echo "==> [3/6] Applying the patch stack (upstream + mobile fixes)"
bash scripts/apply-patches.sh

echo "==> [4/6] Installing npm dependencies"
# The upstream .npmrc in lib/vscode targets Electron; on Termux we build native
# modules against the system Node instead.
export npm_config_runtime=node
export npm_config_target="$(node -p 'process.version.slice(1)')"
export npm_config_disturl="https://nodejs.org/dist"
export npm_config_build_from_source=true
export npm_config_nodedir="${PREFIX:-/data/data/com.termux/files/usr}"
# Not needed to build/run the server: e2e test browsers and the ONNX runtime for
# experimental AI features (huge downloads).
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
export FOUNDRY_LOCAL_SKIP_INSTALL=1
export ELECTRON_SKIP_BINARY_DOWNLOAD=1
npm install --no-audit --no-fund

echo "==> [5/6] Fixing ripgrep for Android (prebuilt binary is glibc-only)"
for RG in \
  "lib/vscode/node_modules/@vscode/ripgrep/bin/rg" \
  "lib/vscode/node_modules/@vscode/ripgrep-universal/bin/linux-x64/rg" \
  "lib/vscode/node_modules/@vscode/ripgrep-universal/bin/linux-arm64/rg"
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

echo "==> [6/6] Building code-server + VS Code web (this is the slow part)"
npm run build
VERSION="${VERSION:-0.0.0}" bash scripts/build-vscode-web.sh

echo "==> Assembling the runnable release"
bash scripts/assemble-release.sh

echo ""
echo "=============================================================="
echo " Build finished. Start VS Code Server with:"
echo "     bash scripts/termux-start.sh"
echo " Debug mode (logs en Descargas/log/):"
echo "     bash scripts/termux-start.sh debug"
echo " then open http://localhost:8080 (or http://<tu-ip>:8080)"
echo "=============================================================="
