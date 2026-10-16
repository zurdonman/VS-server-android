#!/usr/bin/env bash
# VS Server Android — launcher for Termux.
#
#   bash scripts/termux-start.sh            # password auth (default)
#   CS_AUTH=none bash scripts/termux-start.sh
#
# Extra arguments are passed to code-server (e.g. --port 8081 --open).
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -f out/node/entry.js ]]; then
  echo "Not built yet. Run scripts/termux-setup.sh first." >&2
  exit 1
fi

# Let server-side extensions install on Android (process.platform is "android"
# here, which the marketplace treats as an unsupported platform). Set
# CS_ANDROID_AS_LINUX=0 to disable.
if [[ "${CS_ANDROID_AS_LINUX:-1}" == "1" ]]; then
  export NODE_OPTIONS="${NODE_OPTIONS:-} --require $PWD/misc/android-as-linux.js"
fi

export NODE_OPTIONS="${NODE_OPTIONS:-} --max-old-space-size=${CS_MAX_MEMORY:-4096}"

AUTH="${CS_AUTH:-password}"
exec node out/node/entry.js --bind-addr "0.0.0.0:${CS_PORT:-8080}" --auth "$AUTH" "$@"
