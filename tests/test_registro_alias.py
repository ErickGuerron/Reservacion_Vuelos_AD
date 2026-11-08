from fastapi.testclient import TestClient

from usuarios.main import app

client = TestClient(app)


def test_alias_registro_crea_la_cuenta_igual_que_el_endpoint_principal():
    datos = {"nombre": "Alias Registro", "email": "alias-registro@correo.com", "password": "Clave-segura-123"}
    alias = client.post("/api/usuarios/registro", json=datos)
    assert alias.status_code == 201
    assert alias.json()["rol"] == "cliente"
    # Mismo contrato de error: el correo ya existe.
    repetido = client.post("/api/usuarios/registro", json=datos)
    assert repetido.status_code == 409
    assert repetido.json()["codigo"] == "EMAIL_DUPLICADO"
