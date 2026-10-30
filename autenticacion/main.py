"""S2 - Authentication service (port 5002). Issues JWT tokens.

On each successful login the service:
- upgrades legacy PBKDF2 password hashes to bcrypt;
- makes accounts listed in ADMIN_EMAILS administrators (bootstrap);
- copies the stored role into the token's "rol" claim.
"""

from fastapi import FastAPI
from pydantic import BaseModel, Field, field_validator

from shared.cors import enable_cors
from shared.db import add_column_if_missing, create_tables, session_factory
from shared.errors import ApiError, errores, register_error_handlers
from shared.models import USUARIO_ROL_DDL, Base, Usuario
from shared.validacion import validar_email
from shared.security import (
    ROL_ADMIN,
    create_token,
    es_admin_de_configuracion,
    hash_password,
    needs_rehash,
    verify_password,
)

engine, SessionLocal = session_factory("identidad")
create_tables(engine, Base, [Usuario.__table__])
add_column_if_missing(engine, "usuarios", "rol", USUARIO_ROL_DDL)

app = FastAPI(title="S2 - Authentication", version="1.1.0")
register_error_handlers(app)
enable_cors(app)


class LoginIn(BaseModel):
    email: str = Field(min_length=3, max_length=255)
    password: str = Field(min_length=1, max_length=128)

    @field_validator("email")
    @classmethod
    def _email_valido(cls, valor: str) -> str:
        return validar_email(valor)


class TokenOut(BaseModel):
    token: str
    expiraEn: int = Field(description="Segundos de validez del token")
    rol: str = Field(description="cliente o administrador")


@app.post(
    "/api/auth/login",
    response_model=TokenOut,
    responses=errores(400, 401),
    summary="Iniciar sesión y obtener un token JWT",
)
def login(datos: LoginIn):
    email = datos.email.lower()
    with SessionLocal() as db:
        usuario = db.query(Usuario).filter(Usuario.email == email).first()
        if usuario is None or not verify_password(datos.password, usuario.password_hash):
            raise ApiError(401, "CREDENCIALES_INVALIDAS", "Correo o contraseña incorrectos.")
        if needs_rehash(usuario.password_hash):
            usuario.password_hash = hash_password(datos.password)
        if es_admin_de_configuracion(usuario.email):
            usuario.rol = ROL_ADMIN
        db.commit()
        return {**create_token(usuario.email, rol=usuario.rol), "rol": usuario.rol}
