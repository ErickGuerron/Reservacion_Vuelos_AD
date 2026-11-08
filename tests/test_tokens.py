import hashlib
import os

from fastapi.testclient import TestClient

from autenticacion import main as auth_main
from autenticacion.main import app as auth_app
from shared.models import Token
from usuarios.main import app as usuarios_app

usuarios = TestClient(usuarios_app)
auth = TestClient(auth_app)


def test_el_token_del_login_lleva_el_nombre_de_la_cuenta():
    import jwt

    from shared.security import ALGORITHM

    email = "nombre-claim@correo.com"
    usuarios.post("/api/usuarios", json={"nombre": "Ana Torres", "email": email, "password": "Clave-segura-123"})
    token = auth.post("/api/auth/login", json={"email": email, "password": "Clave-segura-123"}).json()["token"]
    claims = jwt.decode(token, os.environ["JWT_SECRET"], algorithms=[ALGORITHM])
    assert claims["nombre"] == "Ana Torres"


def test_login_guarda_el_hash_del_token_con_expiracion_y_estado_activo():
    email = "tokens@correo.com"
    registro = usuarios.post(
        "/api/usuarios",
        json={"nombre": "Token Prueba", "email": email, "password": "Clave-segura-123"},
    )
    assert registro.status_code == 201
    login = auth.post("/api/auth/login", json={"email": email, "password": "Clave-segura-123"})
    assert login.status_code == 200
    token = login.json()["token"]

    with auth_main.SessionLocal() as db:
        filas = db.query(Token).filter(Token.usuario_id == registro.json()["id"]).all()
        assert len(filas) == 1
        fila = filas[0]
        # Solo el hash se guarda: una copia de la base de datos no contiene tokens utilizables.
        assert fila.token == hashlib.sha256(token.encode()).hexdigest()
        assert token not in fila.token
        assert fila.estado == "activo"
        assert fila.expiracion is not None
