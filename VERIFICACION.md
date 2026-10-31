# Dilo 0.1.1 — evidencia y límites de la entrega

## Resultado binario verificado

**Dilo.app compilada y empaquetada con su modelo local; ZIP descargado y comprobado.**
Primera ejecución correcta: https://github.com/soportetinvalu/dilo/actions/runs/41233915972
Commit: `fad9f83094e297552371c9d40868b0677518b946`.
Descarga: https://github.com/soportetinvalu/dilo/actions/runs/41233915972/artifacts/13055007488
(sesión GitHub; caduca el 14 de noviembre de 2026 a las 19:26:49 UTC).
ZIP interior: `Dilo-v0.1.1-macos-arm64.zip`, 566807622 bytes.
SHA-256: `47f93eabb15f5a3262f992e84dcd618290b9747b952a35c8831829627b2baafe`.
Cada run posterior genera otro ZIP y su checksum propio.

- Plataforma real: macOS 15.8.2, arm64, Xcode 16.4, Swift 6.1.2.
- Suite Swift de lógica correcta; Python: 23 casos, 22 ejecutados correctos y
  una guarda específica de Linux omitida en Mac. Linux: 23 correctos, sin omisiones.
- Compilación release de app y comprobador; firma ad hoc comprobada con codesign.
- Auditoría Mach-O: cero dependencias externas; recursos SwiftPM y licencias incluidos.
- Core ML cargó pesos locales e infirió 1 s de silencio desde copia separada con
  HOME vacío. No resuelve repositorios; no se afirma aislamiento de red del runner.
- El ZIP se extrajo de nuevo en Mac y se verificaron firma, dependencias y pesos.
- Descarga recibida: SHA-256 y CRC correctos; 21 archivos del modelo,
  632174014 bytes, hashes del lock exactos, Mach-O arm64 e icono original exacto.

Incidencias reales: run 41233169157 cancelado por brownout de macos-14;
41233286519 detectó guardas negativas que Bash 3.2 no rechazaba con `set -e`;
41233509229 detectó que el cargador buscaba Encoder.mlmodelc cuando se
empaquetaba Encoder_v2.mlmodelc. Corregidos con runner macos-15, rechazo
explícito y precisión int8V2 en app y comprobador; las pruebas siguen activas.

Límites: no hay Developer ID ni notarización. No se ha probado Gatekeeper de
una descarga, apertura gráfica, micrófono, TCC, tecla global, voz real, pegado,
portapapeles ni pulido con la sesión del usuario. El pulido sigue requiriendo
`codex` y su sesión propia. No se creó Release público.

---

## Registro histórico de preparación (anterior al binario)

Los apartados siguientes conservan la evidencia de las fases anteriores;
sus pendientes de compilación quedan resueltos por el resultado de arriba.

## Publicación y compilación en GitHub

El bloqueo anterior del ejecutor está resuelto: diagnóstico y comprobación en línea
APTO, permiso de escritura verificado para `https://github.com/soportetinvalu/dilo.git`.
La identidad de los commits nuevos, aprobada por Christian, es `Dilo <dictado@localhost>`.
Detalle operativo y alcance: `BUILD_GITHUB.md`.
Se conserva el trabajo previo en un respaldo íntegro y en el árbol local.
No se crea Release ni se cambia el inventario o las credenciales.
La preparación agrega cargador de pesos dentro del bundle, comprobador Core ML,
workflow arm64, empaquetado binario y auditoría de dependencias. Se mantiene la
carga original con descarga para compilaciones sin pesos. La única llamada nueva
al cargador y el target de comprobación son excepciones exactas en el test contra
la base; **no se modificaron los hashes base ni el resto del flujo de dictado**.

Ejecución local real: `python3 -m unittest discover -s Tests -p 'test_*.py' -v`:
**22 pruebas correctas, sin omisiones**. `actionlint 1.7.7`: salida vacía, código 0.
Se descargaron y verificaron 21 archivos reales del modelo (632174014 bytes),
revisión `7dd20fe6b1797d35f5e3307e8b1732d9a178edfe`; segunda verificación sin red.
`git diff --check`: código 0. Evidencia en `entregas/github-build/` del canal.

La compilación Mac debe verificarse con el run exacto. Estas comprobaciones Linux no
prueban Swift, Core ML, firma Apple, Gatekeeper, TCC, micrófono, tecla ni pegado.
`dilo-v0.1.1-fuentes.zip` sigue siendo fuentes, ahora con el workflow y las licencias.

---

## Registro histórico de la entrega de fuentes anterior

Lo que sigue documenta la etapa previa (18 pruebas, sin remoto y sin cargador
local de pesos); no sustituye el estado actualizado que aparece arriba.

## Resultado

Se prepara un **paquete de código fuente**, no un binario Mac ni un DMG.
El original fue probado por el usuario en un Mac con el pulido ChatGPT apagado;
**la actualización Dilo no está compilada ni probada en macOS**.

