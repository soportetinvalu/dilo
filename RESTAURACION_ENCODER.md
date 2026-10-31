# Restauración del encoder original

Se restaura explícitamente `Encoder.mlmodelc` / `.int8`, selección predeterminada
que usaba `AsrModels.downloadAndLoad(version: .v3)` en la primera versión `274904a`.
FluidAudio permanece en 0.17.7, commit `503b4bd1bbf7220882de39fe8ae6716aae4132da`.
No se conocen los hashes de la caché descargada en el Mac durante aquella prueba:
restaurar variante no prueba identidad binaria con esa caché ni calidad equivalente.

El lock de entrega mantiene la revisión de pesos
`7dd20fe6b1797d35f5e3307e8b1732d9a178edfe`, con 22 archivos y 483109930 bytes.
Se reemplazan solo los archivos del encoder; no se renombran pesos v2. Descarga,
carga local, fallback de fuentes y comprobador seleccionan ahora el mismo encoder.
El verificador rechaza componentes Core ML sobrantes (incluido v2), sin borrarlos.
El bundle no incluye el encoder v2; se descarga aparte solo para comparar en CI.

No se tocan identificador, preferencias, privacidad, micrófono, pulido ni pegado.
El pulido sigue usando su ajuste guardado y puede fallar y entregar texto crudo;
no se ha demostrado que eso ocurriera en la sesión reportada. No se registran
nuevos textos, audio ni mensajes privados. No se cambia el valor inicial existente.

CI construye en macOS arm64, comprueba firma ad hoc, dependencias y recursos,
prueba carga local/silencio y compara tres grabaciones españolas públicas MInDS-14
con ambos encoders. Las referencias se conservan sin corregir; la comparación
mide WER normalizado, no calidad de redacción ni el pulido. Ver `Tests/Fixtures`.
La guarda amplia WER <= 0.65 comprueba reconocimiento no vacío; no exige ni presume
que el encoder original sea superior. El resultado real se adjunta al artefacto
como `evidence/spanish-comparison.json`, junto con los logs y `build.json`.

Las cifras/enlaces anteriores de `VERIFICACION.md` y `BUILD_GITHUB.md` describen
el artefacto histórico v2, no este. Cada compilación tiene su hash propio.
No hay Developer ID/notarización; falta validación con voz y permisos del usuario.
