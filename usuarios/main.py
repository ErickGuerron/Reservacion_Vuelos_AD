"""S1 - User service (port 5001): registration and role administration.

Public:               POST /api/usuarios
Admin (administrador): GET /api/admin/usuarios, PUT /api/admin/usuarios/{id}/rol
"""

from typing import Literal

from fastapi import Depends, FastAPI, status
from pydantic import BaseModel, EmailStr, Field, field_validator

from shared.cors import enable_cors
from shared.db import add_column_if_missing, create_tables, session_factory
from shared.errors import ApiError, errores, register_error_handlers
from shared.models import USUARIO_ROL_DDL, Base, Usuario
from shared.validacion import validar_nombre_persona, validar_password
from shared.security import (
    BCRYPT_MAX_BYTES,
    ROL_ADMIN,
    ROL_CLIENTE,
    current_admin_email,
    es_admin_de_configuracion,
    hash_password,
)

engine, SessionLocal = session_factory("identidad")
create_tables(engine, Base, [Usuario.__table__])
add_column_if_missing(engine, "usuarios", "rol", USUARIO_ROL_DDL)

app = FastAPI(title="S1 - User service", version="1.1.0")
register_error_handlers(app)
enable_cors(app)


class UsuarioIn(BaseModel):
    nombre: str = Field(min_length=1, max_length=100)
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)

    @field_validator("nombre")
    @classmethod
    def _nombre_valido(cls, valor: str) -> str:
        return validar_nombre_persona(valor)

    @field_validator("password")
    @classmethod
    def _limite_bcrypt(cls, valor: str) -> str:
        validar_password(valor)
        if len(valor.encode()) > BCRYPT_MAX_BYTES:
            raise ValueError(f"password no puede superar {BCRYPT_MAX_BYTES} bytes (unos {BCRYPT_MAX_BYTES} caracteres).")
        return valor


class UsuarioOut(BaseModel):
    id: int
    nombre: str
    email: str
    rol: Literal["cliente", "administrador"]


class RolIn(BaseModel):
    rol: Literal["cliente", "administrador"]


def _out(usuario: Usuario) -> dict:
    return {"id": usuario.id, "nombre": usuario.nombre, "email": usuario.email, "rol": usuario.rol}


def _verificar_administrador(db, email: str) -> None:
    """The token says "administrador", but the database is the source of truth for demotions."""
    actual = db.query(Usuario).filter(Usuario.email == email).first()
    if actual is None or actual.rol != ROL_ADMIN:
        raise ApiError(403, "PERMISO_DENEGADO", "Se requiere una cuenta de administrador.")


@app.post(
    "/api/usuarios",
    status_code=status.HTTP_201_CREATED,
    response_model=UsuarioOut,
    responses=errores(400, 409),
    summary="Registrar un usuario (rol cliente)",
)
def registrar_usuario(datos: UsuarioIn):
    email = str(datos.email).lower()
    with SessionLocal() as db:
        if db.query(Usuario).filter(Usuario.email == email).first():
            raise ApiError(409, "EMAIL_DUPLICADO", "El correo electrónico ya está registrado.")
        usuario = Usuario(
            nombre=datos.nombre,
            email=email,
            password_hash=hash_password(datos.password),
            rol=ROL_CLIENTE,
        )
        db.add(usuario)
        db.commit()
        db.refresh(usuario)
        return _out(usuario)


@app.get(
    "/api/admin/usuarios",
    response_model=list[UsuarioOut],
    responses=errores(401, 403),
    summary="Listar usuarios y sus roles (solo administradores)",
)
def listar_usuarios(email: str = Depends(current_admin_email)):
    with SessionLocal() as db:
        _verificar_administrador(db, email)
        return [_out(u) for u in db.query(Usuario).order_by(Usuario.id).all()]


@app.put(
    "/api/admin/usuarios/{usuario_id}/rol",
    response_model=UsuarioOut,
    responses=errores(400, 401, 403, 404, 409),
    summary="Cambiar el rol de un usuario (solo administradores)",
)
def cambiar_rol(usuario_id: int, datos: RolIn, email: str = Depends(current_admin_email)):
    with SessionLocal() as db:
        _verificar_administrador(db, email)
        usuario = db.get(Usuario, usuario_id)
        if usuario is None:
            raise ApiError(404, "USUARIO_NO_EXISTE", "El usuario no existe.")
        if usuario.rol == datos.rol:
            return _out(usuario)
        if datos.rol == ROL_CLIENTE:
            if es_admin_de_configuracion(usuario.email):
                raise ApiError(
                    409,
                    "ADMIN_DE_CONFIGURACION",
                    "Este administrador está definido en ADMIN_EMAILS y no puede degradarse desde la API.",
                )
            if db.query(Usuario).filter(Usuario.rol == ROL_ADMIN).count() <= 1:
                raise ApiError(409, "ULTIMO_ADMINISTRADOR", "No se puede quitar el rol al último administrador.")
        usuario.rol = datos.rol
        db.commit()
        db.refresh(usuario)
        return _out(usuario)
