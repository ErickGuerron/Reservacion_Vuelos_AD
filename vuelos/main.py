"""S3 - Flight service (port 5003).

Public (clients):      GET /api/vuelos, GET /api/vuelos/{id}, GET /api/vuelos/{id}/asientos
Admin (role "administrador"): POST /api/admin/vuelos
Internal (S4, S5):     POST /api/internal/vuelos/{id}/asientos/reservar,
                       POST /api/internal/reservas/{id}/liberar
"""

from datetime import date

from fastapi import Depends, FastAPI, Query, status
from pydantic import BaseModel, Field, field_validator

from shared.asientos import MAX_ASIENTOS, MIN_ASIENTOS, generar_asientos_para_total, layout_para_total, validar_total_asientos
from shared.cors import enable_cors
from shared.db import add_column_if_missing, create_tables, session_factory
from shared.errors import ApiError, errores, register_error_handlers
from shared.models import VUELO_ACTIVO_DDL, AsientoVuelo, Base, Vuelo
from shared.security import current_admin_email
from shared.validacion import validar_iata, validar_solo_numero

engine, SessionLocal = session_factory("vuelos")
create_tables(engine, Base, [Vuelo.__table__, AsientoVuelo.__table__])
add_column_if_missing(engine, "vuelos", "activo", VUELO_ACTIVO_DDL)

SEED_FLIGHTS = [
    {"origen": "UIO", "destino": "GYE", "fecha": date(2026, 11, 10), "precio": 45.0, "asientos_disponibles": 30},
    {"origen": "UIO", "destino": "GYE", "fecha": date(2026, 11, 12), "precio": 52.5, "asientos_disponibles": 0},
    {"origen": "GYE", "destino": "UIO", "fecha": date(2026, 11, 15), "precio": 48.0, "asientos_disponibles": 12},
    {"origen": "UIO", "destino": "MAD", "fecha": date(2026, 12, 1), "precio": 780.0, "asientos_disponibles": 5},
]

_INTENTOS_ASIENTO_LIBRE = 5


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
    precio: float
    asientosDisponibles: int


class VueloAdminIn(BaseModel):
    origen: str = Field(description="Código IATA de 3 letras")
    destino: str = Field(description="Código IATA de 3 letras")
    fecha: date
    precio: float = Field(gt=0, le=100_000)
    totalAsientos: int = Field(
        ge=MIN_ASIENTOS,
        le=MAX_ASIENTOS,
        description="Total de asientos del avión: múltiplo de 6, filas de 3 + 3 (18 a 180)",
    )
    activo: bool = Field(
        default=False,
        description="Al crear: true publica el vuelo; false lo deja como borrador (valor por defecto)",
    )

    @field_validator("origen", "destino")
    @classmethod
    def _iata(cls, valor: str) -> str:
        return validar_iata(valor)

    @field_validator("precio", "totalAsientos", mode="before")
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
        "precio": vuelo.precio,
        "asientosDisponibles": vuelo.asientos_disponibles,
        "activo": bool(vuelo.activo),
    }


def _flight_or_404(db, vuelo_id: int) -> Vuelo:
    vuelo = db.get(Vuelo, vuelo_id)
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
):
    with SessionLocal() as db:
        query = db.query(Vuelo).filter(Vuelo.activo == True)  # noqa: E712 (SQL Server BIT)
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
        _vuelo_publico(db, vuelo_id)
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
    if datos.fecha < date.today():
        raise ApiError(400, "DATOS_INVALIDOS", "La fecha del vuelo no puede estar en el pasado.")
    motivo = validar_total_asientos(datos.totalAsientos)
    if motivo:
        raise ApiError(400, "DATOS_INVALIDOS", motivo)

    with SessionLocal() as db:
        vuelo = Vuelo(
            origen=origen,
            destino=destino,
            fecha=datos.fecha,
            precio=datos.precio,
            asientos_disponibles=datos.totalAsientos,
            activo=datos.activo,
        )
        db.add(vuelo)
        db.flush()
        db.add_all(AsientoVuelo(vuelo_id=vuelo.id, **datos_asiento) for datos_asiento in layout_para_total(datos.totalAsientos))
        db.commit()
        db.refresh(vuelo)
        return _to_dict(vuelo)


