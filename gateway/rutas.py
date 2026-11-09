"""Public routing table of the gateway. First matching rule wins.

Paths are matched by whole segments: "/api/reservas" matches "/api/reservas/5" but not
"/api/reservasx". Some paths split by HTTP method: POST /api/reservas creates a booking
(S4), while GET and DELETE manage bookings (S5).

Internal endpoints (/api/internal/...) are never routed: the gateway answers 404 for them.
"""

import re

PUERTOS = {
    "usuarios": 5001,
    "autenticacion": 5002,
    "vuelos": 5003,
    "reservas": 5004,
    "gestion": 5005,
    "aviones": 5006,
}

# (prefix, service, methods or None for all methods)
REGLAS = [
    ("/api/usuarios", "usuarios", None),
    ("/api/admin/usuarios", "usuarios", None),
    ("/api/auth", "autenticacion", None),
    ("/api/vuelos", "vuelos", None),
    ("/api/admin/vuelos", "vuelos", None),
    ("/api/admin/aviones", "aviones", None),
    ("/api/reservas", "reservas", {"POST"}),
    ("/api/reservas", "gestion", {"GET", "DELETE"}),
]

# PUT solo para cambiar el asiento de una reserva propia: /api/reservas/{id}/asiento (S4).
CAMBIO_ASIENTO = re.compile(r"^/api/reservas/\d+/asiento$")


def _coincide(path: str, prefijo: str) -> bool:
    return path == prefijo or path.startswith(prefijo + "/")


def resolver(path: str, method: str) -> str | None:
    """Return the service that owns this request, or None when it must not be routed."""
    if path == "/api/internal" or path.startswith("/api/internal/"):
        return None
    if method.upper() == "PUT" and CAMBIO_ASIENTO.match(path):
        return "reservas"
    for prefijo, servicio, metodos in REGLAS:
        if _coincide(path, prefijo) and (metodos is None or method.upper() in metodos):
            return servicio
    return None
