"""S1 - User registration service (port 5001)."""

from fastapi import FastAPI, status
from pydantic import BaseModel, EmailStr, Field

from shared.db import create_tables, session_factory
from shared.cors import enable_cors
from shared.errors import ApiError, errores, register_error_handlers
from shared.models import Base, Usuario
from shared.security import hash_password

engine, SessionLocal = session_factory("identidad")
create_tables(engine, Base, [Usuario.__table__])

app = FastAPI(title="S1 - User registration", version="1.0.0")
register_error_handlers(app)
enable_cors(app)


class UsuarioIn(BaseModel):
    nombre: str = Field(min_length=1, max_length=100)
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)


class UsuarioOut(BaseModel):
    id: int
    nombre: str
    email: str


@app.post(
    "/api/usuarios",
    status_code=status.HTTP_201_CREATED,
    response_model=UsuarioOut,
    responses=errores(400, 409),
    summary="Registrar un usuario",
)
def registrar_usuario(datos: UsuarioIn):
    email = str(datos.email).lower()
    with SessionLocal() as db:
        if db.query(Usuario).filter(Usuario.email == email).first():
            raise ApiError(409, "EMAIL_DUPLICADO", "El correo electrónico ya está registrado.")
        usuario = Usuario(nombre=datos.nombre, email=email, password_hash=hash_password(datos.password))
        db.add(usuario)
        db.commit()
        db.refresh(usuario)
        return {"id": usuario.id, "nombre": usuario.nombre, "email": usuario.email}
