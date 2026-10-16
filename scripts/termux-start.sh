#!/usr/bin/env bash
# VS Server Android — launcher for Termux.
#
#   bash scripts/termux-start.sh          # normal run (password auth)
#   bash scripts/termux-start.sh debug    # debug run: logs to Descargas/log/
#
#   CS_AUTH=none bash scripts/termux-start.sh      # no password
#   CS_PORT=8081 bash scripts/termux-start.sh      # other port
#
# Extra arguments are passed to code-server (e.g. --open).
set -euo pipefail

cd "$(dirname "$0")/.."

MODE="run"
if [[ "${1:-}" == "debug" ]]; then
  MODE="debug"
  shift
fi

if [[ ! -f release/out/node/entry.js ]]; then
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

ARGS=(--bind-addr "0.0.0.0:${CS_PORT:-8080}" --auth "${CS_AUTH:-password}")

if [[ $MODE != "debug" ]]; then
  exec node release/out/node/entry.js "${ARGS[@]}" "$@"
fi

# ---- debug mode: log everything into Descargas/log/ -----------------------
DL="$HOME/storage/downloads"
if [[ ! -d $DL ]] && command -v termux-setup-storage >/dev/null 2>&1; then
  echo "Requesting storage access (accept the Android permission)..."
  termux-setup-storage >/dev/null 2>&1 || true
  sleep 2
fi

if [[ -d $DL ]]; then
  LOG_DIR="$DL/log"
else
  LOG_DIR="$PWD/log"
  echo "Note: no access to Downloads yet. Run 'termux-setup-storage', accept the"
  echo "permission and re-run. Logging to $LOG_DIR instead."
fi
mkdir -p "$LOG_DIR"
export CS_DEBUG_LOG_DIR="$LOG_DIR"

SESSION="$(date +%Y%m%d-%H%M%S)"
{
  echo ""
  echo "===== session $SESSION pid $$ node $(node -v) ====="
} >> "$LOG_DIR/server.log"

copy_workbench_logs() {
  local src="$HOME/.local/share/code-server/logs"
  if [[ -d $src ]]; then
    cp -a "$src" "$LOG_DIR/vscode-logs-$SESSION" 2>/dev/null || true
  fi
}
trap copy_workbench_logs EXIT

echo "=============================================================="
echo " DEBUG MODE — logs en: $LOG_DIR"
echo "   server.log  (servidor: errores y trazas)"
echo "   client.log  (navegador: errores, teclado, teclado virtual)"
echo "   vscode-logs-$SESSION/ (logs internos de VS Code al cerrar)"
echo " Manda la carpeta log/ entera para diagnosticar cualquier fallo."
echo "=============================================================="

node release/out/node/entry.js "${ARGS[@]}" --log trace "$@" 2>&1 | tee -a "$LOG_DIR/server.log"