Base Git: `274904a1756ae31d69b6ff271660772cbf9e37a5`.
Rama local: `feat/dilo-nombre-icono`. Árbol original limpio; no había remoto.
No se han creado commits ni publicado repositorios, instalado infraestructura,
utilizado credenciales o modificado el cuaderno del canal.

## Cambios

- Nombre Finder/sistema: `Dilo`; bundle `dist/Dilo.app`; versión 0.1.1 (build 2).
- Nombre del menú Salir, ventana de Ajustes, ayuda de permisos y etiqueta accesible.
- `Resources/Dilo.icns` se referencia mediante `CFBundleIconFile` y se copia al
  bundle **antes de firmarlo**. No es una vista previa colocada en documentación.
- La imagen original está conservada byte por byte como `Dilo-original.png`:
  SHA-256 `859b57d5872d081706f3b2a44e444771b184f4533db59366d9f4777007ab23af`.
  Se mantiene cuadrada, con su fondo/márgenes originales, sin recortar ni rediseñar.
  Incluye diez representaciones estándar/Retina (16–1024 píxeles) y el iconset.
- Se conservan `local.dictado.DictadoMac`, ejecutable `DictadoMac`, claves de
  UserDefaults, entitlements, dependencias y rutas de modelos/configuración.
- No cambia la lógica de audio, atajos, transcripción, pulido ni pegado.
  Los cambios Swift son textos de marca y dos literales de ayuda de permisos;
  se verifica mediante hashes de los fuentes base, revirtiendo únicamente esas
  sustituciones conocidas. Los hashes base no se modifican.
- Se conserva el estado guardado de `polishEnabled`; no se escriben preferencias.
  La instalación nueva sin preferencias mantiene el valor inicial original (true),
  no alterado en este encargo. Christian debe comprobar que su ajuste siga apagado.
- Sigue siendo una app sin icono permanente en Dock (`LSUIElement = true`).
  El micrófono dinámico de la barra superior no se cambia: muestra el estado.

## Actualización segura propuesta

`Actualizar Dilo.command` pide confirmación y ejecuta compilación local +
instalación en `~/Applications/Dilo.app`, sin sudo. `Instalar herramientas.command`
solo solicita el instalador oficial de Apple si no hay herramientas; no actualiza
unas herramientas antiguas automáticamente.

La compilación se hace en una carpeta nueva. Se comprueban metadatos y firma
mediante `verify-app.sh`; solo después se publica el resultado. Si ya existe una
compilación en `dist/Dilo.app`, se guarda entera en `dist/Dilo-anterior.*/Dilo.app`.

La instalación prepara una copia con `ditto`, la verifica y exige que Dictado/Dilo
esté cerrada. No mata procesos. Guarda la Dilo anterior de este proyecto en
`~/Applications/Dilo-respaldo.*/Dilo.app`. No sustituye una aplicación Dilo con otro
identificador. Si falla el movimiento, intenta recuperar la anterior; si falla
la verificación final, aparta la nueva sin borrarla y recupera la anterior.
Lee el destino exacto y comprueba su firma antes de informar que está instalado.
Si la propia recuperación falla por un error de disco/permisos, conserva los
archivos y el error; no se puede garantizar recuperación frente a fallos de disco.

No borra apps ni archivos, no reinicia TCC, no quita quarantine, no modifica
preferencias/modelos ni ítems de inicio. `Dictado.app` original permanece intacta.
Conserva carpetas de preparación para diagnóstico. Las instrucciones explican
cómo abrir la copia anterior sin borrar nada y evitar dos instancias.

## Corrección focal de instrucciones Mac

- La guía completa está en `LEEME CHRISTIAN.txt` (TextEdit con doble clic).
  `LEEME CHRISTIAN.md` remite a ella para no mantener instrucciones duplicadas.
  Se alinean el inicio rápido, README, textos de Ajustes y mensaje del asistente.
- Si los permisos figuran activos pero fallan: cerrar Dilo y cualquier Dictado,
  quitar solo la entrada de privacidad si hay −, añadir la copia actual con + y
  activarla. En Micrófono o paneles sin esos botones, apagar/encender el permiso
  si es posible y volver a abrir para atender las solicitudes del sistema.
  Quitar la entrada no elimina la app ni ajustes. Se explica que puede no bastar.
- Solo el bloqueo por desarrollador no identificado/no verificable remite a
  Privacidad y seguridad → Abrir igualmente, si se ofrece y se reconoce el paquete.
  Ante malware, «dañará tu ordenador» o archivo dañado: detenerse y pedir ayuda,
  sin eludir el aviso ni desactivar protecciones.
- Se explica el permiso de Terminal para Descargas o la carpeta del paquete,
  si se solicita, sin recomendar Acceso total al disco.
- No se alteran icono, imagen original, dictado, solicitudes oficiales de permisos,
  ajustes ni instalación. No hay restablecimientos automáticos ni garantías TCC.

## Comprobaciones ejecutadas en Linux

