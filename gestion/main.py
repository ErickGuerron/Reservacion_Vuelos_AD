"""S5 - Reservation management service (port 5005): list and cancel own reservations.

Cancelling releases the reservation's seat in S3 before the reservation is marked as cancelled.
"""

import logging
import os
from datetime import date

import httpx
from fastapi import Depends, FastAPI, Response
from pydantic import BaseModel, Field
from sqlalchemy.exc import SQLAlchemyError

from shared.db import add_column_if_missing, create_tables, session_factory
from shared.cors import enable_cors
from shared.errors import ApiError, errores, register_error_handlers
from shared.factura import construir_factura_xml
from shared.models import (
    RESERVA_DOCUMENTO_DDL,
    RESERVA_LOTE_DDL,
    RESERVA_PRECIO_DDL,
    RESERVA_TIPO_DOCUMENTO_DDL,
    Base,
    Reserva,
    ReservaAsiento,
    reserva_to_dict,
)
from shared.security import Cuenta, current_cliente_cuenta, current_cliente_email

engine, SessionLocal = session_factory("reservas")
create_tables(engine, Base, [Reserva.__table__, ReservaAsiento.__table__])
add_column_if_missing(engine, "reservas", "lote_id", RESERVA_LOTE_DDL)
add_column_if_missing(engine, "reservas", "precio", RESERVA_PRECIO_DDL)
add_column_if_missing(engine, "reservas", "tipo_documento", RESERVA_TIPO_DOCUMENTO_DDL)
add_column_if_missing(engine, "reservas", "documento", RESERVA_DOCUMENTO_DDL)

FLIGHTS_URL = os.getenv("FLIGHTS_SERVICE_URL", "http://localhost:5003")
log = logging.getLogger("gestion")

app = FastAPI(title="S5 - Reservation management", version="1.1.0")
register_error_handlers(app)
enable_cors(app)


class ReservaOut(BaseModel):
    id: int
    vueloId: int
    pasajero: str
    estado: str
    asiento: str | None = None
    loteId: int | None = Field(default=None, description="Reservas de una misma compra comparten este valor")
    precio: float | None = Field(default=None, description="Precio por asiento al momento de reservar")
    tipoDocumento: str | None = Field(default=None, description="'cedula' o 'pasaporte'")
    documento: str | None = Field(default=None, description="Número de documento de quien viaja")


class CancelacionOut(BaseModel):
    id: int
    estado: str


def cancelar_asientos_s3(vuelo_id: int, reserva_id: int) -> None:
    """Internal call to S3 POST /api/internal/reservas/{id}/cancelar: frees the seat inside the sale cutoff rules.

    S3 answers 409 RESERVA_CERRADA when the flight departs in less than 3 hours; that refusal reaches the client as is.
    """
    try:
        response = httpx.post(
            f"{FLIGHTS_URL}/api/internal/reservas/{reserva_id}/cancelar",
            json={"vueloId": vuelo_id},
            timeout=5,
        )
    except httpx.HTTPError:
        raise ApiError(503, "SERVICIO_NO_DISPONIBLE", "El servicio de vuelos no está disponible.")
    if response.status_code == 200:
        return
    if response.status_code in {404, 409}:
        cuerpo = response.json()
        raise ApiError(response.status_code, cuerpo["codigo"], cuerpo["mensaje"])
    raise ApiError(503, "SERVICIO_NO_DISPONIBLE", "El servicio de vuelos no está disponible.")


def restaurar_asiento_s3(vuelo_id: int, reserva_id: int, asiento: str) -> None:
    """Compensation: the cancellation could not be stored, so the seat goes back to the reservation. Logged on failure."""
    try:
        response = httpx.post(
            f"{FLIGHTS_URL}/api/internal/reservas/{reserva_id}/cambiar-asiento",
            json={"vueloId": vuelo_id, "asiento": asiento},
            timeout=5,
        )
        if response.status_code == 200:
            return
    except httpx.HTTPError:
        pass
    log.error("No se pudo restaurar en S3 el asiento %s de la reserva %s (compensación pendiente)", asiento, reserva_id)


