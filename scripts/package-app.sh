#!/usr/bin/env bash
# Empaqueta exclusivamente una app Mac ya compilada y con el modelo completo.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo "El empaquetado de app requiere macOS." >&2; exit 1; }
APP="$PWD/dist/Dilo.app"
ZIP="$PWD/dist/Dilo-v0.1.1-macos-arm64.zip"
[[ ! -e "$ZIP" ]] || { echo "Ya existe el ZIP; no se sobrescribe." >&2; exit 1; }
./scripts/verify-app.sh "$APP"
python3 scripts/verify-runtime.py "$APP"
python3 scripts/download-model.py "$APP/Contents/Resources/ParakeetV3" --verify-only
[[ "$(lipo -archs "$APP/Contents/MacOS/DictadoMac")" == arm64 ]]
cp LEEME-DILO-APP.txt dist/
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
ROUNDTRIP="$(mktemp -d "$PWD/dist/.dilo-roundtrip.XXXXXX")"
ditto -x -k "$ZIP" "$ROUNDTRIP"
./scripts/verify-app.sh "$ROUNDTRIP/Dilo.app"
python3 scripts/verify-runtime.py "$ROUNDTRIP/Dilo.app"
python3 scripts/download-model.py "$ROUNDTRIP/Dilo.app/Contents/Resources/ParakeetV3" --verify-only
(cd dist && shasum -a 256 Dilo-v0.1.1-macos-arm64.zip > Dilo-v0.1.1-macos-arm64.zip.sha256)
python3 -c 'import json,os,subprocess; from pathlib import Path; d={"commit":subprocess.check_output(["git","rev-parse","HEAD"],text=True).strip(),"run_url":"https://github.com/"+os.environ.get("GITHUB_REPOSITORY","")+"/actions/runs/"+os.environ.get("GITHUB_RUN_ID",""),"signature":"ad hoc; not notarized","bundled_model":True,"microphone_tcc_paste_tested":False}; Path("dist/evidence/build.json").write_text(json.dumps(d,indent=2)+"\n")'
echo "ZIP, firma, arquitectura, dependencias y pesos verificados tras extracción: $ZIP"
