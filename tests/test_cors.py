from fastapi.testclient import TestClient

from autenticacion.main import app as auth_app
from usuarios.main import app as usuarios_app

FRONTEND = "http://localhost:8080"


def _preflight(app, path: str, origin: str):
    return TestClient(app).options(
        path,
        headers={
            "Origin": origin,
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "content-type",
        },
    )


def test_usuarios_permite_el_origen_del_frontend():
    response = _preflight(usuarios_app, "/api/usuarios", FRONTEND)
    assert response.headers["access-control-allow-origin"] == FRONTEND


def test_autenticacion_permite_el_origen_del_frontend():
    response = _preflight(auth_app, "/api/auth/login", FRONTEND)
    assert response.headers["access-control-allow-origin"] == FRONTEND


def test_origen_no_permitido_no_recibe_cabecera_cors():
    response = _preflight(auth_app, "/api/auth/login", "http://sitio-ajeno.example")
    assert "access-control-allow-origin" not in response.headers
