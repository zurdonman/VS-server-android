# VS Server Android

**VS Code Server optimizado para Android y móviles.** Fork de
[code-server](https://github.com/coder/code-server) (VS Code en el navegador)
con arreglos reales para que sea usable desde el móvil: Enter funcional con
teclados virtuales, barra táctil de teclas especiales, y pantalla que se adapta
al teclado virtual en lugar de quedar tapada por él.

> 🇪🇸 Documentación en español. El código y los comentarios de los parches están
> en inglés (estilo upstream).

## ❌ El problema

`code-server` corre, pero en Android fallan cosas básicas:

- **Enter no hace nada** (ni en el editor ni en la terminal). Los teclados
  virtuales (Gboard, etc.) no envían teclas normales: envían eventos de
  *composición* (`keyCode 229`) y ediciones `beforeinput` que VS Code y xterm.js
  se tragaban sin insertar el salto de línea.
- **No hay teclas especiales**: Esc, Tab, Ctrl, Alt, flechas… no existen en el
  teclado táctil. Imposible cancelar un autocompletado, hacer Tab, Ctrl+C…
- **El teclado virtual tapa el editor**: al abrirse el teclado, Android no
  cambia `window.innerHeight`, y la mitad inferior de VS Code queda oculta.
- **Atajos y Tab rotos**: los teclados táctiles no rellenan `KeyboardEvent.code`
  y el despacho por `code` no funciona.

## ✅ Lo que arregla este fork

| Arreglo | Qué hace |
|---|---|
| `mobile-editor-input.diff` | Enter (y ⌫/Supr del teclado virtual) ahora insertan salto de línea y borrados en el editor, en ambos modos de entrada (textarea y EditContext), sin duplicar saltos con teclado físico |
| `mobile-terminal-input.diff` | Enter envía `\r` a la terminal (xterm.js) aunque el teclado virtual mande `keyCode 229` |
| `mobile-keyboard-dispatch.diff` | `keyboard.dispatch` por defecto es `keyCode` en móviles → atajos y Tab vuelven a funcionar |
| `mobile-touch-bar.diff` | **Barra táctil flotante** (Esc, Tab, Ctrl, Alt, Shift, flechas, Inicio/Fin, ⌫, Supr, Enter, ⌨) + modificadores pegajosos (Ctrl+C, Shift+flechas…) + el layout se re-ancla al `visualViewport` para que el teclado no tape el editor |
| `mobile-viewport.diff` | `viewport-fit=cover` para móviles con muescas |

Extras incluidos:

- `misc/android-as-linux.js` — permite instalar extensiones de servidor en
  Android (la marketplace rechaza la plataforma `android`; este preload se hace
  pasar por `linux`). Activo por defecto en `termux-start.sh`
  (desactivable con `CS_ANDROID_AS_LINUX=0`).

## 📱 Instalación (Termux en el propio móvil)

1. Instala **Termux desde [F-Droid](https://f-droid.org/en/packages/com.termux/)**
   (la versión de Play Store está desactualizada).

2. Clona este repositorio y ejecuta el instalador:

```sh
pkg install -y git
git clone https://github.com/zurdonman/VS-server-android.git
cd VS-server-android
bash scripts/termux-setup.sh
```

El script instala dependencias, descarga el código de VS Code (versión fijada),
aplica todos los parches y compila todo. **La compilación en el móvil es lenta**
(20–60 min según el dispositivo) y necesita espacio (~6 GB) y RAM. Si se te
queda corto el almacenamiento interno, ejecuta Termux con almacenamiento
compartido y clona en `~/storage/shared/…` (aunque evita `/sdcard` para git).

3. Arranca:

```sh
bash scripts/termux-start.sh
```

4. Abre `http://localhost:8080` en el navegador del móvil (Chrome recomendado).
   Desde otro dispositivo en la misma red: `http://<ip-del-móvil>:8080`.

### Variables útiles

| Variable | Efecto |
|---|---|
| `CS_AUTH=none` | Sin contraseña (solo red local de confianza) |
| `CS_PORT=8081` | Cambiar puerto |
| `CS_ANDROID_AS_LINUX=0` | Desactivar el "truco" de extensiones Android→Linux |
| `CS_MAX_MEMORY=2048` | Límite de memoria de Node (MB) |

## 🎛️ Cómo usar la barra táctil

Aparece abajo del todo en pantallas táctiles (ajustable con el setting
`mobileKeyboard.enabled`: `auto` / `on` / `off`).

- **Esc / Tab / flechas / Inicio / Fin / ⌫ / Supr / Enter** — se envían a donde
  tengas el foco (editor, terminal, listas…).
- **Ctrl / Alt / Shift** — se *pegan* (se iluminan). Con uno activo, la próxima
  tecla del teclado virtual se envía con ese modificador: `Ctrl` + `c` = Ctrl+C
  en la terminal, `Shift` + `←` = selección, etc. Se desactivan solos tras un uso.
- **⌨** — enfoca el editor/terminal y abre el teclado virtual.
- **▾** — oculta la barra (queda un botón flotante `⌨` para recuperarla).
- La barra se coloca **encima** del teclado virtual cuando este se abre.

## 🧩 Extensiones en Android

Android no es Linux del todo: la marketplace de VS Code solo permite *web
extensions*. Con `misc/android-as-linux.js` (activado por defecto en
`termux-start.sh`) el servidor se identifica como Linux y puedes instalar
extensiones de servidor. Si una extensión con componentes nativos falla,
desactívalo con `CS_ANDROID_AS_LINUX=0` e instala el `.vsix` a mano.

## 🛠️ Estructura del fork (para contribuir)

Este repositorio es un fork completo de `coder/code-server` **v4.141.0** con:

```
patches/                     ← parches sobre lib/vscode (VS Code 1.141.0)
  series                     ← orden de aplicación (quilt)
  mobile-*.diff              ← los arreglos móviles de este fork
scripts/
  termux-setup.sh            ← instalación completa en Termux
  termux-start.sh            ← arranque con opciones móviles
  fetch-vscode.sh            ← descarga VS Code en el commit fijado
  apply-patches.sh           ← aplica patches/series (no necesita quilt)
misc/android-as-linux.js     ← preload para extensiones
lib/vscode                   ← submódulo: fuente de VS Code (se descarga)
```

Los propios parches de code-server usan `quilt`; los nuestros siguen el mismo
formato y se aplican con `scripts/apply-patches.sh` (GNU patch) o con
`quilt push -a` si lo tienes instalado.

Para modificar los parches: aplica, edita en `lib/vscode`, y regenera el `.diff`
correspondiente (mismo estilo: `Index: code-server/lib/vscode/...`).

### Desarrollo en un PC

Lo mismo pero en Linux/macOS:

```sh
git clone https://github.com/zurdonman/VS-server-android.git
cd VS-server-android
bash scripts/fetch-vscode.sh
bash scripts/apply-patches.sh
npm install
npm run build
VERSION=0.0.0 npm run build:vscode
bash scripts/termux-start.sh
```

## 📄 Créditos y licencia

- Basado en [coder/code-server](https://github.com/coder/code-server) (Apache-2.0)
  y [microsoft/vscode](https://github.com/microsoft/vscode) (MIT). Mantén los
  ficheros `LICENSE` y `ThirdPartyNotices.txt`.
- Los arreglos móviles viven en `patches/mobile-*.diff` y son parte de este fork.

¡Issues y PRs bienvenidos!
