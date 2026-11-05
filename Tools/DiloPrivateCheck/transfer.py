#!/usr/bin/env python3
"""Transferencia de assets YA CIFRADOS con un borrador de release (visible solo con push).

Uso en el runner:
  transfer.py download <release_id> <dir> <etiquetas...>
  transfer.py upload   <release_id> <run_id> <dir>
Lee GH_TOKEN y GITHUB_REPOSITORY del entorno. Nunca imprime contenido: solo nombres y tamaños.
No sigue redirecciones con el token: la URL firmada de descarga se pide sin Authorization.
"""
import json
import os
from pathlib import Path
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.github.com"
UPLOADS = "https://uploads.github.com"
INPUT_UPLOADER = "soportetinvalu"
LABELS = {"ficticio", "real"}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


OPENER = urllib.request.build_opener(NoRedirect)


def call(method, url, data=None, headers=None, auth=True):
    values = {"User-Agent": "dilo-privado", "X-GitHub-Api-Version": "2022-11-28",
              "Accept": "application/vnd.github+json"}
    if auth:
        if urllib.parse.urlsplit(url).hostname not in {"api.github.com", "uploads.github.com"}:
            raise SystemExit("token solo para api/uploads.github.com")
        values["Authorization"] = "Bearer " + os.environ["GH_TOKEN"]
    values.update(headers or {})
    request = urllib.request.Request(url, data=data, method=method, headers=values)
    try:
        with OPENER.open(request, timeout=180) as response:
            return response.status, response.headers, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.headers, error.read()


def draft_assets(repo, release_id):
    status, _, body = call("GET", f"{API}/repos/{repo}/releases/{release_id}")
    if status != 200:
        raise SystemExit(f"borrador no accesible: HTTP {status}")
    if not json.loads(body).get("draft"):
        raise SystemExit("la release no es un borrador; se rechaza")
    status, _, body = call("GET", f"{API}/repos/{repo}/releases/{release_id}/assets?per_page=100")
    if status != 200:
        raise SystemExit(f"assets no accesibles: HTTP {status}")
    return json.loads(body)


def download(repo, release_id, directory, labels):
    if not labels or not set(labels) <= LABELS:
        raise SystemExit("etiquetas no admitidas")
    assets = {item["name"]: item for item in draft_assets(repo, release_id)}
    for label in labels:
        name = f"entrada-{label}.enc"
        asset = assets.get(name)
        if asset is None or asset["uploader"]["login"] != INPUT_UPLOADER or asset["state"] != "uploaded":
            raise SystemExit(f"falta {name} subido por el propietario")
        status, headers, body = call("GET", f"{API}/repos/{repo}/releases/assets/{asset['id']}",
                                     headers={"Accept": "application/octet-stream"})
        if status in (301, 302, 303, 307, 308):
            status, _, body = call("GET", headers["Location"], auth=False,
                                   headers={"Accept": "application/octet-stream"})
        if status != 200 or len(body) != asset["size"]:
            raise SystemExit(f"descarga de {name} fallida: HTTP {status}")
        target = Path(directory) / name
        with open(target, "xb") as handle:
            handle.write(body)
        os.chmod(target, 0o600)
        print(f"recibido {name}: {len(body)} bytes cifrados")


def upload(repo, release_id, run_id, directory):
    if not re.fullmatch(r"[0-9]{1,20}", run_id):
        raise SystemExit("run_id inválido")
    existing = {item["name"] for item in draft_assets(repo, release_id)}
    sent = 0
    for path in sorted(Path(directory).glob("*.enc")):
        match = re.fullmatch(r"(salida-(ficticio|real)|diag)\.enc", path.name)
        if not match:
            continue
        name = f"{match.group(1)}-{run_id}.enc"
        if name in existing:
            raise SystemExit(f"{name} ya existe; no se sobrescribe")
        data = path.read_bytes()
        query = urllib.parse.urlencode({"name": name})
        status, _, body = call("POST", f"{UPLOADS}/repos/{repo}/releases/{release_id}/assets?{query}",
                               data=data, headers={"Content-Type": "application/octet-stream"})
        if status != 201 or json.loads(body)["size"] != len(data):
            raise SystemExit(f"subida de {name} fallida: HTTP {status}")
        sent += 1
        print(f"devuelto {name}: {len(data)} bytes cifrados")
    print(f"assets devueltos: {sent}")


def main():
    repo = os.environ["GITHUB_REPOSITORY"]
    if len(sys.argv) >= 5 and sys.argv[1] == "download" and sys.argv[2].isdigit():
        download(repo, sys.argv[2], sys.argv[3], sys.argv[4:])
    elif len(sys.argv) == 5 and sys.argv[1] == "upload" and sys.argv[2].isdigit():
        upload(repo, sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
