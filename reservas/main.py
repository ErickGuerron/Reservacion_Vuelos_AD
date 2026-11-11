"""S4 - Flight reservation service (port 5004). Consumes S3 over HTTP.

Consistency between S3 (seats) and S4 (bookings) lives in two different databases, so it is
coordinated in this order, with compensation when a later step fails:

- Reserving (POST /api/reservas/lote): S4 writes the bookings inside an open transaction and
  asks S3 to take ALL the seats in one S3 transaction (all or nothing). Only when S3 accepts
  does S4 commit its rows. If that commit fails, S4 releases the seats it took in S3.
  If S3 refuses any seat, nothing is stored in S4 either.
- Changing a seat (PUT /api/reservas/{id}/asiento): S3 moves the seat (atomic in S3). If S4
  cannot store the new seat, S3 is asked to put the reservation back on the previous seat.
"""

import logging
import os

import httpx
from fastapi import Depends, FastAPI, status
from pydantic import BaseModel, Field, field_validator, model_validator

from shared.asientos import MAX_ASIENTOS
from shared.validacion import validar_codigo_asiento, validar_documento, validar_nombre_pasajero, validar_solo_numero
from shared.cors import enable_cors
from shared.db import add_column_if_missing, create_tables, session_factory
from shared.errors import ApiError, errores, register_error_handlers
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
from shared.security import current_cliente_email

engine, SessionLocal = session_factory("reservas")
create_tables(engine, Base, [Reserva.__table__, ReservaAsiento.__table__])
add_column_if_missing(engine, "reservas", "lote_id", RESERVA_LOTE_DDL)
add_column_if_missing(engine, "reservas", "precio", RESERVA_PRECIO_DDL)
add_column_if_missing(engine, "reservas", "tipo_documento", RESERVA_TIPO_DOCUMENTO_DDL)
add_column_if_missing(engine, "reservas", "documento", RESERVA_DOCUMENTO_DDL)

FLIGHTS_URL = os.getenv("FLIGHTS_SERVICE_URL", "http://localhost:5003")
log = logging.getLogger("reservas")

app = FastAPI(title="S4 - Flight reservation", version="1.2.0")
register_error_handlers(app)
enable_cors(app)


def _validar_asiento_opcional(valor: str | None) -> str | None:
    """None o vacío: se asigna el primero libre. Si viene, debe tener formato de asiento (sin espacios alrededor)."""
    if valor is None or valor == "":
        return None
    return validar_codigo_asiento(valor)


def _documento_completo(modelo):
    """El documento es opcional, pero tipo y número van juntos y se validan según el tipo."""
    if (modelo.tipoDocumento is None) != (modelo.documento is None):
        raise ValueError("El tipo de documento y su número deben enviarse juntos.")
    if modelo.tipoDocumento is not None:
        modelo.tipoDocumento, modelo.documento = validar_documento(modelo.tipoDocumento, modelo.documento)
    return modelo


class ReservaIn(BaseModel):
    vueloId: int
    versionMapa: int | None = Field(default=None, description="Versión del mapa que vio el cliente")
    pasajero: str = Field(min_length=1, max_length=100)
    tipoDocumento: str | None = Field(default=None, description="'cedula' o 'pasaporte'")
    documento: str | None = Field(default=None, max_length=20, description="Número de cédula o de pasaporte")
    asiento: str | None = Field(
        default=None,
        max_length=10,
        description="Código del asiento elegido (por ejemplo 12C). Si se omite, se asigna el primero libre.",
    )

    @field_validator("vueloId", mode="before")
    @classmethod
    def _vuelo_numerico(cls, valor: object) -> object:
        return validar_solo_numero(valor, "vueloId")

    @field_validator("pasajero")
    @classmethod
    def _pasajero_valido(cls, valor: str) -> str:
        return validar_nombre_pasajero(valor)

    @field_validator("asiento")
    @classmethod
    def _asiento_valido(cls, valor: str | None) -> str | None:
        return _validar_asiento_opcional(valor)

    @model_validator(mode="after")
    def _documento_valido(self):
        return _documento_completo(self)


