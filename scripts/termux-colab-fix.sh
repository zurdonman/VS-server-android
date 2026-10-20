#!/usr/bin/env bash
# VS Code Server Android — colab-fix
#
# La extension de Colab (google.colab-vscode) pide a Google Drive con el
# scope "drive.file", que segun Google solo da acceso a los ficheros que creo
# la propia app de Colab. Por eso, al importar un notebook que ya existia en
# tu Drive, Google responde 404 "File not found" aunque el login sea correcto.
#
# Este script cambia ese scope por "drive.readonly" (lectura de todo tu Drive)
# en la extension instalada. Despues hay que cerrar sesion y volver a entrar
# en Colab para que se emita un token nuevo con el scope bueno.
#
#   colab-fix            -> aplica el parche
#   colab-fix --revert   -> lo deshace
#   colab-fix --status   -> dice como esta
set -euo pipefail

SCOPE_OLD="https://www.googleapis.com/auth/drive.file"
SCOPE_NEW="https://www.googleapis.com/auth/drive.readonly"

find_ext() {
  local base d
  for base in \
    "$HOME/.local/share/code-server/extensions" \
    "$HOME/.vscode-server/extensions" \
    "$HOME/.local/share/code-server/data/extensions" \
    "$HOME/.vscode/extensions"; do
    [[ -d $base ]] || continue
    d="$(find "$base" -maxdepth 1 -type d -name 'google.colab-vscode*' 2>/dev/null | sort | tail -n 1)"
    if [[ -n $d ]]; then
      echo "$d"
      return 0
    fi
  done
  return 1
}

MODE="${1:-apply}"

EXT_DIR="$(find_ext || true)"
if [[ -z ${EXT_DIR:-} ]]; then
  echo "No encuentro la extension de Colab instalada."
  echo ""
  echo "Instala la extension 'Colab' (google.colab-vscode) desde el"
  echo "marketplace y vuelve a ejecutar este comando."
  exit 1
fi

echo "Extension: $EXT_DIR"

# Ficheros de codigo de la extension.
mapfile -t FILES_OLD < <(grep -rl --include='*.js' -- "$SCOPE_OLD" "$EXT_DIR" 2>/dev/null | sort)
mapfile -t FILES_NEW < <(grep -rl --include='*.js' -- "$SCOPE_NEW" "$EXT_DIR" 2>/dev/null | sort)

case "$MODE" in
  --revert | revert)
    if [[ ${#FILES_NEW[@]} -eq 0 ]]; then
      echo "No hay nada que revertir (no esta parcheada)."
      exit 0
    fi
    for f in "${FILES_NEW[@]}"; do
      if [[ -f "$f.colabbak" ]]; then
        mv -f "$f.colabbak" "$f"
        echo "  revertido: $f"
      else
        sed -i "s|$SCOPE_NEW|$SCOPE_OLD|g" "$f"
        echo "  revertido (sin backup): $f"
      fi
    done
    echo ""
    echo "Listo. Reinicia el servidor y vuelve a entrar en Colab."
    ;;
  --status | status)
    if [[ ${#FILES_OLD[@]} -gt 0 ]]; then
      echo "Estado: SIN parchear (scope drive.file) -> el import de Drive"
      echo "        solo ve los ficheros que creo la propia app de Colab."
    elif [[ ${#FILES_NEW[@]} -gt 0 ]]; then
      echo "Estado: parcheada (scope drive.readonly)."
    else
      echo "Estado: desconocido (no se encuentra el scope en la extension)."
    fi
    ;;
  apply | *)
    if [[ ${#FILES_OLD[@]} -eq 0 ]]; then
      if [[ ${#FILES_NEW[@]} -gt 0 ]]; then
        echo "Ya esta parcheada (scope drive.readonly)."
        exit 0
      fi
      echo "No encuentro el scope '$SCOPE_OLD' en la extension."
      echo "Puede que la extension se haya actualizado: reinstala y prueba otra vez."
      exit 1
    fi
    for f in "${FILES_OLD[@]}"; do
      [[ -f "$f.colabbak" ]] || cp -p "$f" "$f.colabbak"
      sed -i "s|$SCOPE_OLD|$SCOPE_NEW|g" "$f"
      echo "  parcheado: $f"
    done
    echo ""
    echo "Listo. Ahora:"
    echo "  1) Reinicia el servidor (vs-update lo hace, o Ctrl-C y 'vs-server')."
    echo "  2) En VS Code: 'Colab: Sign out' (command palette)."
    echo "  3) Vuelve a iniciar sesion en Colab (asi se emite el token nuevo)."
    echo "  4) 'Colab: Import notebook file from URL' con el enlace del notebook."
    echo ""
    echo "Si el login deja de funcionar, ejecuta:  colab-fix --revert"
    ;;
esac
