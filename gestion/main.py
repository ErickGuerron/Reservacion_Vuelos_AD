"""S5 - Reservation management service (port 5005): list and cancel own reservations.

Cancelling releases the reservation's seat in S3 before the reservation is marked as cancelled.
"""

import os

import httpx
from fastapi import Depends, FastAPI
from pydantic import BaseModel

from shared.db import create_tables, session_factory
from shared.cors import enable_cors
from shared.errors import ApiError, errores, register_error_handlers
from shared.models import Base, Reserva, ReservaAsiento, reserva_to_dict
from shared.security import current_cliente_email

engine, SessionLocal = session_factory("reservas")
create_tables(engine, Base, [Reserva.__table__, ReservaAsiento.__table__])

FLIGHTS_URL = os.getenv("FLIGHTS_SERVICE_URL", "http://localhost:5003")

app = FastAPI(title="S5 - Reservation management", version="1.1.0")
register_error_handlers(app)
enable_cors(app)


class ReservaOut(BaseModel):
    id: int
    vueloId: int
    pasajero: str
    estado: str
    asiento: str | None = None


class CancelacionOut(BaseModel):
    id: int
    estado: str


def liberar_asientos(reserva_id: int) -> None:
    """Internal call to S3 POST /api/internal/reservas/{id}/liberar."""
    try:
        response = httpx.post(f"{FLIGHTS_URL}/api/internal/reservas/{reserva_id}/liberar", timeout=5)
    except httpx.HTTPError:
        raise ApiError(503, "SERVICIO_NO_DISPONIBLE", "El servicio de vuelos no está disponible.")
    if response.status_code != 200:
        raise ApiError(503, "SERVICIO_NO_DISPONIBLE", "El servicio de vuelos no está disponible.")


@app.get(
    "/api/reservas",
    response_model=list[ReservaOut],
    responses=errores(401),
    summary="Listar las reservas del usuario autenticado",
)
def listar_reservas(email: str = Depends(current_cliente_email)):
    with SessionLocal() as db:
        reservas = (
            db.query(Reserva, ReservaAsiento.asiento)
            .outerjoin(ReservaAsiento, ReservaAsiento.reserva_id == Reserva.id)
            .filter(Reserva.usuario_email == email)
            .order_by(Reserva.id)
            .all()
        )
        return [{**reserva_to_dict(r), "asiento": asiento} for r, asiento in reservas]


@app.delete(
    "/api/reservas/{reserva_id}",
    response_model=CancelacionOut,
    responses=errores(400, 401, 404, 409, 503),
    summary="Cancelar una reserva propia y liberar su asiento",
)
def cancelar_reserva(reserva_id: int, email: str = Depends(current_cliente_email)):
    with SessionLocal() as db:
        reserva = (
            db.query(Reserva)
            .filter(Reserva.id == reserva_id, Reserva.usuario_email == email)
            .first()
        )
        if reserva is None:
            raise ApiError(404, "RESERVA_NO_EXISTE", "La reserva no existe.")
        if reserva.estado == "cancelada":
            raise ApiError(409, "RESERVA_YA_CANCELADA", "La reserva ya está cancelada.")
        liberar_asientos(reserva.id)
        reserva.estado = "cancelada"
        db.commit()
        return {"id": reserva.id, "estado": reserva.estado}