class ReservaItemIn(BaseModel):
    pasajero: str = Field(min_length=1, max_length=100)
    asiento: str | None = Field(default=None, max_length=10)
    tipoDocumento: str | None = Field(default=None, description="'cedula' o 'pasaporte'")
    documento: str | None = Field(default=None, max_length=20, description="Número de cédula o de pasaporte")

    @field_validator("pasajero")
    @classmethod
    def _pasajero_valido(cls, valor: str) -> str:
        return validar_nombre_pasajero(valor)

    @field_validator("asiento")
    @classmethod
    def _asiento_valido(cls, valor: str | None) -> str | None:
        return _validar_asiento_opcional(valor)

    @model_validator(mode="after")
    def _documento_valido(self):
        return _documento_completo(self)


class ReservasLoteIn(BaseModel):
    vueloId: int
    reservas: list[ReservaItemIn] = Field(min_length=1, max_length=MAX_ASIENTOS)
    versionMapa: int | None = Field(
        default=None, description="Versión del mapa de asientos que vio el cliente (GET /api/vuelos/{id}/asientos)"
    )

    @field_validator("vueloId", mode="before")
    @classmethod
    def _vuelo_numerico(cls, valor: object) -> object:
        return validar_solo_numero(valor, "vueloId")


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


class CambioAsientoIn(BaseModel):
    asiento: str = Field(min_length=1, max_length=10, description="Código del nuevo asiento (por ejemplo 12C)")
    versionMapa: int | None = Field(default=None, description="Versión del mapa que vio el cliente")

    @field_validator("asiento")
    @classmethod
    def _asiento_valido(cls, valor: str) -> str:
        return validar_codigo_asiento(valor)


def _s3_error(response: httpx.Response) -> None:
    """Translate a refusal from S3 into the same error the client gets from S4."""
    if response.status_code in {404, 409}:
        cuerpo = response.json()
        raise ApiError(response.status_code, cuerpo["codigo"], cuerpo["mensaje"])
    raise ApiError(503, "SERVICIO_NO_DISPONIBLE", "El servicio de vuelos no está disponible.")


def obtener_vuelo(vuelo_id: int) -> dict:
    """Internal call to S3 GET /api/vuelos/{id}."""
    try:
        response = httpx.get(f"{FLIGHTS_URL}/api/vuelos/{vuelo_id}", timeout=5)
    except httpx.HTTPError:
        raise ApiError(503, "SERVICIO_NO_DISPONIBLE", "El servicio de vuelos no está disponible.")
    if response.status_code == 404:
        # S3 distingue "no existe" de "no disponible" (inactivo); se conserva su código y mensaje.
        try:
            cuerpo = response.json()
        except ValueError:
            cuerpo = {}
        raise ApiError(404, cuerpo.get("codigo", "VUELO_NO_EXISTE"), cuerpo.get("mensaje", "El vuelo no existe."))
    if response.status_code != 200:
        raise ApiError(503, "SERVICIO_NO_DISPONIBLE", "El servicio de vuelos no está disponible.")
    return response.json()


def reservar_lote_s3(vuelo_id: int, items: list[tuple[int, str | None]], version: int | None = None) -> dict[int, str]:
    """Internal call to S3: take every seat of the batch in one transaction. Returns {reserva_id: asiento}."""
    cuerpo = {"reservas": [{"reservaId": reserva_id, "asiento": asiento} for reserva_id, asiento in items]}
    if version is not None:
        cuerpo["version"] = version  # S3 rechaza el lote si el mapa cambió desde que el cliente lo vio
    try:
        response = httpx.post(f"{FLIGHTS_URL}/api/internal/vuelos/{vuelo_id}/asientos/reservar-lote", json=cuerpo, timeout=5)
    except httpx.HTTPError:
        raise ApiError(503, "SERVICIO_NO_DISPONIBLE", "El servicio de vuelos no está disponible.")
    if response.status_code == 200:
        return {a["reservaId"]: a["asiento"] for a in response.json()["asientos"]}
    _s3_error(response)


