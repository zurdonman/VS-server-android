#!/usr/bin/env bash
# postinstall del paquete npm "vs-server-android".
#
# El VS Code ya viene compilado dentro del paquete; aqui solo se compilan los
# modulos nativos PEQUEÑOS para Android (Bionic/aarch64): node-pty, spdlog,
# sqlite3 y @parcel/watcher. Es exactamente lo que hace el code-server oficial
# al instalarse en Termux, pero con el motor de VS Code ya compilado.
#
# Estrategia: primero se instalan TODAS las dependencias sin compilar
# (rapido) y despues se compilan una a una las nativas que hacen falta. Asi
# que una opcional que falle (kerberos, por ejemplo) no tira el resto.
#
# Toda la salida va a Descargas/log/setup.log y, si algo falla, se imprime
# solo un bloque corto que se puede copiar y pegar.
set -uo pipefail

PKG="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
RELEASE="$PKG/release"

DL="$HOME/storage/downloads"
if [[ ! -d $DL ]] && command -v termux-setup-storage >/dev/null 2>&1; then
  termux-setup-storage >/dev/null 2>&1 || true
  sleep 2
fi
if [[ -d $DL ]]; then
  LOG_DIR="$DL/log"
else
  LOG_DIR="$PKG/log"
fi
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/setup.log"

echo "==> Compilando las piezas nativas para Android (~10 min)"
echo "    Log: $LOG_FILE"
{
  echo ""
  echo "===== vs-server-android postinstall $(date) ====="
} >> "$LOG_FILE"

exec > >(tee -a "$LOG_FILE") 2>&1

export PYTHON=python3
export npm_config_runtime=node
export npm_config_target="$(node -p 'process.version.slice(1)' 2>/dev/null || echo 24.0.0)"
export npm_config_disturl="https://nodejs.org/dist"
export npm_config_build_from_source=true
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
export FOUNDRY_LOCAL_SKIP_INSTALL=1
export ELECTRON_SKIP_BINARY_DOWNLOAD=1
# El postinstall oficial de code-server exige node 24 exacto; usamos el mayor
# de la version que estamos ejecutando para no abortar la instalacion.
export FORCE_NODE_VERSION="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 24)"

# Prefijo de Node: en Termux es $PREFIX, pero si no existe (u otro entorno)
# se deduce de la ruta del propio binario node (asi node-gyp encuentra las
# cabeceras y compila bien).
NODE_BIN="$(command -v node || true)"
if [[ -n "$NODE_BIN" ]]; then
  NODE_PREFIX="$(cd "$(dirname "$(dirname "$(readlink -f "$NODE_BIN")")")" && pwd)"
else
  NODE_PREFIX="/data/data/com.termux/files/usr"
fi
export npm_config_nodedir="${PREFIX:-$NODE_PREFIX}"

# krb5 lo necesita el modulo 'kerberos' del servidor.
if command -v pkg >/dev/null 2>&1; then
  echo "==> Asegurando krb5 (necesario para kerberos)"
  pkg install -y krb5 || true
fi

FAILED=0
step() { echo ""; echo "--- $*"; }

# 1) Dependencias del servidor (sin compilar nativos todavia).
step "Dependencias del servidor (sin scripts)"
( cd "$RELEASE" && npm install --omit=dev --no-audit --no-fund --ignore-scripts ) || FAILED=1

# 2) Dependencias del VS Code server (sin scripts).
step "Dependencias de lib/vscode (sin scripts)"
( cd "$RELEASE/lib/vscode" && npm install --omit=dev --no-audit --no-fund --ignore-scripts ) || FAILED=1

# 3) Dependencias de las extensiones.
step "Dependencias de las extensiones (sin scripts)"
( cd "$RELEASE/lib/vscode/extensions" && npm install --omit=dev --no-audit --no-fund --ignore-scripts ) || true

# 4) Ahora si, las nativas que hacen falta, una a una.
NATIVES=(node-pty @vscode/spdlog @vscode/sqlite3 @parcel/watcher @vscode/ripgrep-universal)
for dir in "$RELEASE/lib/vscode" "$RELEASE"; do
  [[ -d "$dir/node_modules" ]] || continue
  for m in "${NATIVES[@]}"; do
    if [[ -d "$dir/node_modules/$m" ]]; then
      step "Compilando $m en ${dir#$PKG/}"
      ( cd "$dir" && npm rebuild "$m" ) || FAILED=1
    fi
  done
done

# 5) argon2 (hash de contrasenas del servidor) y demas con binario nativo.
step "Compilando argon2 (servidor)"
( cd "$RELEASE" && npm rebuild argon2 ) || FAILED=1

# 5b) kerberos: necesita krb5; es opcional para el uso normal.
if [[ -d "$RELEASE/lib/vscode/node_modules/kerberos" ]]; then
  step "Compilando kerberos (opcional, necesita krb5)"
  ( cd "$RELEASE/lib/vscode" && npm rebuild kerberos ) || echo "AVISO: kerberos no se pudo compilar (no afecta al uso normal)."
fi

# 6) El ripgrep precompilado es glibc: en Android usamos el rg de Termux.
if command -v rg >/dev/null 2>&1; then
  for RG in \
    "$RELEASE/lib/vscode/node_modules/@vscode/ripgrep/bin/rg" \
    "$RELEASE/lib/vscode/node_modules/@vscode/ripgrep-universal/bin/linux-x64/rg" \
    "$RELEASE/lib/vscode/node_modules/@vscode/ripgrep-universal/bin/linux-arm64/rg"
  do
    if [[ -f "$RG" ]]; then
      printf '#!/usr/bin/env bash\nexec rg "$@"\n' > "$RG"
      chmod +x "$RG"
    fi
  done
  echo "ripgrep: se usa el rg de Termux."
fi

if [[ $FAILED -eq 0 ]]; then
  touch "$RELEASE/.native-install-ok"
  echo ""
  echo "=============================================================="
  echo " INSTALACION CORRECTA"
  echo "   Arranca el servidor con:  vs-server"
  echo "   (http://localhost:8080)"
  echo "   Modo depuracion:         vs-server-debug"
  echo "   Log de esta instalacion:  $LOG_FILE"
  echo "=============================================================="
else
  echo ""
  echo "=============================================================="
  echo " INSTALACION FALLIDA (las piezas nativas)"
  echo " Copia este bloque y mandamelo:"
  echo "--------------------------------------------------------------"
  tail -n 25 "$LOG_FILE"
  echo "--------------------------------------------------------------"
  echo " Log completo: $LOG_FILE"
  echo " Reintentar:   npm install -g https://github.com/zurdonman/VS-server-android/releases/latest/download/vs-server-android-npm.tar.gz --force"
  echo "=============================================================="
fi

# Salimos con 0 para que npm no desinstale el paquete si algo falla: asi el
# usuario puede reintentar sin volver a descargarlo todo.
exit 0