class VueloAdminOut(BaseModel):
    id: int
    origen: str
    destino: str
    fecha: date
    precio: float
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
        "precio": vuelo.precio,
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
    if datos.fecha < date.today():
        raise ApiError(400, "DATOS_INVALIDOS", "La fecha del vuelo no puede estar en el pasado.")
    motivo = validar_total_asientos(datos.totalAsientos)
    if motivo:
        raise ApiError(400, "DATOS_INVALIDOS", motivo)

    with SessionLocal() as db:
        vuelo = _flight_or_404(db, vuelo_id)
        if _ocupados(db, vuelo_id) > 0:
            raise ApiError(409, "VUELO_CON_RESERVAS", "El vuelo tiene reservas y no puede editarse.")
        vuelo.origen, vuelo.destino, vuelo.fecha, vuelo.precio = origen, destino, datos.fecha, datos.precio
        total_actual = db.query(AsientoVuelo).filter(AsientoVuelo.vuelo_id == vuelo_id).count()
        if total_actual != datos.totalAsientos:
            # Sin reservas no hay asientos tomados: se rehace el mapa con el nuevo total.
            db.query(AsientoVuelo).filter(AsientoVuelo.vuelo_id == vuelo_id).delete(synchronize_session=False)
            db.add_all(AsientoVuelo(vuelo_id=vuelo_id, **datos_asiento) for datos_asiento in layout_para_total(datos.totalAsientos))
            vuelo.asientos_disponibles = datos.totalAsientos
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
        .update({Vuelo.asientos_disponibles: Vuelo.asientos_disponibles - 1}, synchronize_session=False)
    )
    if actualizados != 1:
        raise ApiError(409, "SIN_ASIENTOS", "El vuelo no tiene asientos disponibles.")


def _descontar_disponibles(db, vuelo_id: int, cantidad: int) -> None:
    """Descuenta `cantidad` asientos de una vez; falla si no alcanzan (nada queda descontado)."""
    actualizados = (
        db.query(Vuelo)
        .filter(Vuelo.id == vuelo_id, Vuelo.asientos_disponibles >= cantidad)
        .update({Vuelo.asientos_disponibles: Vuelo.asientos_disponibles - cantidad}, synchronize_session=False)
    )
    if actualizados != 1:
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
        _flight_or_404(db, vuelo_id)
        _descontar_disponible(db, vuelo_id)
        asiento = _tomar_asiento(db, vuelo_id, datos.reservaId, codigo)
        db.commit()
        return {"vueloId": vuelo_id, "asiento": asiento}


class ItemLoteIn(BaseModel):
    reservaId: int
    asiento: str | None = Field(default=None, max_length=10, description="Omitir para asignar el primero libre")


class LoteIn(BaseModel):
    reservas: list[ItemLoteIn] = Field(min_length=1, max_length=MAX_ASIENTOS)


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
        _descontar_disponibles(db, vuelo_id, len(datos.reservas))
        asignados = []
        for item in datos.reservas:
            codigo = (item.asiento or "").strip().upper() or None
            # Si cualquier asiento falla, la excepción sale del bloque sin commit: la sesión deshace todo el lote.
            asiento = _tomar_asiento(db, vuelo_id, item.reservaId, codigo)
            asignados.append({"reservaId": item.reservaId, "asiento": asiento})
        db.commit()
        return {"vueloId": vuelo_id, "asientos": asignados}


@app.post(
    "/api/internal/reservas/{reserva_id}/liberar",
    response_model=LiberacionOut,
    summary="Liberar los asientos de una reserva cancelada (uso interno de S5)",
)
def liberar_asientos(reserva_id: int):
    with SessionLocal() as db:
        asientos = db.query(AsientoVuelo).filter(AsientoVuelo.reserva_id == reserva_id).all()
        for asiento in asientos:
            asiento.reserva_id = None
            db.query(Vuelo).filter(Vuelo.id == asiento.vuelo_id).update(
                {Vuelo.asientos_disponibles: Vuelo.asientos_disponibles + 1}, synchronize_session=False
            )
        db.commit()
        return {"liberados": len(asientos)}


class CambioAsientoIn(BaseModel):
    vueloId: int
    asiento: str = Field(min_length=1, max_length=10)


@app.post(
    "/api/internal/reservas/{reserva_id}/cambiar-asiento",
    response_model=AsientoAsignadoOut,
    responses=errores(400, 404, 409),
    summary="Mover una reserva a otro asiento libre (uso interno de S4)",
)
def cambiar_asiento_reserva(reserva_id: int, datos: CambioAsientoIn):
    codigo = datos.asiento.strip().upper()
    with SessionLocal() as db:
        _flight_or_404(db, datos.vueloId)
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
        # Primero se reclama el asiento nuevo. Si está ocupado, se responde 409 y no se libera el actual.
        if not _marcar_si_libre(db, nuevo.id, reserva_id):
            raise ApiError(409, "ASIENTO_OCUPADO", "El asiento ya está ocupado.")
        if actual is not None:
            actual.reserva_id = None
        db.commit()
        return {"vueloId": datos.vueloId, "asiento": codigo}
