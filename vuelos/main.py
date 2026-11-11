"""S3 - Flight service (port 5003).

Public (clients):      GET /api/vuelos, GET /api/vuelos/{id}, GET /api/vuelos/{id}/asientos
Admin (role "administrador"): POST /api/admin/vuelos
Internal (S4, S5):     POST /api/internal/vuelos/{id}/asientos/reservar,
                       POST /api/internal/reservas/{id}/liberar
"""

import os
from datetime import date, datetime, timedelta, timezone

import httpx
from fastapi import Depends, FastAPI, Query, status
from pydantic import BaseModel, Field, field_validator

from shared.asientos import MAX_ASIENTOS, MIN_ASIENTOS, generar_asientos_para_total, layout_para_total, validar_total_asientos
from shared.cors import enable_cors
from shared.db import add_column_if_missing, create_tables, session_factory
from shared.errors import ApiError, errores, register_error_handlers
from shared.horarios import FRANJAS, estimar, franja_de, validar_horario
from shared.models import (
    VUELO_ACTIVO_DDL,
    VUELO_AVION_DDL,
    VUELO_HORA_DDL,
    VUELO_HORA_LLEGADA_DDL,
    VUELO_VERSION_DDL,
    AsientoVuelo,
    Base,
    Vuelo,
)
from shared.security import current_admin_email
from shared.validacion import validar_iata, validar_solo_numero

engine, SessionLocal = session_factory("vuelos")
create_tables(engine, Base, [Vuelo.__table__, AsientoVuelo.__table__])
add_column_if_missing(engine, "vuelos", "activo", VUELO_ACTIVO_DDL)
add_column_if_missing(engine, "vuelos", "hora", VUELO_HORA_DDL)
add_column_if_missing(engine, "vuelos", "hora_llegada", VUELO_HORA_LLEGADA_DDL)
add_column_if_missing(engine, "vuelos", "avion_id", VUELO_AVION_DDL)
add_column_if_missing(engine, "vuelos", "version", VUELO_VERSION_DDL)

# S6 Aviones: de allí sale la capacidad (número de asientos) de cada vuelo nuevo o editado.
AVIONES_URL = os.getenv("AVIONES_SERVICE_URL", "http://localhost:5006")


def obtener_avion(avion_id: int) -> dict:
    """Internal call to S6 GET /api/internal/aviones/{id}: name, capacity and whether it is active."""
    try:
        response = httpx.get(f"{AVIONES_URL}/api/internal/aviones/{avion_id}", timeout=5)
    except httpx.HTTPError:
        raise ApiError(503, "SERVICIO_NO_DISPONIBLE", "El servicio de aviones no está disponible.")
    if response.status_code == 404:
        raise ApiError(404, "AVION_NO_EXISTE", "El avión no existe.")
    if response.status_code != 200:
        raise ApiError(503, "SERVICIO_NO_DISPONIBLE", "El servicio de aviones no está disponible.")
    return response.json()


def _avion_asignable(avion_id: int) -> dict:
    avion = obtener_avion(avion_id)
    if not avion["activo"]:
        raise ApiError(409, "AVION_INACTIVO", "El avión está desactivado y no puede asignarse a vuelos.")
    motivo = validar_total_asientos(avion["capacidad"])
    if motivo:
        raise ApiError(400, "DATOS_INVALIDOS", motivo)
    return avion

# Hora de salida en 24 horas, HH:MM.
HORA_PATTERN = r"^([01]\d|2[0-3]):[0-5]\d$"

SEED_FLIGHTS = [
    {"origen": "UIO", "destino": "GYE", "fecha": date(2026, 11, 10), "hora": "08:30", "precio": 45.0, "asientos_disponibles": 30},
    {"origen": "UIO", "destino": "GYE", "fecha": date(2026, 11, 12), "hora": "14:15", "precio": 52.5, "asientos_disponibles": 0},
    {"origen": "GYE", "destino": "UIO", "fecha": date(2026, 11, 15), "hora": "09:45", "precio": 48.0, "asientos_disponibles": 12},
    {"origen": "UIO", "destino": "MAD", "fecha": date(2026, 12, 1), "hora": "22:10", "precio": 780.0, "asientos_disponibles": 5},
]

_INTENTOS_ASIENTO_LIBRE = 5

