# Fixtures públicas de voz española

Tres primeras filas (0, 1, 2), sin selección por resultados, de `PolyAI/minds14`,
configuración `es-ES`, split `train`, revisión
`40ce77cb32a384e4d50a568e1ec39ac804019d33`.

Fuente y licencia CC-BY-4.0:
https://huggingface.co/datasets/PolyAI/minds14/blob/40ce77cb32a384e4d50a568e1ec39ac804019d33/README.md

Atribución: Daniela Gerz, Pei-Hao Su, Razvan Kusztos, Avishek Mondal, Michal Lis,
Eshan Singhal, Nikola Mrksic, Tsung-Hsien Wen e Ivan Vulic (PolyAI),
*Multilingual and Cross-Lingual Intent Detection from Spoken Data*, 2021.
https://arxiv.org/abs/2104.08524
Licencia: https://creativecommons.org/licenses/by/4.0/
Texto completo ya conservado en `Resources/licenses/CC-BY-4.0.txt`.

Los WAV públicos se obtuvieron del visor de Hugging Face de esa revisión y se
convirtieron con ffmpeg desde WAV mu-law a PCM16 mono, 16 kHz, sin recortes.
`spanish-public.json` conserva ruta original, fila, texto original sin correcciones,
hash de descarga, hash del WAV convertido, tamaño y duración. No son grabaciones
privadas ni voz sintetizada. No se modificaron referencias ruidosas del dataset.

La comparación usa exactamente las mismas muestras y parámetros ASR para ambos
encoders, sin pulido ni credenciales. WER ignora puntuación/caja, mantiene tildes.
Tres clips telefónicos no demuestran calidad general, redacción ni regresión en
la voz/micrófono de Christian. El informe conserva textos solo de estas fixtures
públicas. El helper no forma parte del ejecutable de la app ni cambia preferencias.