Comando: `PYTHONDONTWRITEBYTECODE=1 python3 Tests/test_delivery.py`.
**Resultado tras la corrección focal: 18 pruebas, todas correctas, sin omisiones**.
Registro: `dilo-v0.1.1-validacion-instrucciones-linux.txt`, junto al ZIP.
Se conservan las 14 pruebas previas y se añaden cuatro de instrucciones.

- XML/plist válido, nombres Dilo, misma identidad/ejecutable y app de menú.
- Decodificación ICNS con Pillow; diez representaciones; PNG completos; tamaños
  y píxeles idénticos a la reducción Lanczos del original. SHA-256 original exacto.
- Código funcional conservado contra la base de hashes, incluidos ajustes,
  permisos, dictado, atajos, audio, pulido, pegado y autopruebas Swift originales.
- Guía .txt enlazada y prevista en el paquete, pasos manuales y ausencia de
  promesas de resolución; condiciones de Gatekeeper y acceso a carpeta.
  Contraprueba en memoria: quitar la advertencia de detenerse ante malware o la
  condición de apertura hace fallar la comprobación. Esto valida textos, no TCC.
- Sintaxis `bash -n` y bits ejecutables de los scripts y asistentes.
- Guardas reales: build/instalador/verificador/asistentes rechazan Linux.
- Scripts ejecutados en rutas con espacios con **dobles explícitos de herramientas
  Apple**: empaquetado con icono y recurso de dependencia, preservación de build,
  primera instalación y actualización con copia de seguridad; preferencias con
  pulido apagado y Dictado original intactas.
- Negativos: identificador/icono incorrectos, icono ausente, app ajena en destino,
  app ejecutándose; fallos de compilación, firma, copia y movimiento; fallo de
  verificación final con recuperación; Swift antiguo, arquitectura no compatible
  y macOS anterior a 14. Todos rechazados sin alterar la instalación anterior.
- `git diff --check`: código 0.

Estas pruebas con dobles validan el flujo de archivos y las ramas shell;
**NO prueban codesign, PlistBuddy, Swift, ditto ni otros componentes reales de Apple**.
Los ejecutables usados por los dobles son marcadores de prueba y no se entregan
como aplicación. No se contactó con FluidAudio, Apple ni un Mac.

Incidencias de la sonda: en la primera ejecución, el escaneo de comandos detectó
la palabra `sudo` en un comentario («sin sudo»). Se excluyeron comentarios; no era
un fallo de la app. Se corrigió también un aviso de archivo ICNS no cerrado en la
prueba. La siguiente ejecución pasó todas las pruebas.

`./scripts/selftest.sh`: **no pudo ejecutarse**, código 127,
`swiftc: command not found`. No hay `swift` ni `swiftc` disponibles en este Linux.
No se atribuye un resultado verde a la suite Swift ni se instala infraestructura
para sustituir una compilación macOS real.

## Verificación de la entrega

`scripts/package-source.py` genera el ZIP desde una lista permitida de código y
recursos, excluye `.git`, `dist`, cachés, entornos y credenciales. Verifica CRC de
ZIP, hashes y bytes de cada entrada, presencia de los asistentes y sus bits
Unix ejecutables. Incluye `Dilo/CONTENIDO-SHA256.json` y escribe el SHA-256 del ZIP
junto al archivo. El resultado de su ejecución acompaña a la entrega en
`dilo-v0.1.1-empaquetado.json`.

## Pendiente, solo verificable en un Mac

1. Compilar de verdad con Swift 6+ y resolver FluidAudio 0.17.7 en macOS 14+/arm64.
2. Comprobar que el bundle firmado se abre y que Finder/sistema muestran Dilo y
   la imagen. El ICNS válido en Linux no garantiza que se refresque la caché del Mac.
3. Verificar el flujo de doble clic, avisos Gatekeeper, firma real y posibles
   bloqueos de ejecución de `.command` tras descargar/descomprimir; solicitudes
   de acceso de Terminal a Descargas/carpeta y lectura de la guía .txt en TextEdit.
4. Comprobar que siguen la tecla, micrófono, modo y pulido desactivado de Christian.
5. Conceder/revalidar Micrófono, Accesibilidad y Monitoreo de entrada si se solicitan.
   La firma ad hoc cambia la identidad de código: mantener el bundle ID no garantiza
   que TCC conserve los permisos. No se diagnostica un bucle sin evidencia del Mac.
   La reconcesión manual descrita puede ayudar, pero no garantiza resolverlo.
6. Dictar en Notas, navegador y editor; confirmar inserción y restauración del
   portapapeles, estados de la barra de menú y comportamiento del modelo local.
7. Probar el retorno a la app anterior si hiciera falta; revisar ítems de inicio
   manualmente para que no se abran ambas copias.

No hay certificado Developer ID ni notarización. No se afirma que esta actualización
funcione ya en el Mac de Christian hasta completar esas comprobaciones allí.