def cambiar_asiento_s3(vuelo_id: int, reserva_id: int, asiento: str, version: int | None = None) -> str:
    """Internal call to S3 POST /api/internal/reservas/{id}/cambiar-asiento. Returns the new seat code."""
    cuerpo = {"vueloId": vuelo_id, "asiento": asiento}
    if version is not None:
        cuerpo["version"] = version  # S3 rechaza el cambio si el mapa cambió desde que el cliente lo vio
    try:
        response = httpx.post(
            f"{FLIGHTS_URL}/api/internal/reservas/{reserva_id}/cambiar-asiento",
            json=cuerpo,
            timeout=5,
        )
    except httpx.HTTPError:
        raise ApiError(503, "SERVICIO_NO_DISPONIBLE", "El servicio de vuelos no está disponible.")
    if response.status_code == 200:
        return response.json()["asiento"]
    _s3_error(response)


def liberar_reservas_s3(reserva_ids: list[int]) -> None:
    """Compensation: give back the seats of bookings that could not be stored. Best effort, logged on failure."""
    for reserva_id in reserva_ids:
        try:
            httpx.post(f"{FLIGHTS_URL}/api/internal/reservas/{reserva_id}/liberar", timeout=5)
        except httpx.HTTPError:
            log.error("No se pudo liberar en S3 los asientos de la reserva %s (compensación pendiente)", reserva_id)


def _revertir_cambio_s3(vuelo_id: int, reserva_id: int, asiento_anterior: str | None) -> None:
    """Compensation for a seat change: back to the previous seat, or free the seat if there was none."""
    try:
        if asiento_anterior:
            cambiar_asiento_s3(vuelo_id, reserva_id, asiento_anterior)
        else:
            liberar_reservas_s3([reserva_id])
    except ApiError:
        log.error("No se pudo revertir el cambio de asiento de la reserva %s (compensación pendiente)", reserva_id)


@app.post(
    "/api/reservas/lote",
    status_code=status.HTTP_201_CREATED,
    response_model=list[ReservaOut],
    responses=errores(400, 401, 404, 409, 503),
    summary="Reservar varios asientos a la vez: todos o ninguno (requiere token Bearer)",
)
def crear_reservas_lote(datos: ReservasLoteIn, email: str = Depends(current_cliente_email)):
    vuelo = obtener_vuelo(datos.vueloId)
    # Chequeo previo para responder rápido; el descuento real lo hace S3 de forma atómica.
    if vuelo["asientosDisponibles"] < len(datos.reservas):
        raise ApiError(409, "SIN_ASIENTOS", "El vuelo no tiene asientos disponibles.")
    precio = vuelo.get("precio")
    # 1) Las reservas se guardan como "pendiente" en una transacción corta. Ninguna transacción queda abierta
    #    mientras S3 toma los asientos: con una sola conexión por proceso, eso bloqueaba a las demás peticiones.
    with SessionLocal() as db:
        reservas = [
            Reserva(
                usuario_email=email,
                vuelo_id=datos.vueloId,
                pasajero=item.pasajero,
                estado="pendiente",
                precio=precio,
                tipo_documento=item.tipoDocumento,
                documento=item.documento,
            )
            for item in datos.reservas
        ]
        db.add_all(reservas)
        db.flush()  # the ids are needed to tag the seats in S3 and to name the lote
        for reserva in reservas:
            reserva.lote_id = reservas[0].id
        # Se leen antes del commit: después del commit los atributos caducan y cada lectura sería otra consulta.
        ids = [reserva.id for reserva in reservas]
        pedidos = [(reserva.id, (item.asiento or "").strip() or None) for reserva, item in zip(reservas, datos.reservas)]
        base = [reserva_to_dict(reserva) for reserva in reservas]
        db.commit()

    # 2) S3 toma todos los asientos en una transacción propia. Si falla, o si la respuesta se pierde (timeout),
    #    se devuelven los asientos (es idempotente) y se borran las pendientes.
    try:
        asignados = reservar_lote_s3(datos.vueloId, pedidos, datos.versionMapa)
        # 3) Solo cuando S3 acepta, la reserva pasa a confirmada y se guardan los asientos.
        with SessionLocal() as db:
            for id_reserva, asiento in asignados.items():
                db.add(ReservaAsiento(reserva_id=id_reserva, vuelo_id=datos.vueloId, asiento=asiento))
            db.query(Reserva).filter(Reserva.id.in_(ids)).update({Reserva.estado: "confirmada"}, synchronize_session=False)
            db.commit()
    except Exception:
        liberar_reservas_s3(ids)
        _borrar_reservas_pendientes(ids)
        raise
    return [{**fila, "estado": "confirmada", "asiento": asignados[fila["id"]]} for fila in base]


