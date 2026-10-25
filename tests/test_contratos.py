import pytest
from fastapi.testclient import TestClient

from autenticacion.main import app as auth_app
from gestion.main import app as gestion_app
from reservas.main import app as reservas_app
from usuarios.main import app as usuarios_app
from vuelos.main import app as vuelos_app

APPS = [usuarios_app, auth_app, vuelos_app, reservas_app, gestion_app]


@pytest.mark.parametrize("app", APPS)
def test_contrato_publica_400_con_error_uniforme_y_no_422(app):
    contrato = TestClient(app).get("/openapi.json").json()
    for operaciones in contrato["paths"].values():
        for operacion in operaciones.values():
            respuestas = operacion["responses"]
            assert "422" not in respuestas
            for codigo, respuesta in respuestas.items():
                if codigo.startswith(("4", "5")):
                    esquema = respuesta["content"]["application/json"]["schema"]["$ref"]
                    assert esquema.endswith("/ErrorOut")
    assert "ErrorOut" in contrato["components"]["schemas"]


def test_contrato_de_reserva_declara_todos_sus_errores():
    contrato = TestClient(reservas_app).get("/openapi.json").json()
    respuestas = contrato["paths"]["/api/reservas"]["post"]["responses"]
    assert set(respuestas) == {"201", "400", "401", "404", "409", "503"}
