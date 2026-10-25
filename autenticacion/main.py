"""S2 - Authentication service (port 5002). Issues JWT tokens."""

from fastapi import FastAPI
from pydantic import BaseModel, Field

from shared.db import create_tables, session_factory
from shared.cors import enable_cors
from shared.errors import ApiError, errores, register_error_handlers
from shared.models import Base, Usuario
from shared.security import create_token, verify_password

engine, SessionLocal = session_factory("identidad")
create_tables(engine, Base, [Usuario.__table__])

app = FastAPI(title="S2 - Authentication", version="1.0.0")
register_error_handlers(app)
enable_cors(app)


class LoginIn(BaseModel):
    email: str = Field(min_length=3, max_length=255)
    password: str = Field(min_length=1, max_length=128)


class TokenOut(BaseModel):
    token: str
    expiraEn: int = Field(description="Segundos de validez del token")


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
        return create_token(usuario.email)
