# Avisos de terceros

## Dependencias que se descargan al compilar

- **FluidAudio** — https://github.com/FluidInference/FluidAudio — licencia Apache-2.0.
  Se usa como dependencia de Swift Package (versión 0.17.7); no se copia su código a este repositorio.
  Incluye un componente binario (NemoTextProcessing) que SwiftPM descarga de GitHub.

## Modelo de voz

- **Parakeet TDT 0.6B v3** — © NVIDIA — licencia CC-BY-4.0.
  Original: https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3
  Conversión Core ML de FluidInference:
  https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml
  Los artefactos de CI redistribuyen los pesos Core ML sin modificarlos (revisión
  `7dd20fe6b1797d35f5e3307e8b1732d9a178edfe`). Dilo añade integración y empaquetado,
  sin implicar respaldo de NVIDIA o FluidInference. Licencia incluida en
  `Resources/licenses/CC-BY-4.0.txt`; tarjeta original del modelo incluida con los pesos.
  La compilación ligera de fuentes mantiene la descarga al primer arranque.
- **FluidAudio 0.17.7** y **NemoTextProcessing 0.3.1**: licencias de sus
  distribuciones incluidas en `Resources/licenses/` y copiadas al bundle de la app.

## Referencias de diseño

- **Dictate Anywhere** — https://github.com/hoomanaskari/mac-dictate-anywhere — licencia MIT,
  © 2026 Hooman Askari. Se consultó (CGEventTap para teclas globales, uso de FluidAudio,
  inserción por portapapeles) como referencia de enfoque. El código de este repositorio está
  escrito de nuevo; no se copió código fuente. Se deja el aviso por cortesía y por si en el futuro
  se incorpora código suyo (en ese caso hay que conservar su aviso de copyright y licencia MIT).
- **VoiceInk** (GPL-3.0): solo como referencia conceptual, **no se copió código**.
