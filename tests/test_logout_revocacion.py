"""Cierre de sesión (S2) y revocación de tokens al cambiar el rol (S1).

Con base compartida (Supabase) un token revocado deja de servir en cualquier servicio.
Estas pruebas simulan Supabase apuntando la revocación a la base de identidad de pruebas.
"""

import pytest
from fastapi.testclient import TestClient

from autenticacion import main as auth_main
from autenticacion.main import app as auth_app
from gestion.main import app as gestion_app
from shared import tokens
from shared.models import Token
from usuarios.main import app as usuarios_app

usuarios = TestClient(usuarios_app)
auth = TestClient(auth_app)
gestion = TestClient(gestion_app)
PASSWORD = "Clave-segura-123"
ADMIN = "admin@aerovuelo.com"  # listed in ADMIN_EMAILS by tests/conftest.py


@pytest.fixture(autouse=True)
def base_compartida(tmp_path, monkeypatch):
    """Base propia para cada prueba: el login promueve al administrador de configuración, y eso
    no debe alterar el estado que usan las pruebas de roles. Simula Supabase (DB_PROVIDER=postgres)."""
    from sqlalchemy import create_engine
    from sqlalchemy.orm import sessionmaker

    from shared.models import Base
    from usuarios import main as usuarios_main

    engine = create_engine(f"sqlite:///{(tmp_path / 'aislada.db').as_posix()}", connect_args={"check_same_thread": False})
    Base.metadata.create_all(engine)
    sesion = sessionmaker(bind=engine, autoflush=False)
    monkeypatch.setattr(usuarios_main, "SessionLocal", sesion)
    monkeypatch.setattr(auth_main, "SessionLocal", sesion)
    monkeypatch.setattr(tokens, "_session_local", sesion)
    monkeypatch.setenv("DB_PROVIDER", "postgres")


def _cuenta(email: str, rol_admin: bool = False) -> tuple[int, str]:
    registro = usuarios.post("/api/usuarios", json={"nombre": "Cierre Sesion", "email": email, "password": PASSWORD})
    usuario_id = registro.json().get("id")
    if usuario_id is None:  # ya existía
        with auth_main.SessionLocal() as db:
            usuario_id = db.query(auth_main.Usuario).filter(auth_main.Usuario.email == email).one().id
    token = auth.post("/api/auth/login", json={"email": email, "password": PASSWORD}).json()["token"]
    return usuario_id, token


def _estado_en_bd(token: str) -> str:
    import hashlib

    digest = hashlib.sha256(token.encode()).hexdigest()
    with auth_main.SessionLocal() as db:
        return db.query(Token).filter(Token.token == digest).one().estado


def test_logout_marca_el_token_como_revocado_en_la_base():
    _, token = _cuenta("logout@correo.com")
    response = auth.post("/api/auth/logout", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    assert _estado_en_bd(token) == "revocado"


def test_token_revocado_por_logout_no_sirve_en_otro_servicio(base_compartida):
    _, token = _cuenta("logout2@correo.com")
    headers = {"Authorization": f"Bearer {token}"}
    assert gestion.get("/api/reservas", headers=headers).status_code == 200
    auth.post("/api/auth/logout", headers=headers)
    rechazado = gestion.get("/api/reservas", headers=headers)
    assert rechazado.status_code == 401
    assert rechazado.json()["codigo"] == "TOKEN_REVOCADO"


def test_logout_sin_token_devuelve_401():
    assert auth.post("/api/auth/logout").status_code == 401


def test_cambio_de_rol_revoca_los_tokens_del_usuario(base_compartida):
    usuario_id, token_cliente = _cuenta("rol-revoca@correo.com")
    _, token_admin = _cuenta(ADMIN)
    response = usuarios.put(
        f"/api/admin/usuarios/{usuario_id}/rol",
        json={"rol": "administrador"},
        headers={"Authorization": f"Bearer {token_admin}"},
    )
    assert response.status_code == 200
    assert _estado_en_bd(token_cliente) == "revocado"
    rechazado = gestion.get("/api/reservas", headers={"Authorization": f"Bearer {token_cliente}"})
    assert rechazado.status_code == 401
    assert rechazado.json()["codigo"] == "TOKEN_REVOCADO"
