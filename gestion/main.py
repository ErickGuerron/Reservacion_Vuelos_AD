"""S5 - Reservation management service (port 5005): list and cancel own reservations."""

from fastapi import Depends, FastAPI
from pydantic import BaseModel

from shared.db import create_tables, session_factory
from shared.cors import enable_cors
from shared.errors import ApiError, errores, register_error_handlers
from shared.models import Base, Reserva, reserva_to_dict
from shared.security import current_user_email

engine, SessionLocal = session_factory("reservas")
create_tables(engine, Base, [Reserva.__table__])

app = FastAPI(title="S5 - Reservation management", version="1.0.0")
register_error_handlers(app)
enable_cors(app)


class ReservaOut(BaseModel):
    id: int
    vueloId: int
    pasajero: str
    estado: str


class CancelacionOut(BaseModel):
    id: int
    estado: str


@app.get(
    "/api/reservas",
    response_model=list[ReservaOut],
    responses=errores(401),
    summary="Listar las reservas del usuario autenticado",
)
def listar_reservas(email: str = Depends(current_user_email)):
    with SessionLocal() as db:
        reservas = db.query(Reserva).filter(Reserva.usuario_email == email).order_by(Reserva.id).all()
        return [reserva_to_dict(r) for r in reservas]


@app.delete(
    "/api/reservas/{reserva_id}",
    response_model=CancelacionOut,
    responses=errores(400, 401, 404, 409),
    summary="Cancelar una reserva propia",
)
def cancelar_reserva(reserva_id: int, email: str = Depends(current_user_email)):
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
        reserva.estado = "cancelada"
        db.commit()
        return {"id": reserva.id, "estado": reserva.estado}
