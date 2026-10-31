# Pruebas de la entrega Dilo

En Linux: `PYTHONDONTWRITEBYTECODE=1 python3 Tests/test_delivery.py`.
Requiere Python 3 y Pillow; no son requisitos del actualizador en el Mac.

- Decodifica el ICNS y cada PNG, valida tamaños Retina y compara los píxeles
  con la reducción Lanczos del original; verifica el SHA-256 original.
- Valida nombre e identidad, y compara los fuentes con la base indicada en
  `dictation-baseline.json`, permitiendo solo los cambios de marca explícitos.
  Esto acredita conservación de código, NO funcionamiento de dictado.
- Permite únicamente los dos literales nuevos de ayuda en SettingsView, sin
  cambiar los hashes base ni excluir bloques de lógica. Comprueba la guía .txt,
  sus enlaces y su inclusión en el empaquetador; reconcesión manual sin garantía,
  separación entre desarrollador no identificado y malware, y acceso a carpeta.
  Una contraprueba en memoria quita el aviso de detenerse o la condición de
  apertura: la comprobación debe rechazar esas variantes. Son pruebas de textos,
  no de los diálogos ni permisos reales de macOS.
- Ejecuta `bash -n`, comprueba permisos ejecutables y las guardas Linux reales.
- Ejecuta los scripts de build/instalación sobre carpetas con espacios y
  herramientas Apple sustituidas explícitamente por dobles. Comprueba
  conservación de Dictado, preferencias con pulido desactivado, respaldos,
  rechazo de apps ajenas, fallos de copia/firma/compilación/movimiento, validación
  final y recuperación. Los binarios de esas pruebas son marcadores ficticios
  dentro de carpetas temporales propias: NO son entregables ni una app compilada.
- Casos negativos: nombre/identificador de icono incorrecto, icono ausente,
  app en ejecución, Swift antiguo, CPU no compatible y macOS anterior a 14.

Los fixtures se crean y retiran dentro de `Tests/.dilo-test-*`, no en las carpetas
reales del usuario. No hay red ni credenciales. No prueba las API de Apple,
LaunchServices, TCC, firma real, compilación Swift o integración FluidAudio.

En macOS, el propio build usa `scripts/verify-app.sh` antes de publicar el bundle;
la instalación lo repite en la copia preparada y en el destino exacto. Hace falta
probar el dictado y los permisos a mano. La suite original independiente de
AppKit sigue en `scripts/selftest.sh` y requiere `swiftc`.
