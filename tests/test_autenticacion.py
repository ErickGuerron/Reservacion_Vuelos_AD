import jwt
from fastapi.testclient import TestClient

from autenticacion.main import app as auth_app
from usuarios.main import app as usuarios_app

auth = TestClient(auth_app)
usuarios = TestClient(usuarios_app)

PASSWORD = "clave-login-1"


def _registrar(email: str) -> None:
    usuarios.post(
        "/api/usuarios",
        json={"nombre": "Login", "email": email, "password": PASSWORD},
    )


def test_login_correcto_devuelve_token_jwt_valido():
    _registrar("login@correo.com")
    response = auth.post("/api/auth/login", json={"email": "login@correo.com", "password": PASSWORD})
    assert response.status_code == 200
    body = response.json()
    assert body["expiraEn"] == 3600
    claims = jwt.decode(body["token"], "test-secret-with-at-least-32-bytes!!", algorithms=["HS256"])
    assert claims["sub"] == "login@correo.com"


def test_password_incorrecta_devuelve_401():
    _registrar("errada@correo.com")
    response = auth.post("/api/auth/login", json={"email": "errada@correo.com", "password": "otra-clave"})
    assert response.status_code == 401
    assert response.json()["codigo"] == "CREDENCIALES_INVALIDAS"


def test_usuario_inexistente_devuelve_401_sin_revelar_si_existe():
    response = auth.post("/api/auth/login", json={"email": "nadie@correo.com", "password": PASSWORD})
    assert response.status_code == 401
    assert response.json()["codigo"] == "CREDENCIALES_INVALIDAS"