# Corte de venta: no se reserva un vuelo que sale en menos de 3 horas.
# Horario de Ecuador (UTC-5, sin horario de verano).
ZONA_HORARIA_VENTA = timezone(timedelta(hours=-5))
ANTICIPACION_MINIMA_RESERVA = timedelta(hours=3)


def _ahora_venta() -> datetime:
    return datetime.now(ZONA_HORARIA_VENTA)


def _salida(vuelo: Vuelo) -> datetime:
    horas, minutos = (int(parte) for parte in vuelo.hora.split(":"))
    return datetime(vuelo.fecha.year, vuelo.fecha.month, vuelo.fecha.day, horas, minutos, tzinfo=ZONA_HORARIA_VENTA)


def _validar_ventana_reserva(vuelo: Vuelo) -> None:
    if _salida(vuelo) - _ahora_venta() < ANTICIPACION_MINIMA_RESERVA:
        raise ApiError(409, "RESERVA_CERRADA", "La venta de este vuelo cerró 3 horas antes de la salida.")


def _asegurar_asientos(db) -> None:
    """Give every flight without a seat map one (seeded and pre-existing flights).

    Flights created before seat selection get a layout with as many seats as they had free.
    """
    con_mapa = {vuelo_id for (vuelo_id,) in db.query(AsientoVuelo.vuelo_id).distinct()}
    for vuelo in db.query(Vuelo).all():
        if vuelo.id in con_mapa:
            continue
        db.add_all(AsientoVuelo(vuelo_id=vuelo.id, **datos) for datos in generar_asientos_para_total(vuelo.asientos_disponibles))


def _seed() -> None:
    with SessionLocal() as db:
        if db.query(Vuelo).count() == 0:
            db.add_all(Vuelo(**flight, activo=True) for flight in SEED_FLIGHTS)  # datos de demostración publicados
            db.commit()
        _asegurar_asientos(db)
        db.commit()


_seed()

app = FastAPI(title="S3 - Flight service", version="1.1.0")
register_error_handlers(app)
enable_cors(app)


class VueloOut(BaseModel):
    id: int
    origen: str
    destino: str
    fecha: date
    hora: str
    horaLlegada: str | None = None
    precio: float
    asientosDisponibles: int


class VueloAdminIn(BaseModel):
    origen: str = Field(description="Código IATA de 3 letras")
    destino: str = Field(description="Código IATA de 3 letras")
    fecha: date
    hora: str = Field(default="08:00", pattern=HORA_PATTERN, description="Hora de salida HH:MM (24 horas)")
    horaLlegada: str | None = Field(
        default=None,
        pattern=HORA_PATTERN,
        description="Hora estimada de llegada HH:MM (24 horas). Opcional.",
    )
    precio: float = Field(gt=0, le=100_000)
    avionId: int = Field(gt=0, description="Avión registrado en S6: sus asientos son los del vuelo")
    activo: bool = Field(
        default=False,
        description="Al crear: true publica el vuelo; false lo deja como borrador (valor por defecto)",
    )

    @field_validator("origen", "destino")
    @classmethod
    def _iata(cls, valor: str) -> str:
        return validar_iata(valor)

    @field_validator("precio", "avionId", mode="before")
    @classmethod
    def _solo_numero(cls, valor: object) -> object:
        return validar_solo_numero(valor, "El valor")


class AsientoOut(BaseModel):
    codigo: str
    fila: int
    columna: str
    ocupado: bool


class MapaAsientosOut(BaseModel):
    vueloId: int
    filas: int
    columnas: list[str]
    asientosLibres: int
    version: int = Field(description="Versión del mapa: cambia con cada cambio de asientos del vuelo")
    asientos: list[AsientoOut]


class ReservarAsientoIn(BaseModel):
    reservaId: int
    asiento: str | None = Field(default=None, max_length=10, description="Omitir para asignar el primero libre")


class AsientoAsignadoOut(BaseModel):
    vueloId: int
    asiento: str


class LiberacionOut(BaseModel):
    liberados: int


def _to_dict(vuelo: Vuelo) -> dict:
    return {
        "id": vuelo.id,
        "origen": vuelo.origen,
        "destino": vuelo.destino,
        "fecha": vuelo.fecha.isoformat(),
        "hora": vuelo.hora,
        "horaLlegada": vuelo.hora_llegada,
        "precio": vuelo.precio,
        "asientosDisponibles": vuelo.asientos_disponibles,
        "activo": bool(vuelo.activo),
    }


