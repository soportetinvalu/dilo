# Último antes y después — build 4

## Camino mínimo comprobado en la base

En `9f79cf1e2cf937e4931763944ad39fa9969184e9`, `DictationController.process`
solo conservaba `raw` y `finalText` como variables locales. Menú y Ajustes no
ofrecían ambos; apagar pulido exige otro dictado, que no compara la misma captura.
Los logs no ofrecen esta comparación y no son el camino de diagnóstico.
No se puede reconstruir el incidente anterior: no se conservaron audio ni raw.

## Prueba manual privada (una sola grabación)

1. Con build 4, dicta una vez y espera a que termine la inserción.
2. Menú de Dilo → **Ver último antes y después…**. No se abre automáticamente.
3. Compara **Antes de ChatGPT (transcripción local)** con **Después de ChatGPT
   (texto usado)**. Son los textos de esa misma ejecución; abrir la ventana no
   vuelve a grabar, transcribir ni enviar una petición.
4. Si pulido estaba apagado o no se aceptó una respuesta, se muestra **Texto usado
   (sin pulir)** con el estado correspondiente, no un supuesto resultado de ChatGPT.
5. Cierra la ventana: se elimina el resultado y se deshabilita la acción hasta
   otro dictado. Iniciar otro intento borra el anterior y cierra la vista, incluso
   si falla por modelo, permisos, interrupción, brevedad, error o texto vacío.
   Salir de Dilo también elimina la referencia retenida.

Solo se conserva un resultado; no hay historial, exportación ni copia automática.
La vista no permite selección/copia ni solicita permisos. El campo «texto usado»
es el pasado al insertador, no una lectura de lo que recibió otra aplicación.
Si el cambio ya está en «Antes», apareció antes del pulido; si solo aparece en
«Después», apareció en el pulido. Esto no atribuye una causa al reconocimiento ni
acredita mejora de su precisión. Una respuesta idéntica también se identifica
como pulido completado, no como pulido apagado.

## Privacidad y alcance de la afirmación

El nuevo diagnóstico solo retiene dos `String` y un estado en RAM, sin audio,
archivos, preferencias, logs, errores del CLI ni nuevas emisiones de red. Su
ventana no es restaurable y se suelta también su vista al cerrar. Borrar significa
soltar referencias, no sobrescritura criptográfica de RAM ni garantía frente a
swap, volcados del sistema o capturas que haga el usuario.

**No se cambió el pulidor existente:** con pulido activo, ya enviaba texto por
stdin a Codex y usaba `-o` con un archivo temporal que intenta borrar al terminar.
La nueva vista no añade archivos ni cambia las opciones/cachés del CLI. No es una
garantía de cero escrituras del sistema o de Codex, ni elimina el consumo habitual
de cuota cuando el usuario dicta con pulido. No se ha hecho login ni una petición
real de ChatGPT para estas pruebas.

Se conservan íntegros ASR/modelo/prompt/pulidor/insertador/permisos/identidad del
bundle y ajustes. Los cambios del controlador son inserciones exactas documentadas
en `comparison-sources.json`; retirarlas recupera la base histórica verificada.

## Evidencia automatizada

- `python3 -m unittest discover -s Tests -p 'test_*.py' -v`: invariantes de base,
  identidad build 4, alcance de las fuentes, menú optativo y conexión de las pruebas.
- `scripts/selftest.sh` en macOS: compila **el controlador, almacén y ventana de
  producción** contra dobles de grabación, ASR, pulido, pegado y permisos.
  Comprueba raw/final distintos, una llamada por paso, captura tras inserción,
  apertura explícita, cierre/borrado, reemplazo y fallos, apagado/fallback,
  preservación del portapapeles real y ausencia de persistencia del diagnóstico.
- Cuatro mutantes compilables en copias temporales: raw sustituido por final,
  borrado omitido al empezar, borrado omitido al cerrar y fallback falsamente
  completado. Cada uno debe fallar por su aserción funcional concreta.
- Solo fixtures sintéticas en el arnés; sus textos no se imprimen. HOME/TMPDIR y
  Codex están aislados. No se usan dictados ni audio del usuario en Actions.
- CI existente: compila app arm64, firma ad hoc, verifica modelo y dependencias,
  ejecuta inferencia Core ML, empaqueta y verifica de nuevo el ZIP extraído.

**Límites:** las pruebas con dobles no acreditan micrófono, TCC, precisión de voz,
ChatGPT real, pegado efectivo ni layout/OCR en todos los tamaños del Mac del
usuario. La ventana nativa se ejercita en CI, pero no se afirma una aceptación
visual por capturas/OCR. La firma ad hoc no es Developer ID ni notarización.
La app debe probarse en el Mac del usuario; no se instala ni se restablecen permisos.
