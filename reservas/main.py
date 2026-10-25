"""S4 - Flight reservation service (port 5004). Consumes S3 over HTTP."""

import os

import httpx
from fastapi import Depends, FastAPI, status
from pydantic import BaseModel, Field

from shared.db import create_tables, session_factory
from shared.cors import enable_cors
from shared.errors import ApiError, errores, register_error_handlers
from shared.models import Base, Reserva, reserva_to_dict
from shared.security import current_user_email

engine, SessionLocal = session_factory("reservas")
create_tables(engine, Base, [Reserva.__table__])

FLIGHTS_URL = os.getenv("FLIGHTS_SERVICE_URL", "http://localhost:5003")

app = FastAPI(title="S4 - Flight reservation", version="1.0.0")
register_error_handlers(app)
enable_cors(app)


class ReservaIn(BaseModel):
    vueloId: int
    pasajero: str = Field(min_length=1, max_length=100)


class ReservaOut(BaseModel):
    id: int
    vueloId: int
    pasajero: str
    estado: str


def obtener_vuelo(vuelo_id: int) -> dict:
    """Internal call to S3 GET /api/vuelos/{id}."""
    try:
        response = httpx.get(f"{FLIGHTS_URL}/api/vuelos/{vuelo_id}", timeout=5)
    except httpx.HTTPError:
        raise ApiError(503, "SERVICIO_NO_DISPONIBLE", "El servicio de vuelos no está disponible.")
    if response.status_code == 404:
        raise ApiError(404, "VUELO_NO_EXISTE", "El vuelo no existe.")
    if response.status_code != 200:
        raise ApiError(503, "SERVICIO_NO_DISPONIBLE", "El servicio de vuelos no está disponible.")
    return response.json()


@app.post(
    "/api/reservas",
    status_code=status.HTTP_201_CREATED,
    response_model=ReservaOut,
    responses=errores(400, 401, 404, 409, 503),
    summary="Reservar un vuelo (requiere token Bearer)",
)
def crear_reserva(datos: ReservaIn, email: str = Depends(current_user_email)):
    vuelo = obtener_vuelo(datos.vueloId)
    if vuelo["asientosDisponibles"] <= 0:
        raise ApiError(409, "SIN_ASIENTOS", "El vuelo no tiene asientos disponibles.")
    with SessionLocal() as db:
        reserva = Reserva(
            usuario_email=email,
            vuelo_id=datos.vueloId,
            pasajero=datos.pasajero,
            estado="confirmada",
        )
        db.add(reserva)
        db.commit()
        db.refresh(reserva)
        return reserva_to_dict(reserva)