def _flight_or_404(db, vuelo_id: int, bloquear: bool = False) -> Vuelo:
    # `bloquear` toma un lock de fila (SELECT ... FOR UPDATE) hasta el commit; SQLite lo ignora.
    vuelo = db.get(Vuelo, vuelo_id, with_for_update=bloquear)
    if vuelo is None:
        raise ApiError(404, "VUELO_NO_EXISTE", "El vuelo no existe.")
    return vuelo


def _vuelo_publico(db, vuelo_id: int) -> Vuelo:
    """Para clientes: un vuelo inactivo no existe para ellos."""
    vuelo = _flight_or_404(db, vuelo_id)
    if not vuelo.activo:
        raise ApiError(404, "VUELO_NO_DISPONIBLE", "El vuelo no está disponible.")
    return vuelo


def _ocupados(db, vuelo_id: int) -> int:
    return db.query(AsientoVuelo).filter(AsientoVuelo.vuelo_id == vuelo_id, AsientoVuelo.reserva_id.isnot(None)).count()


@app.get(
    "/api/vuelos",
    response_model=list[VueloOut],
    responses=errores(400),
    summary="Buscar vuelos por origen, destino y fecha",
)
def buscar_vuelos(
    origen: str | None = Query(default=None, pattern=r"^[A-Za-z]{3}$"),
    destino: str | None = Query(default=None, pattern=r"^[A-Za-z]{3}$"),
    fecha: date | None = None,
    franja: str | None = Query(
        default=None,
        pattern="^(" + "|".join(FRANJAS) + ")$",
        description="Franja de la hora de salida: madrugada 00-06, manana 06-12, tarde 12-18, noche 18-24",
    ),
):
    with SessionLocal() as db:
        query = db.query(Vuelo).filter(Vuelo.activo == True)  # noqa: E712 (SQL Server BIT)
        if origen:
            query = query.filter(Vuelo.origen == origen.upper())
        if destino:
            query = query.filter(Vuelo.destino == destino.upper())
        if fecha:
            query = query.filter(Vuelo.fecha == fecha)
        vuelos = query.order_by(Vuelo.id).all()
        if franja:
            vuelos = [v for v in vuelos if franja_de(v.hora) == franja]
        return [_to_dict(v) for v in vuelos]


class EstimacionOut(BaseModel):
    duracionHabitual: int = Field(description="Minutos de vuelo habituales de la ruta")
    duracionMinima: int
    duracionMaxima: int
    horaLlegadaSugerida: str = Field(description="HH:MM en la hora local del destino")
    duracionIndicada: int | None = None
    valida: bool | None = Field(default=None, description="Solo si se envía horaLlegada")
    mensaje: str | None = None


@app.get(
    "/api/vuelos/estimacion",
    response_model=EstimacionOut,
    responses=errores(400, 404),
    summary="Duración habitual de una ruta y llegada sugerida para una salida",
)
def estimar_vuelo(
    origen: str = Query(pattern=r"^[A-Za-z]{3}$"),
    destino: str = Query(pattern=r"^[A-Za-z]{3}$"),
    fecha: date = Query(),
    hora: str = Query(pattern=HORA_PATTERN),
    horaLlegada: str | None = Query(default=None, pattern=HORA_PATTERN),
):
    estimacion = estimar(origen.upper(), destino.upper(), fecha, hora, horaLlegada)
    if estimacion is None:
        raise ApiError(404, "RUTA_SIN_ESTIMACION", "No hay una duración habitual registrada para esa ruta.")
    return estimacion


@app.get(
    "/api/vuelos/{vuelo_id}",
    response_model=VueloOut,
    responses=errores(400, 404),
    summary="Detalle de un vuelo",
)
def detalle_vuelo(vuelo_id: int):
    with SessionLocal() as db:
        return _to_dict(_vuelo_publico(db, vuelo_id))


@app.get(
    "/api/vuelos/{vuelo_id}/asientos",
    response_model=MapaAsientosOut,
    responses=errores(400, 404),
    summary="Mapa de asientos de un vuelo con su disponibilidad",
)
def mapa_asientos(vuelo_id: int):
    with SessionLocal() as db:
        vuelo = _vuelo_publico(db, vuelo_id)
        asientos = (
            db.query(AsientoVuelo)
            .filter(AsientoVuelo.vuelo_id == vuelo_id)
            .order_by(AsientoVuelo.fila, AsientoVuelo.columna)
            .all()
        )
        return {
            "vueloId": vuelo_id,
            "filas": max((a.fila for a in asientos), default=0),
            "columnas": sorted({a.columna for a in asientos}),
            "asientosLibres": sum(1 for a in asientos if a.reserva_id is None),
            "version": vuelo.version or 0,
            "asientos": [
                {"codigo": a.codigo, "fila": a.fila, "columna": a.columna, "ocupado": a.reserva_id is not None}
                for a in asientos
            ],
        }


