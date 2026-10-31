# Compilación y entrega binaria mediante GitHub Actions

## Estado de publicación

Repositorio autorizado: https://github.com/soportetinvalu/dilo (público).
`origin` usa `https://github.com/soportetinvalu/dilo.git` sin credenciales.
La autorización anterior ya fue resuelta: `check` y `git-check --en-linea`
devuelven APTO y GitHub confirma `permissions.push=true` con el token del canal.
Christian aprobó expresamente la identidad local `Dilo <dictado@localhost>`.
Se conserva el trabajo anterior; la publicación y ejecución se verifican mediante
el mismo ejecutor. Hasta registrar una ejecución verde y descargar el artefacto,
no se afirma que exista un binario comprobado.
Página de Actions: https://github.com/soportetinvalu/dilo/actions

## Qué hace el workflow preparado

`.github/workflows/dilo-macos.yml` usa `macos-14` Apple Silicon y rechaza Intel.
La tabla oficial actual de GitHub identifica ese label como arm64:
https://docs.github.com/en/actions/reference/runners/github-hosted-runners
La compilación exige Swift 6, macOS 14+ y mantiene el identificador anterior.

1. Ejecuta pruebas Swift de lógica y pruebas Python de scripts/recursos.
2. Descarga Parakeet v3 desde una revisión inmutable y verifica tamaños y hashes.
   Son 21 archivos, 632174014 bytes. El lock vive en `Resources/parakeet-v3.lock.json`.
3. Compila app y comprobador, copia recursos SwiftPM, pesos y licencias y firma ad hoc.
   `Package.resolved` fija FluidAudio 0.17.7 al commit `503b4bd1bbf7220882de39fe8ae6716aae4132da`.
4. Audita Mach-O: acepta bibliotecas del sistema y las presentes dentro de la app;
   rechaza dependencias ausentes o rutas de Homebrew/build. Si aparecen dependencias
   dinámicas no empaquetadas, falla: no etiqueta ese resultado como app lista.
5. Carga los pesos de una copia independiente con `AsrModels.loadLocal`, sin caché
   de usuario ni resolución de red, y transcribe silencio. No es una prueba de voz real.
6. Empaqueta mediante `ditto`, extrae de nuevo y comprueba firma, pesos y dependencias.
7. Sube ZIP, SHA-256, guía y evidencia como artifact de Actions (retención 14 días).
   No crea Release, tag ni publicación adicional; permisos del workflow: `contents: read`.

Las acciones están fijadas por SHA. No se incluyen tokens, sesiones ni credenciales Apple.
Al ser público el repo, no deben incorporarse audio privado, credenciales ni datos personales
al commit/artefacto. Los pesos son públicos, con atribución y licencia CC-BY-4.0 incluidas.

## Qué incluye y qué no

El artefacto binario previsto contiene `Dilo.app` para arm64, modelo y recursos.
No necesita Swift/Xcode ni descargar pesos para dictar. El modelo del bundle se
carga localmente; si existe pero falla, se muestra el error sin descargar otro modelo.
La compilación ligera desde fuentes mantiene la descarga original al primer inicio.

El **pulido opcional** sigue requiriendo instalar `codex` y la sesión ChatGPT del usuario;
no se empaquetan codex ni una cuenta. El dictado crudo funciona sin ese componente.
La firma ad hoc **no es Developer ID ni notarización**. Gatekeeper puede bloquear
la descarga y TCC puede pedir nuevamente permisos; no se deshabilitan protecciones.
La guía `LEEME-DILO-APP.txt` explica el alcance y los avisos ante los que hay que detenerse.

## Operación de publicación y verificación

El inventario y las credenciales no se modifican desde esta tarea.
Se publica por `ejecutar-proyecto.py git-push`, nunca Git/API alternativos.
La ejecución del workflow podrá proceder por push o manualmente desde Actions.
Se debe comparar `headSha` con el commit publicado y exigir conclusión `success`,
descargar el artifact exacto y comprobar SHA-256 y contenidos antes de entregar la URL.

La prueba final de micrófono, TCC, tecla global, pegado, portapapeles y pulido requiere
el Mac del usuario. Un workflow verde no demuestra esos comportamientos.

## Evidencia local

En la entrega del canal, `github-build/` conserva respaldo de todos los archivos
anteriores, manifiesto de hashes, pesos descargados, salida de pruebas y bloqueo.
`dilo-v0.1.1-fuentes.zip` es **fuentes**, no una app. Incluye workflow, comprobador,
lock de modelo y licencias; no incluye los pesos de 632 MB ni ejecutables Mac.