def _borrar_reservas_pendientes(ids: list[int]) -> None:
    """Deshace un intento de reserva que no se pudo completar."""
    try:
        with SessionLocal() as db:
            db.query(Reserva).filter(Reserva.id.in_(ids)).delete(synchronize_session=False)
            db.commit()
    except Exception:
        log.error("No se pudieron borrar las reservas pendientes %s", ids)


@app.post(
    "/api/reservas",
    status_code=status.HTTP_201_CREATED,
    response_model=ReservaOut,
    responses=errores(400, 401, 404, 409, 503),
    summary="Reservar un vuelo, con asiento elegido o asignado (requiere token Bearer)",
)
def crear_reserva(datos: ReservaIn, email: str = Depends(current_cliente_email)):
    lote = crear_reservas_lote(
        ReservasLoteIn(
            vueloId=datos.vueloId,
            versionMapa=datos.versionMapa,
            reservas=[ReservaItemIn(pasajero=datos.pasajero, asiento=datos.asiento, tipoDocumento=datos.tipoDocumento, documento=datos.documento)],
        ),
        email,
    )
    return lote[0]


@app.put(
    "/api/reservas/{reserva_id}/asiento",
    response_model=ReservaOut,
    responses=errores(400, 401, 404, 409, 503),
    summary="Cambiar el asiento de una reserva propia (requiere token Bearer)",
)
def cambiar_asiento_reserva(reserva_id: int, datos: CambioAsientoIn, email: str = Depends(current_cliente_email)):
    with SessionLocal() as db:
        # Bloquea la reserva hasta el commit: un cambio y una cancelación de la misma reserva van en fila.
        reserva = db.get(Reserva, reserva_id, with_for_update=True)
        # 404 también si la reserva es de otro usuario: no se revela que exista.
        if reserva is None or reserva.usuario_email != email:
            raise ApiError(404, "RESERVA_NO_EXISTE", "La reserva no existe.")
        if reserva.estado != "confirmada":
            raise ApiError(409, "RESERVA_NO_ACTIVA", "Solo se puede cambiar el asiento de una reserva confirmada.")
        fila = db.get(ReservaAsiento, reserva.id)
        anterior = fila.asiento if fila else None
        nuevo = cambiar_asiento_s3(reserva.vuelo_id, reserva.id, datos.asiento.strip(), datos.versionMapa)
        try:
            if fila is None:
                db.add(ReservaAsiento(reserva_id=reserva.id, vuelo_id=reserva.vuelo_id, asiento=nuevo))
            else:
                fila.asiento = nuevo
            db.commit()
        except Exception:
            _revertir_cambio_s3(reserva.vuelo_id, reserva.id, anterior)
            raise
        return {**reserva_to_dict(reserva), "asiento": nuevo}