@app.post(
    "/api/admin/vuelos",
    status_code=status.HTTP_201_CREATED,
    response_model=VueloOut,
    responses=errores(400, 401, 403),
    summary="Crear un vuelo con su mapa de asientos (solo administradores)",
)
def crear_vuelo(datos: VueloAdminIn, _: str = Depends(current_admin_email)):
    origen, destino = datos.origen.upper(), datos.destino.upper()
    if origen == destino:
        raise ApiError(400, "DATOS_INVALIDOS", "El origen y el destino deben ser distintos.")
    if datos.fecha <= date.today():
        raise ApiError(400, "DATOS_INVALIDOS", "El vuelo debe programarse desde mañana en adelante.")
    motivo = validar_horario(origen, destino, datos.fecha, datos.hora, datos.horaLlegada)
    if motivo:
        raise ApiError(400, "DATOS_INVALIDOS", motivo)
    avion = _avion_asignable(datos.avionId)
    capacidad = avion["capacidad"]

    with SessionLocal() as db:
        vuelo = Vuelo(
            origen=origen,
            destino=destino,
            fecha=datos.fecha,
            hora=datos.hora,
            hora_llegada=datos.horaLlegada,
            precio=datos.precio,
            asientos_disponibles=capacidad,
            activo=datos.activo,
            avion_id=datos.avionId,
        )
        db.add(vuelo)
        db.flush()
        db.add_all(AsientoVuelo(vuelo_id=vuelo.id, **datos_asiento) for datos_asiento in layout_para_total(capacidad))
        db.commit()
        db.refresh(vuelo)
        return _to_dict(vuelo)


class VueloAdminOut(BaseModel):
    id: int
    origen: str
    destino: str
    fecha: date
    hora: str
    horaLlegada: str | None = None
    precio: float
    avionId: int | None = Field(default=None, description="Avión del vuelo; null en vuelos anteriores al registro de aviones")
    totalAsientos: int
    asientosDisponibles: int
    asientosOcupados: int
    activo: bool
    editable: bool = Field(description="True si no tiene reservas: solo entonces puede editarse")


class EstadoVueloIn(BaseModel):
    activo: bool


def _admin_dict(db, vuelo: Vuelo) -> dict:
    total = db.query(AsientoVuelo).filter(AsientoVuelo.vuelo_id == vuelo.id).count()
    ocupados = _ocupados(db, vuelo.id)
    return {
        "id": vuelo.id,
        "origen": vuelo.origen,
        "destino": vuelo.destino,
        "fecha": vuelo.fecha,
        "hora": vuelo.hora,
        "horaLlegada": vuelo.hora_llegada,
        "precio": vuelo.precio,
        "avionId": vuelo.avion_id,
        "totalAsientos": total,
        "asientosDisponibles": vuelo.asientos_disponibles,
        "asientosOcupados": ocupados,
        "activo": bool(vuelo.activo),
        "editable": ocupados == 0,
    }


@app.get(
    "/api/admin/vuelos",
    response_model=list[VueloAdminOut],
    responses=errores(401, 403),
    summary="Listar todos los vuelos, también los inactivos (solo administradores)",
)
def listar_vuelos_admin(_: str = Depends(current_admin_email)):
    with SessionLocal() as db:
        return [_admin_dict(db, vuelo) for vuelo in db.query(Vuelo).order_by(Vuelo.id).all()]