def obtener_vuelo_para_factura(vuelo_id: int) -> dict | None:
    """Datos del vuelo para la factura (S3). Si S3 no responde, la factura sale sin ese bloque."""
    try:
        response = httpx.get(f"{FLIGHTS_URL}/api/vuelos/{vuelo_id}", timeout=3)
        return response.json() if response.status_code == 200 else None
    except (httpx.HTTPError, ValueError):
        return None


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


@app.get(
    "/api/reservas/lote/{lote_id}/factura",
    response_class=Response,
    responses={200: {"content": {"application/xml": {}}, "description": "Factura XML del lote"}, **errores(401, 404)},
    summary="Factura XML de un lote propio: subtotal, IVA 15% y total (requiere token Bearer)",
)
def factura_lote(lote_id: int, cuenta: Cuenta = Depends(current_cliente_cuenta)):
    with SessionLocal() as db:
        reservas = (
            db.query(Reserva)
            .filter(Reserva.lote_id == lote_id, Reserva.usuario_email == cuenta.email)
            .order_by(Reserva.id)
            .all()
        )
        # 404 también si el lote es de otro usuario: no se revela que exista.
        if not reservas:
            raise ApiError(404, "LOTE_NO_EXISTE", "El lote no existe.")
        confirmadas = [r for r in reservas if r.estado == "confirmada"]
        # Nombre de la cuenta (claim del token). Tokens anteriores al claim usan el primer pasajero.
        cliente = cuenta.nombre or (confirmadas or reservas)[0].pasajero
        asientos = {
            fila.reserva_id: fila.asiento
            for fila in db.query(ReservaAsiento).filter(ReservaAsiento.reserva_id.in_([r.id for r in confirmadas])).all()
        }
        boletos = [
            {
                "pasajero": r.pasajero,
                "tipoDocumento": r.tipo_documento,
                "documento": r.documento,
                "asiento": asientos.get(r.id),
                "precio": r.precio,
            }
            for r in confirmadas
        ]
        vuelo = obtener_vuelo_para_factura((confirmadas or reservas)[0].vuelo_id)
        xml = construir_factura_xml(lote_id, cliente, [r.precio for r in confirmadas], date.today(), boletos, vuelo, correo=cuenta.email)
        return Response(content=xml, media_type="application/xml")


@app.get(
    "/api/reservas/{reserva_id}",
    response_model=ReservaOut,
    responses=errores(401, 404),
    summary="Consultar una reserva propia (requiere token Bearer)",
)
def consultar_reserva(reserva_id: int, email: str = Depends(current_cliente_email)):
    with SessionLocal() as db:
        fila = (
            db.query(Reserva, ReservaAsiento.asiento)
            .outerjoin(ReservaAsiento, ReservaAsiento.reserva_id == Reserva.id)
            .filter(Reserva.id == reserva_id, Reserva.usuario_email == email)
            .first()
        )
        # 404 también si la reserva es de otro usuario: no se revela que exista.
        if fila is None:
            raise ApiError(404, "RESERVA_NO_EXISTE", "La reserva no existe.")
        reserva, asiento = fila
        return {**reserva_to_dict(reserva), "asiento": asiento}


@app.delete(
    "/api/reservas/{reserva_id}",
    response_model=CancelacionOut,
    responses=errores(400, 401, 404, 409, 503),
    summary="Cancelar una reserva propia y liberar su asiento (hasta 3 horas antes de la salida)",
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
        vuelo_id, id_reserva = reserva.vuelo_id, reserva.id
        fila = db.get(ReservaAsiento, id_reserva)
        asiento = fila.asiento if fila else None

        # S3 libera primero (y aplica el corte). Solo si el guardado local falla hay que devolver el asiento.
        cancelar_asientos_s3(vuelo_id, id_reserva)
        reserva.estado = "cancelada"
        try:
            db.commit()
        except SQLAlchemyError:
            db.rollback()
            if asiento is not None:
                restaurar_asiento_s3(vuelo_id, id_reserva, asiento)
            raise ApiError(503, "SERVICIO_NO_DISPONIBLE", "No se pudo cancelar la reserva. Intente de nuevo.")
        return {"id": id_reserva, "estado": "cancelada"}
