"""The processes the console manages: the gateway and the five services."""

from dataclasses import dataclass


@dataclass(frozen=True)
class Servicio:
    clave: str
    codigo: str
    nombre: str
    modulo: str  # ASGI app passed to uvicorn
    puerto: int
    desactivable: bool = True


SERVICIOS = [
    Servicio("gateway", "GW", "API Gateway", "gateway.main:app", 8000, desactivable=False),
    Servicio("usuarios", "S1", "Usuarios", "usuarios.main:app", 5001),
    Servicio("autenticacion", "S2", "Autenticación", "autenticacion.main:app", 5002),
    Servicio("vuelos", "S3", "Vuelos", "vuelos.main:app", 5003),
    Servicio("reservas", "S4", "Reservas", "reservas.main:app", 5004),
    Servicio("gestion", "S5", "Gestión de reservas", "gestion.main:app", 5005),
    Servicio("aviones", "S6", "Aviones", "aviones.main:app", 5006),
]


def buscar(clave: str) -> Servicio:
    for servicio in SERVICIOS:
        if servicio.clave == clave:
            return servicio
    raise KeyError(clave)