@app.put(
    "/api/admin/vuelos/{vuelo_id}",
    response_model=VueloAdminOut,
    responses=errores(400, 401, 403, 404, 409),
    summary="Editar un vuelo que no tiene reservas (solo administradores)",
)
def editar_vuelo(vuelo_id: int, datos: VueloAdminIn, _: str = Depends(current_admin_email)):
    origen, destino = datos.origen.upper(), datos.destino.upper()
    if origen == destino:
        raise ApiError(400, "DATOS_INVALIDOS", "El origen y el destino deben ser distintos.")
    if datos.fecha <= date.today():
        raise ApiError(400, "DATOS_INVALIDOS", "El vuelo debe programarse desde mañana en adelante.")
    motivo = validar_horario(origen, destino, datos.fecha, datos.hora, datos.horaLlegada)
    if motivo:
        raise ApiError(400, "DATOS_INVALIDOS", motivo)
    capacidad = _avion_asignable(datos.avionId)["capacidad"]

    with SessionLocal() as db:
        vuelo = _flight_or_404(db, vuelo_id)
        if _ocupados(db, vuelo_id) > 0:
            raise ApiError(409, "VUELO_CON_RESERVAS", "El vuelo tiene reservas y no puede editarse.")
        vuelo.origen, vuelo.destino, vuelo.fecha, vuelo.hora, vuelo.precio = origen, destino, datos.fecha, datos.hora, datos.precio
        vuelo.hora_llegada = datos.horaLlegada
        vuelo.avion_id = datos.avionId
        total_actual = db.query(AsientoVuelo).filter(AsientoVuelo.vuelo_id == vuelo_id).count()
        if total_actual != capacidad:
            # Sin reservas no hay asientos tomados: se rehace el mapa con la capacidad del avión elegido.
            db.query(AsientoVuelo).filter(AsientoVuelo.vuelo_id == vuelo_id).delete(synchronize_session=False)
            db.add_all(AsientoVuelo(vuelo_id=vuelo_id, **datos_asiento) for datos_asiento in layout_para_total(capacidad))
        vuelo.asientos_disponibles = capacidad
        db.commit()
        db.refresh(vuelo)
        return _admin_dict(db, vuelo)


@app.patch(
    "/api/admin/vuelos/{vuelo_id}/estado",
    response_model=VueloAdminOut,
    responses=errores(401, 403, 404),
    summary="Activar o desactivar un vuelo (solo administradores)",
)
def cambiar_estado_vuelo(vuelo_id: int, datos: EstadoVueloIn, _: str = Depends(current_admin_email)):
    with SessionLocal() as db:
        vuelo = _flight_or_404(db, vuelo_id)
        vuelo.activo = datos.activo
        db.commit()
        db.refresh(vuelo)
        return _admin_dict(db, vuelo)


# ----- Uso interno (S4 y S5) -----


def _descontar_disponible(db, vuelo_id: int) -> None:
    actualizados = (
        db.query(Vuelo)
        .filter(Vuelo.id == vuelo_id, Vuelo.asientos_disponibles > 0)
        .update(
            {Vuelo.asientos_disponibles: Vuelo.asientos_disponibles - 1, Vuelo.version: Vuelo.version + 1},
            synchronize_session=False,
        )
    )
    if actualizados != 1:
        raise ApiError(409, "SIN_ASIENTOS", "El vuelo no tiene asientos disponibles.")


def _descontar_disponibles(db, vuelo_id: int, cantidad: int, version: int | None = None) -> None:
    """Descuenta `cantidad` asientos y sube la versión del mapa en un solo UPDATE condicional.

    Si `version` llega y ya no es la del vuelo, el mapa que vio el cliente está desactualizado:
    409 MAPA_DESACTUALIZADO y nada queda descontado. Sin `version` se comporta como antes.
    """
    filtros = [Vuelo.id == vuelo_id, Vuelo.asientos_disponibles >= cantidad]
    if version is not None:
        filtros.append(Vuelo.version == version)
    actualizados = (
        db.query(Vuelo)
        .filter(*filtros)
        .update(
            {Vuelo.asientos_disponibles: Vuelo.asientos_disponibles - cantidad, Vuelo.version: Vuelo.version + 1},
            synchronize_session=False,
        )
    )
    if actualizados == 1:
        return
    if version is not None:
        actual = db.query(Vuelo.version).filter(Vuelo.id == vuelo_id).scalar()
        if actual is not None and actual != version:
            raise ApiError(409, "MAPA_DESACTUALIZADO", "El mapa de asientos cambió. Actualice la selección.")
    raise ApiError(409, "SIN_ASIENTOS", "El vuelo no tiene asientos disponibles.")


def _marcar_si_libre(db, asiento_id: int, reserva_id: int) -> bool:
    """Atomic claim: the UPDATE only succeeds while the seat is still free."""
    actualizados = (
        db.query(AsientoVuelo)
        .filter(AsientoVuelo.id == asiento_id, AsientoVuelo.reserva_id.is_(None))
        .update({AsientoVuelo.reserva_id: reserva_id}, synchronize_session=False)
    )
    return actualizados == 1


