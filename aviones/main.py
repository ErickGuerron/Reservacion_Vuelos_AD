"""S6 - Registro de aviones (port 5006). Each plane has a name and a capacity: its number of seats.

Admin (role "administrador"): GET /api/admin/aviones, POST /api/admin/aviones,
                              PUT /api/admin/aviones/{id}, PATCH /api/admin/aviones/{id}/estado
Internal (S3):                GET /api/internal/aviones/{id}

Planes are never deleted: a plane that flights use stays in the registry. Deactivating it stops
new flights from using it; changing its capacity only affects flights created afterwards, because
each flight stores its seat map when it is created.
"""

from fastapi import Depends, FastAPI, status
from pydantic import BaseModel, Field, field_validator
from sqlalchemy.exc import IntegrityError

from shared.asientos import validar_total_asientos
from shared.cors import enable_cors
from shared.db import create_tables, session_factory
from shared.errors import ApiError, errores, register_error_handlers
from shared.models import Avion, Base
from shared.security import current_admin_email
from shared.validacion import validar_solo_numero, validar_texto

engine, SessionLocal = session_factory("aviones")
create_tables(engine, Base, [Avion.__table__])

app = FastAPI(title="S6 - Aviones", version="1.0.0")
register_error_handlers(app)
enable_cors(app)


class AvionIn(BaseModel):
    nombre: str = Field(description="Nombre del avión, por ejemplo Airbus A320-200")
    capacidad: int = Field(description="Número de asientos: 18 a 180, múltiplo de 6")

    @field_validator("nombre")
    @classmethod
    def _nombre_valido(cls, valor: str) -> str:
        valor = validar_texto(valor, "nombre", minimo=2, maximo=60)
        # Los nombres de avión se escriben sin ñ (y sin emojis, que validar_texto ya rechaza).
        if "ñ" in valor.lower():
            raise ValueError("El nombre del avión no puede contener la letra ñ.")
        return valor

    @field_validator("capacidad", mode="before")
    @classmethod
    def _capacidad_numerica(cls, valor: object) -> object:
        return validar_solo_numero(valor, "capacidad")

    @field_validator("capacidad")
    @classmethod
    def _capacidad_de_cabina(cls, valor: int) -> int:
        motivo = validar_total_asientos(valor)
        if motivo:
            raise ValueError(motivo)
        return valor


class EstadoAvionIn(BaseModel):
    activo: bool


class AvionOut(BaseModel):
    id: int
    nombre: str
    capacidad: int
    activo: bool


def _out(avion: Avion) -> dict:
    return {"id": avion.id, "nombre": avion.nombre, "capacidad": avion.capacidad, "activo": bool(avion.activo)}


def _avion_or_404(db, avion_id: int) -> Avion:
    avion = db.get(Avion, avion_id)
    if avion is None:
        raise ApiError(404, "AVION_NO_EXISTE", "El avión no existe.")
    return avion


@app.post(
    "/api/admin/aviones",
    status_code=status.HTTP_201_CREATED,
    response_model=AvionOut,
    responses=errores(400, 401, 403, 409),
    summary="Registrar un avión con su nombre y capacidad (solo administradores)",
)
def registrar_avion(datos: AvionIn, _: str = Depends(current_admin_email)):
    with SessionLocal() as db:
        avion = Avion(nombre=datos.nombre, capacidad=datos.capacidad, activo=True)
        db.add(avion)
        try:
            db.commit()
        except IntegrityError:
            # El nombre es único: si otra petición lo registró primero, la restricción decide.
            db.rollback()
            raise ApiError(409, "AVION_DUPLICADO", "Ya existe un avión con ese nombre.")
        db.refresh(avion)
        return _out(avion)


@app.get(
    "/api/admin/aviones",
    response_model=list[AvionOut],
    responses=errores(401, 403),
    summary="Listar los aviones registrados, también los inactivos (solo administradores)",
)
def listar_aviones(_: str = Depends(current_admin_email)):
    with SessionLocal() as db:
        return [_out(a) for a in db.query(Avion).order_by(Avion.id).all()]


@app.put(
    "/api/admin/aviones/{avion_id}",
    response_model=AvionOut,
    responses=errores(400, 401, 403, 404, 409),
    summary="Cambiar nombre o capacidad de un avión (solo administradores)",
)
def editar_avion(avion_id: int, datos: AvionIn, _: str = Depends(current_admin_email)):
    with SessionLocal() as db:
        avion = _avion_or_404(db, avion_id)
        avion.nombre, avion.capacidad = datos.nombre, datos.capacidad
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            raise ApiError(409, "AVION_DUPLICADO", "Ya existe un avión con ese nombre.")
        db.refresh(avion)
        return _out(avion)


@app.patch(
    "/api/admin/aviones/{avion_id}/estado",
    response_model=AvionOut,
    responses=errores(400, 401, 403, 404),
    summary="Activar o desactivar un avión para nuevos vuelos (solo administradores)",
)
def cambiar_estado_avion(avion_id: int, datos: EstadoAvionIn, _: str = Depends(current_admin_email)):
    with SessionLocal() as db:
        avion = _avion_or_404(db, avion_id)
        avion.activo = datos.activo
        db.commit()
        db.refresh(avion)
        return _out(avion)


@app.get(
    "/api/internal/aviones/{avion_id}",
    response_model=AvionOut,
    responses=errores(404),
    summary="Datos de un avión para asignarlo a un vuelo (uso interno de S3)",
)
def consultar_avion(avion_id: int):
    with SessionLocal() as db:
        return _out(_avion_or_404(db, avion_id))
