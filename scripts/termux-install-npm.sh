#!/usr/bin/env bash
# VS Code Server Android — instalacion del paquete npm precompilado.
#
# Es el mismo modelo que el code-server oficial:
#   npm install -g <release asset>
# pero este script ademas:
#   1. quita los enlaces de una instalacion anterior (si los hay, npm aborta
#      con EEXIST al no pisarlos),
#   2. usa --force por si acaso,
#   3. te dice que hacer despues.
#
# El VS Code llega ya compilado; en el movil solo se compilan los modulos
# nativos pequenos (node-pty, spdlog, sqlite3, watcher) -> ~10 min.
set -euo pipefail

cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.."

REPO_URL="https://github.com/zurdonman/VS-server-android"
ASSET_URL="${VS_SERVER_ASSET_URL:-$REPO_URL/releases/latest/download/vs-server-android-npm.tar.gz}"

BIN_DIR="${PREFIX:-/data/data/com.termux/files/usr}/bin"
if [[ ! -d $BIN_DIR || ! -w $BIN_DIR ]]; then
  BIN_DIR="$HOME/.local/bin"
  mkdir -p "$BIN_DIR"
fi

echo "==> [1/3] Quitando los comandos de una instalacion anterior"
for c in vs-server vs-server-debug vs-update vs-code vs-code-debug; do
  if [[ -e "$BIN_DIR/$c" || -L "$BIN_DIR/$c" ]]; then
    echo "    quitando $BIN_DIR/$c"
    rm -f "$BIN_DIR/$c"
  fi
done

echo ""
echo "==> [2/3] Instalando el build precompilado (compila ~10 min los nativos)"
echo "    $ASSET_URL"
echo ""
if ! npm install -g --force "$ASSET_URL"; then
  echo ""
  echo "=============================================================="
  echo " LA INSTALACION NO TERMINO BIEN"
  echo " Copia este bloque y mandamelo:"
  echo "--------------------------------------------------------------"
  echo "  npm install -g --force $ASSET_URL"
  echo "--------------------------------------------------------------"
  echo " (log de npm: ~/.npm/_logs/)"
  echo "=============================================================="
  exit 1
fi

echo ""
echo "==> [3/3] Comprobando"
for c in vs-server vs-server-debug vs-update vs-code vs-code-debug; do
  if [[ -x "$BIN_DIR/$c" ]]; then
    echo "    $c  ok"
  else
    echo "    $c  NO ENCONTRADO (revisa el log de arriba)"
  fi
done

echo ""
echo "=============================================================="
echo " INSTALACION CORRECTA"
echo ""
echo "   vs-server            (arranca el servidor)"
echo "   vs-server-debug      (modo debug: logs en Descargas/log/)"
echo "   vs-update            (actualiza a la ultima version)"
echo ""
echo " Arranca con:  vs-server"
echo " y abre http://localhost:8080 en el navegador."
echo "=============================================================="