def _tomar_asiento(db, vuelo_id: int, reserva_id: int, codigo: str | None) -> str:
    if codigo:
        asiento = db.query(AsientoVuelo).filter(AsientoVuelo.vuelo_id == vuelo_id, AsientoVuelo.codigo == codigo).first()
        if asiento is None:
            raise ApiError(404, "ASIENTO_NO_EXISTE", "El asiento no existe en este vuelo.")
        if not _marcar_si_libre(db, asiento.id, reserva_id):
            raise ApiError(409, "ASIENTO_OCUPADO", f"El asiento {asiento.codigo} ya está ocupado.")
        return asiento.codigo

    for _ in range(_INTENTOS_ASIENTO_LIBRE):
        libre = (
            db.query(AsientoVuelo)
            .filter(AsientoVuelo.vuelo_id == vuelo_id, AsientoVuelo.reserva_id.is_(None))
            .order_by(AsientoVuelo.fila, AsientoVuelo.columna)
            .first()
        )
        if libre is None:
            raise ApiError(409, "SIN_ASIENTOS", "El vuelo no tiene asientos disponibles.")
        if _marcar_si_libre(db, libre.id, reserva_id):
            return libre.codigo
    raise ApiError(409, "ASIENTO_OCUPADO", "Otro pasajero tomó el asiento. Intente de nuevo.")


@app.post(
    "/api/internal/vuelos/{vuelo_id}/asientos/reservar",
    response_model=AsientoAsignadoOut,
    responses=errores(400, 404, 409),
    summary="Tomar un asiento para una reserva (uso interno de S4)",
)
def reservar_asiento(vuelo_id: int, datos: ReservarAsientoIn):
    codigo = (datos.asiento or "").strip().upper() or None
    with SessionLocal() as db:
        vuelo = _flight_or_404(db, vuelo_id)
        if not vuelo.activo:
            raise ApiError(409, "VUELO_INACTIVO", "El vuelo no está disponible para reservas.")
        _validar_ventana_reserva(vuelo)
        _descontar_disponible(db, vuelo_id)
        asiento = _tomar_asiento(db, vuelo_id, datos.reservaId, codigo)
        db.commit()
        return {"vueloId": vuelo_id, "asiento": asiento}


class ItemLoteIn(BaseModel):
    reservaId: int
    asiento: str | None = Field(default=None, max_length=10, description="Omitir para asignar el primero libre")


class LoteIn(BaseModel):
    reservas: list[ItemLoteIn] = Field(min_length=1, max_length=MAX_ASIENTOS)
    version: int | None = Field(default=None, description="Versión del mapa que vio el cliente; si cambió, se rechaza")


class AsignacionOut(BaseModel):
    reservaId: int
    asiento: str


class LoteAsignadoOut(BaseModel):
    vueloId: int
    asientos: list[AsignacionOut]


@app.post(
    "/api/internal/vuelos/{vuelo_id}/asientos/reservar-lote",
    response_model=LoteAsignadoOut,
    responses=errores(400, 404, 409),
    summary="Tomar varios asientos en una sola transacción: todos o ninguno (uso interno de S4)",
)
def reservar_lote(vuelo_id: int, datos: LoteIn):
    ids = [item.reservaId for item in datos.reservas]
    if len(set(ids)) != len(ids):
        raise ApiError(400, "DATOS_INVALIDOS", "Hay reservas repetidas en el lote.")
    with SessionLocal() as db:
        vuelo = _flight_or_404(db, vuelo_id)
        if not vuelo.activo:
            raise ApiError(409, "VUELO_INACTIVO", "El vuelo no está disponible para reservas.")
        _validar_ventana_reserva(vuelo)
        _descontar_disponibles(db, vuelo_id, len(datos.reservas), datos.version)
        asignados = []
        for item in datos.reservas:
            codigo = (item.asiento or "").strip().upper() or None
            # Si cualquier asiento falla, la excepción sale del bloque sin commit: la sesión deshace todo el lote.
            asiento = _tomar_asiento(db, vuelo_id, item.reservaId, codigo)
            asignados.append({"reservaId": item.reservaId, "asiento": asiento})
        db.commit()
        return {"vueloId": vuelo_id, "asientos": asignados}


