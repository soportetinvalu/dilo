#!/usr/bin/env bash
# Abrir con doble clic en Finder. Compila localmente; no descarga ni ejecuta instaladores externos.
set -euo pipefail
cd "$(dirname "$0")"
finish() {
  result=$?
  if [[ "$result" != 0 ]]; then
    echo
    echo "La actualización no se completó. Conserva esta ventana o una captura del error."
    echo "No se han borrado tu app anterior, ajustes ni modelos."
  fi
  echo
  read -r -p "Pulsa Intro para cerrar esta ventana… " _ || true
}
trap finish EXIT
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Este actualizador se abre en el Mac de Christian, no en Linux." >&2
  exit 1
fi
osascript -e 'display dialog "Se compilará Dilo en tu Mac y se instalará en la carpeta Aplicaciones de tu usuario. Necesita internet y herramientas de Xcode (Swift 6+). No borra Dictado, tus preferencias ni el modelo de voz. Antes de continuar, cierra Dictado o Dilo desde su menú → Salir. Puede tardar varios minutos y macOS puede pedir permisos de nuevo." with title "Actualizar a Dilo" buttons {"Cancelar", "Continuar"} default button "Continuar" cancel button "Cancelar"'
INSTALL=1 ./scripts/build.sh
./scripts/verify-app.sh "$HOME/Applications/Dilo.app"
open "$HOME/Applications/Dilo.app"
echo
echo "Dilo está en $HOME/Applications/Dilo.app. Busca el micrófono en la barra superior."
echo "En Ajustes comprueba que Pulir con ChatGPT sigue apagado, como lo tenías."
echo "Revisa Micrófono, Accesibilidad y Monitoreo de entrada en Ajustes del Sistema → Privacidad y seguridad."
echo "Si figuran activos pero no funcionan, consulta LEEME CHRISTIAN.txt; no se restablecen automáticamente."
