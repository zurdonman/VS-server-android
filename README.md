# VS Server Android

**VS Code Server optimizado para Android y móviles.** Fork de
[code-server](https://github.com/coder/code-server) (VS Code en el navegador)
con arreglos reales para que sea usable desde el móvil: Enter funcional con
teclados virtuales, barra táctil de teclas especiales, y pantalla que se adapta
al teclado virtual en lugar de quedar tapada por él.

> 🇪🇸 Documentación en español. El código y los comentarios de los parches están
> en inglés (estilo upstream).

## ⚡ Comandos rápidos (Termux en el móvil)

**Opción rápida (recomendada)** — descarga el build precopilado y solo compila
unas piezas nativas en el móvil (~10 min), como el code-server oficial:

```sh
pkg install -y git
git clone -b arena/55960f6b-vs-server-android https://github.com/zurdonman/VS-server-android.git ~/vs-server
cd ~/vs-server
bash scripts/termux-fast-setup.sh
```

**Opción completa** — compila todo desde el código en el propio móvil (20-60 min):

```sh
pkg install -y git
git clone -b arena/55960f6b-vs-server-android https://github.com/zurdonman/VS-server-android.git ~/vs-server
cd ~/vs-server
bash scripts/termux-setup.sh
```

> Usa una carpeta propia (`~/vs-server`) para el proyecto, no una subcarpeta de
> otro proyecto.

Y después, **desde cualquier carpeta**, con dos comandos fáciles de recordar:

```sh
vs-server                        # arranca en http://localhost:8080
vs-server-debug                  # modo debug: logs en Descargas/log/
```

> Si por costumbre escribes `vs-code` / `vs-code-debug`, también funcionan
> (son alias de los mismos comandos).

> `termux-setup.sh` instala esos comandos en el PATH de Termux. Si algún día
> no los encuentras, cierra y vuelve a abrir Termux (o usa
> `bash scripts/termux-start.sh` / `bash scripts/termux-start.sh debug` dentro
> de la carpeta del proyecto, que es lo mismo).

## 🔄 Actualizar (el "pull" de siempre)

```sh
vs-update
```

Eso hace `git pull` y **solo recompila lo que haya cambiado** (si la
actualización es de documentación o scripts, es al instante). Si prefieres
hacerlo a mano:

```sh
cd ~/vs-server
git pull
```

> **Importante**: si acabas de hacer `git pull` a mano y los comandos cortos no
> existen aún en tu móvil (pasó si instalaste antes de que se añadieran),
> ejecuta una sola vez `bash scripts/termux-update.sh` desde la carpeta del
> proyecto: es instantáneo y deja `vs-server`, `vs-server-debug` y `vs-update`
> instalados en el PATH.

> Nota: se clona la rama `arena/55960f6b-vs-server-android` porque el PR #1 aún no
> está fusionado en `main`. Tras fusionarlo, `git clone` sin `-b` ya sirve.

## 🐛 Modo debug (logs para diagnosticar errores)

`vs-server-debug` (o `bash scripts/termux-start.sh debug`) arranca igual pero
**registrando todo lo que pasa** en la carpeta **`Descargas/log/`** (se crea sola dentro de
`Downloads`; la primera vez Termux pide permiso de almacenamiento — acepta):

| Archivo                | Qué guarda                                                                                                                                                                                                                                        |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `server.log`           | Todo el servidor: errores, peticiones, trazas                                                                                                                                                                                                     |
| `client.log`           | El **navegador**: errores de consola, excepciones, peticiones rechazadas y **trazas de teclado reales** (qué teclas/beforeinput manda el teclado virtual — justo lo que hace falta para depurar Enter/IME), cambios de foco y del teclado virtual |
| `vscode-logs-<fecha>/` | Logs internos de VS Code (se copian al cerrar)                                                                                                                                                                                                    |

Si algo te falla: **mándame la carpeta `Descargas/log/` entera** (o su contenido)
y con ella puedo ver exactamente qué evento llega (o no llega) y por qué.

## ❌ El problema

`code-server` corre, pero en Android fallan cosas básicas:

- **Enter no hace nada** (ni en el editor ni en la terminal). Los teclados
  virtuales (Gboard, etc.) no envían teclas normales: envían eventos de
  _composición_ (`keyCode 229`) y ediciones `beforeinput` que VS Code y xterm.js
  se tragaban sin insertar el salto de línea.
- **No hay teclas especiales**: Esc, Tab, Ctrl, Alt, flechas… no existen en el
  teclado táctil. Imposible cancelar un autocompletado, hacer Tab, Ctrl+C…
- **El teclado virtual tapa el editor**: al abrirse el teclado, Android no
  cambia `window.innerHeight`, y la mitad inferior de VS Code queda oculta.
- **Atajos y Tab rotos**: los teclados táctiles no rellenan `KeyboardEvent.code`
  y el despacho por `code` no funciona.

## ✅ Lo que arregla este fork

| Arreglo                         | Qué hace                                                                                                                                                                                                                                                                       |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `mobile-editor-input.diff`      | Enter (y ⌫/Supr del teclado virtual) ahora insertan salto de línea y borrados en el editor, en ambos modos de entrada (textarea y EditContext), sin duplicar saltos con teclado físico                                                                                         |
| `mobile-terminal-input.diff`    | Enter envía `\r` a la terminal (xterm.js) aunque el teclado virtual mande `keyCode 229`                                                                                                                                                                                        |
| `mobile-keyboard-dispatch.diff` | `keyboard.dispatch` por defecto es `keyCode` en móviles → atajos y Tab vuelven a funcionar                                                                                                                                                                                     |
| `mobile-touch-bar.diff`         | **Barra táctil flotante** (Esc, Tab, Ctrl, Alt, Shift, flechas, Inicio/Fin, ⌫, Supr, Enter, ⌨) + modificadores pegajosos (Ctrl+C, Shift+flechas…) + el layout se re-ancla al `visualViewport` para que el teclado no tape el editor                                            |
| `mobile-viewport.diff`          | `viewport-fit=cover` para móviles con muescas                                                                                                                                                                                                                                  |
| `mobile-gestures.diff`          | **Zoom con dos dedos (pinch)** sobre el texto del editor (cambia el tamaño de la letra y se guarda) + **scroll suave** (`editor.smoothScrolling`) para que el dedo no dé saltos                                                                                                |
| `mobile-zoom.diff`              | **Zoom nativo del navegador** habilitado (VS Code lo desactiva con `user-scalable=no`): con dos dedos puedes agrandar toda la interfaz                                                                                                                                         |
| `mobile-external-open.diff`     | Si el navegador **bloquea** la apertura de una pestaña (los logins OAuth abren la URL después de varias esperas y el "gesto" ya ha caducado → _"no pasa nada"_), ahora se detecta y se ofrece un botón **Reintentar / Abrir en esta pestaña**                                  |
| `mobile-ui-kind.diff`           | El extension host remoto se identifica como **escritorio** (`UIKind.Desktop`) en el móvil → las extensiones con login por callback local (**Google Colab**, GitHub…) usan el flujo de loopback en `127.0.0.1`, que **sí funciona en el móvil** (login real, sin pegar códigos) |

Extras incluidos:

- `misc/android-as-linux.js` — permite instalar extensiones de servidor en
  Android (la marketplace rechaza la plataforma `android`; este preload se hace
  pasar por `linux`). Activo por defecto en `termux-start.sh`
  (desactivable con `CS_ANDROID_AS_LINUX=0`).

## 📱 Instalación (Termux en el propio móvil)

Hay dos formas. **Ninguna compila el motor de VS Code en el móvil**: ese
trabajo pesado se hace en CI (GitHub Actions) y tú solo descargas el resultado
(igual que hace el `code-server` oficial al instalarse).

### Opción A — Como el code-server oficial (un comando)

```sh
npm install -g --force https://github.com/zurdonman/VS-server-android/releases/latest/download/vs-server-android-npm.tar.gz
```

Esto instala los comandos `vs-server`, `vs-server-debug` y `vs-update` en el
PATH. En el móvil solo se compilan los módulos nativos pequeños
(`node-pty`, `spdlog`, `sqlite3`, `@parcel/watcher`): unos 10 minutos.

> `--force` hace falta si ya tenías una instalación anterior de este proyecto:
> npm no pisa los enlaces que ya existen en `$PREFIX/bin` (`vs-server`,
> `vs-code`, …) y aborta con `EEXIST`. Con `--force` los sustituye por los
> nuevos (los antiguos apuntaban a `~/vs-server`, que ya no hace falta).

### Opción B — Desde el clon del repositorio (un comando)

```sh
git clone https://github.com/zurdonman/VS-server-android.git
cd VS-server-android
bash scripts/termux-install-npm.sh
```

Este script instala el mismo paquete npm que la opción A (y de paso limpia los
enlaces de una instalación anterior, que si no hacen que npm aborte con
`EEXIST`).

El script descarga el build precompilado del release, lo extrae, compila las
mismas piezas nativas y deja los comandos en el PATH.

En ambos casos:

```sh
vs-server
```

y abre `http://localhost:8080` en el navegador del móvil (Chrome recomendado).
Desde otro dispositivo en la misma red: `http://<ip-del-móvil>:8080`.

### Opción C — Compilarlo todo en el móvil (solo si quieres)

```sh
bash scripts/termux-setup.sh
```

Compila todo desde cero en el móvil: **20–60 min**, necesita ~6 GB de
espacio y bastante RAM. Necesita almacenamiento compartido (y evita
`/sdcard` para git).

### Variables útiles

| Variable                | Efecto                                             |
| ----------------------- | -------------------------------------------------- |
| `CS_AUTH=none`          | Sin contraseña (solo red local de confianza)       |
| `CS_PORT=8081`          | Cambiar puerto                                     |
| `CS_ANDROID_AS_LINUX=0` | Desactivar el "truco" de extensiones Android→Linux |
| `CS_MAX_MEMORY=2048`    | Límite de memoria de Node (MB)                     |

## 🎛️ Cómo usar la barra táctil

Aparece abajo del todo en pantallas táctiles (ajustable con el setting
`mobileKeyboard.enabled`: `auto` / `on` / `off`).

- **Esc / Tab / flechas / Inicio / Fin / ⌫ / Supr / Enter** — se envían a donde
  tengas el foco (editor, terminal, listas…).
- **Ctrl / Alt / Shift** — se _pegan_ (se iluminan). Con uno activo, la próxima
  tecla del teclado virtual se envía con ese modificador: `Ctrl` + `c` = Ctrl+C
  en la terminal, `Shift` + `←` = selección, etc. Se desactivan solos tras un uso.
- **⌨** — enfoca el editor/terminal y abre el teclado virtual.
- **▾** — oculta la barra (queda un botón flotante `⌨` para recuperarla).
- La barra se coloca **encima** del teclado virtual cuando este se abre.

## 🔍 Zoom con los dedos y scroll cómodo

- **Pinch (dos dedos)** sobre el editor → cambia el **tamaño de la letra** (de 8
  a 40 px, de 2 en 2). Se guarda en tu configuración, así que se mantiene al
  recargar la página.
- **Scroll suave**: el desplazamiento con el dedo es continuo, sin saltos
  (equivale a `editor.smoothScrolling: true`, que se activa solo si no lo has
  configurado tú).
- **Pinch en cualquier otro sitio** (barra lateral, paneles, menús) hace el
  **zoom nativo del navegador**: ahora el zoom de página está habilitado
  (`mobile-zoom.diff` quita el `user-scalable=no` de VS Code), así que puedes
  agrandar la interfaz entera con los dedos.
- En el editor el pinch lo controlamos nosotros (para cambiar el tamaño de la
  letra de forma persistente), así que no se mezcla con el zoom del navegador.

## 🔐 Login de Google (Colab) en el móvil

El problema: en el móvil, el login de Google/Colab "no pasaba nada". La causa era
doble:

1. **El navegador bloqueaba la pestaña** que abre el login (OAuth tarda varias
   esperas, el "gesto" del usuario caduca y Chrome bloquea el popup). Ahora se
   detecta el bloqueo y sale un aviso con **Reintentar** o **Abrir en esta
   pestaña** (toques reales → siempre funciona).
2. **VS Code web se identificaba como navegador**, y la extensión de Colab en
   ese caso usa un flujo de login que necesita un servidor de callbacks que no
   existe en el móvil. Con `mobile-ui-kind.diff` el extension host se
   identifica como escritorio, así que Colab usa el flujo **loopback**: levanta
   un servidor en `127.0.0.1` **dentro del propio móvil**, Google vuelve a esa
   dirección y **el login se completa solo** (sin copiar códigos a mano).

Si prefieres pegar el código manualmente, también funciona: la extensión
sigue mostrando esa opción.

## 🧩 Extensiones en Android

Android no es Linux del todo: la marketplace de VS Code solo permite _web
extensions_. Con `misc/android-as-linux.js` (activado por defecto en
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
  bin/vs-server              ← comando corto `vs-server` (arranque normal)
  bin/vs-server-debug        ← comando corto `vs-server-debug` (logs en Descargas/log/)
  termux-start.sh            ← arranque (normal y debug: logs en Descargas/log/)
  fetch-vscode.sh            ← descarga VS Code en el commit fijado
  apply-patches.sh           ← aplica patches/series (no necesita quilt)
  assemble-release.sh        ← empaqueta release/ listo para lanzar
misc/android-as-linux.js     ← preload para extensiones
src/node/routes/androidDebug.ts ← endpoint de logs del modo debug
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
bash scripts/assemble-release.sh
vs-server                               # o: vs-server-debug
```

## 📄 Créditos y licencia

- Basado en [coder/code-server](https://github.com/coder/code-server) (Apache-2.0)
  y [microsoft/vscode](https://github.com/microsoft/vscode) (MIT). Mantén los
  ficheros `LICENSE` y `ThirdPartyNotices.txt`.
- Los arreglos móviles viven en `patches/mobile-*.diff` y son parte de este fork.

¡Issues y PRs bienvenidos!