def _liberar(db, reserva_id: int, vuelo_id: int | None = None) -> int:
    """Free every seat held by the reservation (only on `vuelo_id` when given). The caller commits."""
    consulta = db.query(AsientoVuelo).filter(AsientoVuelo.reserva_id == reserva_id)
    if vuelo_id is not None:
        consulta = consulta.filter(AsientoVuelo.vuelo_id == vuelo_id)
    asientos = consulta.all()
    for asiento in asientos:
        asiento.reserva_id = None
        db.query(Vuelo).filter(Vuelo.id == asiento.vuelo_id).update(
            {Vuelo.asientos_disponibles: Vuelo.asientos_disponibles + 1, Vuelo.version: Vuelo.version + 1},
            synchronize_session=False,
        )
    return len(asientos)


@app.post(
    "/api/internal/reservas/{reserva_id}/liberar",
    response_model=LiberacionOut,
    summary="Liberar los asientos de una reserva (uso interno: compensación de S4)",
)
def liberar_asientos(reserva_id: int):
    with SessionLocal() as db:
        liberados = _liberar(db, reserva_id)
        db.commit()
        return {"liberados": liberados}


class CancelacionIn(BaseModel):
    vueloId: int


@app.post(
    "/api/internal/reservas/{reserva_id}/cancelar",
    response_model=LiberacionOut,
    responses=errores(404, 409),
    summary="Liberar los asientos de una reserva que se cancela, dentro del corte de venta (uso interno de S5)",
)
def cancelar_asientos_reserva(reserva_id: int, datos: CancelacionIn):
    with SessionLocal() as db:
        # Mismo corte que al reservar: no se cancela ni se libera un asiento a menos de 3 horas de la salida.
        vuelo = _flight_or_404(db, datos.vueloId)
        _validar_ventana_reserva(vuelo)
        liberados = _liberar(db, reserva_id, datos.vueloId)
        db.commit()
        return {"liberados": liberados}


class CambioAsientoIn(BaseModel):
    vueloId: int
    asiento: str = Field(min_length=1, max_length=10)
    version: int | None = Field(default=None, description="Versión del mapa que vio el cliente; si cambió, se rechaza")


@app.post(
    "/api/internal/reservas/{reserva_id}/cambiar-asiento",
    response_model=AsientoAsignadoOut,
    responses=errores(400, 404, 409),
    summary="Mover una reserva a otro asiento libre (uso interno de S4 y compensación de S5)",
)
def cambiar_asiento_reserva(reserva_id: int, datos: CambioAsientoIn):
    codigo = datos.asiento.strip().upper()
    with SessionLocal() as db:
        # Bloquea el vuelo: dos cambios sobre el mismo vuelo no pueden leer el estado viejo a la vez.
        vuelo = _flight_or_404(db, datos.vueloId, bloquear=True)
        _validar_ventana_reserva(vuelo)
        if datos.version is not None and vuelo.version != datos.version:
            raise ApiError(409, "MAPA_DESACTUALIZADO", "El mapa de asientos cambió. Actualice la selección.")
        nuevo = db.query(AsientoVuelo).filter(AsientoVuelo.vuelo_id == datos.vueloId, AsientoVuelo.codigo == codigo).first()
        if nuevo is None:
            raise ApiError(404, "ASIENTO_NO_EXISTE", "El asiento no existe en este vuelo.")
        actual = (
            db.query(AsientoVuelo)
            .filter(AsientoVuelo.vuelo_id == datos.vueloId, AsientoVuelo.reserva_id == reserva_id)
            .first()
        )
        if actual is not None and actual.id == nuevo.id:
            return {"vueloId": datos.vueloId, "asiento": codigo}
        # Primero se libera el actual (la base de datos admite una sola fila por reserva), luego se reclama el nuevo.
        # Si el nuevo está ocupado, se responde 409 y la transacción sin commit deshace la liberación.
        if actual is not None:
            actual.reserva_id = None
            db.flush()
        if not _marcar_si_libre(db, nuevo.id, reserva_id):
            raise ApiError(409, "ASIENTO_OCUPADO", "El asiento ya está ocupado.")
        db.query(Vuelo).filter(Vuelo.id == datos.vueloId).update({Vuelo.version: Vuelo.version + 1}, synchronize_session=False)
        db.commit()
        return {"vueloId": datos.vueloId, "asiento": codigo}
