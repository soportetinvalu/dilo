# Avisos de terceros

## Dependencias que se descargan al compilar

- **FluidAudio** — https://github.com/FluidInference/FluidAudio — licencia Apache-2.0.
  Se usa como dependencia de Swift Package (versión 0.17.7); no se copia su código a este repositorio.
  Incluye un componente binario (NemoTextProcessing) que SwiftPM descarga de GitHub.

## Modelo de voz (se descarga al primer arranque, no está en el repositorio)

- **Parakeet TDT 0.6B v3** — NVIDIA — licencia CC-BY-4.0 (se exige atribución).
  Versión Core ML publicada por FluidInference: `FluidInference/parakeet-tdt-0.6b-v3-coreml` en HuggingFace.
  Revisa la licencia del modelo descargado si algún día distribuyes la app a terceros.

## Referencias de diseño

- **Dictate Anywhere** — https://github.com/hoomanaskari/mac-dictate-anywhere — licencia MIT,
  © 2026 Hooman Askari. Se consultó (CGEventTap para teclas globales, uso de FluidAudio,
  inserción por portapapeles) como referencia de enfoque. El código de este repositorio está
  escrito de nuevo; no se copió código fuente. Se deja el aviso por cortesía y por si en el futuro
  se incorpora código suyo (en ese caso hay que conservar su aviso de copyright y licencia MIT).
- **VoiceInk** (GPL-3.0): solo como referencia conceptual, **no se copió código**.
