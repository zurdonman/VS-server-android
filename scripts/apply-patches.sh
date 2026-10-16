#!/usr/bin/env bash
# Applies the quilt patch stack in patches/series to lib/vscode without needing
# quilt (GNU patch is enough). Safe to re-run: skips patches already applied.
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -f lib/vscode/package.json ]]; then
  echo "lib/vscode is missing. Run scripts/termux-setup.sh (or scripts/fetch-vscode.sh) first." >&2
  exit 1
fi

MARKER=".patches-applied"
EXPECTED=$(grep -c '' patches/series)

if [[ -f $MARKER ]] && [[ $(cat "$MARKER") == "$EXPECTED" ]]; then
  echo "Patches already applied (marker $MARKER). Skipping."
  exit 0
fi

while read -r p; do
  [[ -z $p ]] && continue
  if patch -p1 --forward --no-backup-if-mismatch < "patches/$p" >/dev/null 2>&1; then
    echo "OK   $p"
  elif patch -p1 --reverse --dry-run --no-backup-if-mismatch < "patches/$p" >/dev/null 2>&1; then
    echo "SKIP $p (already applied)"
  else
    echo "FAIL $p" >&2
    patch -p1 --forward --no-backup-if-mismatch < "patches/$p" || true
    exit 1
  fi
done < patches/series

echo "$EXPECTED" > "$MARKER"
echo "All patches applied."
