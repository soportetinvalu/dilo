# Dilo

Dictado por voz para macOS, parecido a Wispr Flow, pero **la transcripción se hace 100 % en tu Mac**.
Mantienes una tecla, hablas, la sueltas y el texto aparece donde tengas el cursor (Notas, Mail, el navegador, lo que sea).

- **Voz → texto:** Parakeet TDT 0.6B v3 (español) con [FluidAudio](https://github.com/FluidInference/FluidAudio), sobre Core ML / Neural Engine. El audio nunca sale del Mac.
- **Pulido opcional:** el texto transcrito se corrige (puntuación, mayúsculas, muletillas) con **ChatGPT**, usando el programa `codex` con tu sesión «Sign in with ChatGPT». No se usa ninguna API key de pago. **Solo viaja el texto, nunca el audio.** Se puede apagar con un interruptor y, si `codex` falla o tarda demasiado, se inserta el texto sin pulir.
- **Tecla configurable:** desde Ajustes eliges qué tecla usar (incluso un modificador solo, como Option derecha, que es el valor inicial).

> Actualización 0.1.1: nombre **Dilo** e icono de la imagen proporcionada. El usuario probó la app original en su Mac; **esta actualización no se ha compilado ni ejecutado en macOS**. Para actualizar con doble clic, abre **LEEME CHRISTIAN.txt** en TextEdit. Evidencia y límites: **VERIFICACION.md**.

> Compilación binaria en GitHub Actions: lee **BUILD_GITHUB.md**. El repositorio y la identidad de publicación están autorizados; la entrega exige una ejecución verde y un ZIP descargado y verificado. El ZIP de fuentes no es una app. No se crea un Release público.

## Requisitos

| Qué | Detalle |
|---|---|
| Mac | Apple Silicon (tu Mac mini M4), macOS 14 o más reciente |
| Herramientas de Xcode | Con las *Command Line Tools* basta, pero tiene que ser Swift **6.0 o superior** (Xcode 16+). Se instalan con `xcode-select --install`. Comprueba con `swift --version`. |
| Internet | Para descargar FluidAudio al compilar y el modelo de voz (≈ 500 MB) la primera vez que se abre la app |
| `codex` (solo para el pulido) | `npm i -g @openai/codex` y luego `codex login` eligiendo **Sign in with ChatGPT** |

Si no quieres el pulido, no necesitas `codex`: apágalo en Ajustes y la app dicta igual.

## Compilar y abrir

En la Terminal, dentro de esta carpeta:

```bash
./scripts/build.sh     # compila y crea dist/Dilo.app (firma ad-hoc, para uso personal)
./scripts/run.sh       # abre la app
```

La primera compilación tarda unos minutos (descarga FluidAudio). Para dejarla instalada: `INSTALL=1 ./scripts/build.sh` instala en `~/Applications/Dilo.app`, sin sudo, guardando cualquier Dilo previa de este proyecto en una carpeta de respaldo y sin borrar Dictado. Antes de instalar, cierra la app desde su menú → Salir.

Si macOS bloquea un `.command` o `Dilo.app`, lee el aviso. Si solo indica **desarrollador no identificado** o que no puede verificar al desarrollador, y reconoces este paquete, puedes usar **Ajustes del Sistema → Privacidad y seguridad → Abrir igualmente**, si se ofrece para ese archivo. Ante una advertencia de **malware**, «dañará tu ordenador» o archivo dañado, **detente, no lo abras ni eludas el aviso**: guarda una captura y pide ayuda. No desactives las protecciones del sistema.

Si Terminal solicita acceso a **Descargas** o a la carpeta del paquete, permítelo solo si corresponde a la carpeta que estás usando. Si lo denegaste, revisa **Privacidad y seguridad → Archivos y carpetas → Terminal**, si aparece, y reabre el actualizador. No hace falta **Acceso total al disco**. Para otros fallos de lectura/ejecución, consulta **LEEME CHRISTIAN.txt** o pide ayuda.

## Primera vez: permisos

Al abrir por primera vez aparece la ventana de **Ajustes** y macOS pide el micrófono. La app necesita **tres permisos** (en *Ajustes del Sistema → Privacidad y seguridad*):

| Permiso | Para qué | Dónde |
|---|---|---|
| **Micrófono** | Grabar tu voz | Micrófono |
| **Accesibilidad** | Pegar el texto (envía ⌘V) | Accesibilidad |
| **Monitoreo de entrada** | Detectar la tecla de dictado en cualquier app | Monitoreo de entrada |

En la sección *Permisos* de Ajustes aparece **Conceder…** cuando la app detecta un permiso pendiente; solicita el permiso o abre su panel. Activa «Dilo» en cada lista (puede figurar como «Dictado»). La app consulta los estados y reintenta activar la tecla, pero no garantiza que baste sin cerrar y abrir. Si macOS lo solicita, sal de Dilo y abre solo la copia actual. El micrófono tachado indica que la tecla no está activa.

> **Ojo:** una compilación con firma ad hoc puede hacer que macOS deje de reconocer permisos anteriores o los pida de nuevo, aunque conservemos `local.dictado.DictadoMac`; no ocurre necesariamente en todos los casos. No se restablecen permisos automáticamente. Puedes usar una identidad de firma propia mediante `SIGN_IDENTITY="Nombre del certificado" ./scripts/build.sh`; este paquete no proporciona un certificado ni garantiza conservar TCC.

**Si figuran activos pero no funcionan:** sal de Dilo y de cualquier Dictado abierto. En **Privacidad y seguridad → Accesibilidad**, selecciona su entrada y quítala con **−**, si existe; **quitar una entrada de privacidad no elimina la app, ajustes ni archivos**. Añade con **+** la copia actual en **tu carpeta de usuario → Aplicaciones → Dilo** (`~/Applications/Dilo.app`) y actívala. Repite en **Monitoreo de entrada** si ofrece esos botones. En **Micrófono**, o sin **−/+**, desactiva y activa el permiso si es posible; vuelve a abrir Dilo y usa **Conceder…** si aparece. No elijas Dictado ni una copia de respaldo. Esto puede ayudar, pero **no garantiza resolver el fallo**: si persiste, guarda una captura y solicita diagnóstico sin borrar apps. Pasos completos: **LEEME CHRISTIAN.txt**.

## Elegir la tecla de dictado

Menú del micrófono (barra de menú) → **Ajustes…** → *Tecla de dictado* → **Cambiar…** y pulsa lo que quieras:

- **Un modificador solo** (Option derecha, Control derecha, Comando derecha, Mayús derecha, fn…): púlsalo y suéltalo sin tocar nada más. El valor inicial es **Option derecha**.
- **Una combinación**, por ejemplo ⌃⌥Espacio.
- **Una tecla F** (F5, F13…).
- *Esc* cancela. *Restablecer* vuelve a Option derecha.

Modo (también en Ajustes):

- **Mantener pulsada** (por defecto): mantén la tecla mientras hablas, suéltala para insertar.
- **Pulsar para empezar y pulsar para terminar**: una pulsación empieza, otra termina.

Notas: con un modificador solo, si pulsas otra tecla a la vez (p. ej. Option+E para escribir «é»), la grabación se descarta, así no interfiere con tu escritura normal. La tecla **fn/🌐** funciona solo si tu teclado la envía al sistema (en teclados no Apple muchas veces no llega).

## Cómo probar

1. Abre **Notas**, crea una nota y haz clic dentro para poner el cursor.
2. Espera a que el menú diga «Listo — mantén ⌥ Option derecha para dictar» (la primera vez el modelo se descarga y se prepara; el icono es una flecha de descarga hasta entonces).
3. Mantén **Option derecha**. Sonará un «tink» y aparecerá abajo un indicador rojo «Grabando…». Habla una frase en español, p. ej.: *«eh hola buenas tardes quería preguntar si mañana a las tres podemos vernos»*.
4. Suelta la tecla. Verás «Transcribiendo…», luego «Puliendo con ChatGPT…» y el texto aparece en la nota.
5. Pruebas útiles:
   - Apaga el pulido en el menú (*Pulir con ChatGPT*) y repite: debe salir el texto crudo de Parakeet.
   - En Ajustes pon la espera máxima en 3 s o una ruta de `codex` incorrecta: debe insertarse el texto sin pulir y aparecer un aviso breve.
   - Copia algo antes de dictar: tras el pegado, tu portapapeles debe volver a tener lo que habías copiado.

Para ver los registros de la app: `./scripts/run.sh --logs`.

## El pulido con ChatGPT (codex)

La app ejecuta, para cada dictado, algo equivalente a:

```
codex exec --skip-git-repo-check --ephemeral --ignore-user-config --sandbox read-only --color never \
           -o <archivo temporal> -C <carpeta vacía> -c model_reasoning_effort="low" -
```

con el prompt por entrada estándar (no en la lista de procesos). Detalles:

- Solo se envía el **texto** transcrito. Se ejecuta en una carpeta vacía y en modo solo lectura.
- Se eliminan `OPENAI_API_KEY` y `CODEX_API_KEY` del entorno. Si `codex` estuviera logueado con API key en vez de ChatGPT, la app **no pule** y te lo dice (haz `codex logout && codex login` y elige ChatGPT).
- Las opciones `--ephemeral` / `--ignore-user-config` / `--skip-git-repo-check` solo se usan si tu versión de `codex` las admite (se comprueba con `codex exec --help`).
- Si la respuesta es vacía, o su longitud es muy distinta a la del dictado (señal de que ChatGPT contestó o inventó en vez de corregir), se descarta y se usa el texto crudo.
- El estado de `codex` (no instalado / sin sesión / listo) se ve en el menú y en Ajustes. «Comprobar de nuevo» vuelve a mirar.
- Cada pulido consume cuota de tu plan de ChatGPT, compartida con el resto de tu uso.
- Ajustes permite fijar la ruta de `codex`, el modelo y el «esfuerzo de razonamiento» (bajo = más rápido). Si tu cuenta no admite ese valor, `codex` fallará y se insertará el texto crudo: cámbialo a «El predeterminado de codex».

## Privacidad

- El audio se graba en memoria, se transcribe localmente y se descarta. No se guarda en disco.
- El modelo de voz se descarga una vez de HuggingFace a `~/Library/Application Support/FluidAudio/Models/`.
- Con el pulido activo, el texto transcrito se envía a ChatGPT a través de `codex`. Con el pulido apagado no sale nada del Mac (salvo la descarga inicial del modelo).
- El portapapeles se usa solo un instante para pegar y se restaura (incluidas imágenes y otros formatos); el texto temporal se marca para que los gestores de portapapeles lo ignoren.

## Solución de problemas

| Síntoma | Qué hacer |
|---|---|
| `swift build` dice que la versión de herramientas no es compatible | Actualiza Xcode / Command Line Tools (necesitas Swift 6.0+): `softwareupdate` o `xcode-select --install`. |
| Falla al resolver paquetes | Hace falta internet (FluidAudio y un componente binario se descargan de GitHub). Reintenta. |
| Icono de micrófono tachado / la tecla no hace nada | Revisa Ajustes → *Permisos*. Si figuran activos pero fallan, sigue la reconcesión manual en **LEEME CHRISTIAN.txt**; puede no bastar. Si persiste, solicita diagnóstico sin borrar la app. |
| Al dictar dice «El modelo de voz aún no está listo» | Espera: se está descargando o preparando (la primera vez tarda). Si da error, «Reintentar» en Ajustes → General. |
| No se pega, el texto queda en el portapapeles | Falta el permiso de Accesibilidad. Pega con ⌘V. También ocurre en campos de contraseña o con «Secure Keyboard Entry» activo en la Terminal. |
| El pegado devuelve el portapapeles viejo demasiado pronto en alguna app | Algunas apps leen el portapapeles tarde. Sube `restoreDelay` en `Sources/DictadoMac/TextInserter.swift` (300 ms) y recompila. |
| «codex: no está instalado» pero sí lo tienes | Pon la ruta en Ajustes (`which codex` en la Terminal te la da). La app abre en un entorno sin tu PATH de Terminal; si `codex` viene de `nvm`, usa la ruta completa. |
| «codex: no has iniciado sesión» | En la Terminal: `codex login` → *Sign in with ChatGPT*. |
| El pulido tarda mucho | Esfuerzo de razonamiento «Bajo»; baja la espera máxima (p. ej. 8 s); prueba otro modelo en Ajustes. |
| Se pierden las primeras palabras | Empieza a hablar cuando suene el «tink»/aparezca el indicador rojo; abrir el micrófono tarda una fracción de segundo. |
| Option derecha no dicta pero escribe acentos | Estás pulsando otra tecla a la vez: la grabación se descarta a propósito. Elige otra tecla en Ajustes si te molesta. |
| El micrófono equivocado | Ajustes → Micrófono. |

## Qué no se ha probado

La app original fue probada por el usuario en su Mac, con el pulido ChatGPT apagado. Eso no valida este nuevo paquete. **La actualización Dilo no se ha compilado ni ejecutado en macOS**. En este entorno Linux no hay Swift; `scripts/selftest.sh` no puede ejecutarse aquí. Las verificaciones realmente ejecutadas, los resultados y las pruebas pendientes están en `VERIFICACION.md`. Lo que hay que comprobar en el Mac:

**Qué probar primero:** que compila; que el modelo se descarga y carga; que la tecla se detecta con los permisos; que el pegado funciona en Notas, el navegador y un editor; que `codex exec` con tu sesión devuelve el texto pulido; el comportamiento de respaldo (apagar wifi con el pulido activo); cambiar de tecla en Ajustes; elegir otro micrófono.

No incluido (a propósito, para mantenerlo sencillo): inserción directa por Accesibilidad (solo portapapeles + ⌘V), cancelar con Esc durante la grabación, vista previa de texto parcial, historial, vocabulario personalizado, otros idiomas.

## Estructura

```
Package.swift                  Swift Package (macOS 14+), depende de FluidAudio 0.17.7
Sources/DictadoMac/
  DictadoMacApp.swift          Punto de entrada
  AppDelegate.swift            Icono y menú de la barra, ventana de Ajustes, conecta todo
  DictationController.swift    Flujo: tecla → grabar → transcribir → pulir → insertar
  HotkeyBinding.swift          Qué es "la tecla" (modificador solo / tecla + modificadores) y su nombre
  HotkeyManager.swift          CGEventTap: detecta pulsar/soltar la tecla en todo el sistema
  ShortcutRecorderView.swift   Grabador de atajo para Ajustes
  AudioRecorder.swift          AVAudioEngine → 16 kHz, mono, Float32 en memoria
  AudioDevices.swift           Lista de micrófonos (Core Audio)
  ParakeetTranscriber.swift    FluidAudio / Parakeet v3, carga al arrancar, español
  PolishPrompt.swift           Prompt en español y validación de la respuesta
  TextPolisher.swift           Ejecuta `codex exec`; comprueba instalación y login; respaldo
  ProcessRunner.swift          Lanza procesos con tiempo máximo, sin shell
  TextInserter.swift           Portapapeles + ⌘V + restaurar portapapeles
  Permissions.swift            Micrófono, Accesibilidad, Monitoreo de entrada
  OverlayPanel.swift           Indicador flotante (grabando / transcribiendo / puliendo)
  AppSettings.swift            Ajustes en UserDefaults
  SettingsView.swift           Ventana de Ajustes (SwiftUI)
Resources/Info.plist           LSUIElement, descripción del micrófono
Resources/DictadoMac.entitlements
scripts/build.sh               Compila, monta Dilo.app y firma ad-hoc
scripts/run.sh                 Abre la app (--logs para ver registros)
scripts/selftest.sh            Pruebas de la lógica sin AppKit (también corren en Linux)
SelfTests/main.swift
```

## Licencias y agradecimientos

Código propio bajo licencia MIT (ver `LICENSE`). Usa FluidAudio (Apache-2.0) y el modelo Parakeet TDT 0.6B v3 de NVIDIA (CC-BY-4.0). Ver `THIRD_PARTY_NOTICES.md`.
