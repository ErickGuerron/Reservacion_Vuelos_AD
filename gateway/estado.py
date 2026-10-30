"""Enabled / disabled state of each service, shared by the console and the gateway.

The console writes runtime/estado.json (or GATEWAY_ESTADO); the gateway reads it on every
request, so a service can be switched off and on without restarting the gateway.
A missing file or a missing key means "enabled".
"""

import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLAVES_SERVICIOS = ("usuarios", "autenticacion", "vuelos", "reservas", "gestion")


def ruta_estado() -> Path:
    return Path(os.getenv("GATEWAY_ESTADO", ROOT / "runtime" / "estado.json"))


def leer_estado() -> dict[str, bool]:
    ruta = ruta_estado()
    if not ruta.exists():
        return {}
    try:
        datos = json.loads(ruta.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return {k: bool(v) for k, v in datos.items() if k in CLAVES_SERVICIOS}


def habilitado(clave: str) -> bool:
    return leer_estado().get(clave, True)


def fijar_habilitado(clave: str, valor: bool) -> None:
    if clave not in CLAVES_SERVICIOS:
        raise ValueError(f"Servicio desconocido: {clave}")
    estado = leer_estado()
    estado[clave] = valor
    ruta = ruta_estado()
    ruta.parent.mkdir(parents=True, exist_ok=True)
    temporal = ruta.with_suffix(".tmp")
    temporal.write_text(json.dumps(estado, indent=2), encoding="utf-8")
    os.replace(temporal, ruta)  # atomic on the same volume: readers never see a half-written file
