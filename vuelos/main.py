"""S3 - Flight query service (port 5003)."""

from datetime import date

from fastapi import FastAPI
from pydantic import BaseModel

from shared.db import create_tables, session_factory
from shared.cors import enable_cors
from shared.errors import ApiError, errores, register_error_handlers
from shared.models import Base, Vuelo

engine, SessionLocal = session_factory("vuelos")
create_tables(engine, Base, [Vuelo.__table__])

SEED_FLIGHTS = [
    {"origen": "UIO", "destino": "GYE", "fecha": date(2026, 11, 10), "precio": 45.0, "asientos_disponibles": 30},
    {"origen": "UIO", "destino": "GYE", "fecha": date(2026, 11, 12), "precio": 52.5, "asientos_disponibles": 0},
    {"origen": "GYE", "destino": "UIO", "fecha": date(2026, 11, 15), "precio": 48.0, "asientos_disponibles": 12},
    {"origen": "UIO", "destino": "MAD", "fecha": date(2026, 12, 1), "precio": 780.0, "asientos_disponibles": 5},
]


def _seed() -> None:
    with SessionLocal() as db:
        if db.query(Vuelo).count() == 0:
            db.add_all(Vuelo(**flight) for flight in SEED_FLIGHTS)
            db.commit()


_seed()

app = FastAPI(title="S3 - Flight query", version="1.0.0")
register_error_handlers(app)
enable_cors(app)


class VueloOut(BaseModel):
    id: int
    origen: str
    destino: str
    fecha: date
    precio: float
    asientosDisponibles: int


def _to_dict(vuelo: Vuelo) -> dict:
    return {
        "id": vuelo.id,
        "origen": vuelo.origen,
        "destino": vuelo.destino,
        "fecha": vuelo.fecha.isoformat(),
        "precio": vuelo.precio,
        "asientosDisponibles": vuelo.asientos_disponibles,
    }


@app.get(
    "/api/vuelos",
    response_model=list[VueloOut],
    responses=errores(400),
    summary="Buscar vuelos por origen, destino y fecha",
)
def buscar_vuelos(origen: str | None = None, destino: str | None = None, fecha: date | None = None):
    with SessionLocal() as db:
        query = db.query(Vuelo)
        if origen:
            query = query.filter(Vuelo.origen == origen.upper())
        if destino:
            query = query.filter(Vuelo.destino == destino.upper())
        if fecha:
            query = query.filter(Vuelo.fecha == fecha)
        return [_to_dict(v) for v in query.order_by(Vuelo.id).all()]


@app.get(
    "/api/vuelos/{vuelo_id}",
    response_model=VueloOut,
    responses=errores(400, 404),
    summary="Detalle de un vuelo (uso interno de S4)",
)
def detalle_vuelo(vuelo_id: int):
    with SessionLocal() as db:
        vuelo = db.get(Vuelo, vuelo_id)
        if vuelo is None:
            raise ApiError(404, "VUELO_NO_EXISTE", "El vuelo no existe.")
        return _to_dict(vuelo)
