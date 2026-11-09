from fastapi.testclient import TestClient

from shared.models import Usuario
from usuarios import main as usuarios_main
from usuarios.main import app

client = TestClient(app)


def test_registro_exitoso_devuelve_201_sin_password():
    response = client.post(
        "/api/usuarios",
        json={"nombre": "Ana", "email": "ana@correo.com", "password": "clave-segura-1"},
    )
    assert response.status_code == 201
    body = response.json()
    assert body["email"] == "ana@correo.com"
    assert body["nombre"] == "Ana"
    assert "password" not in body


def test_email_duplicado_devuelve_409():
    payload = {"nombre": "Dup", "email": "dup@correo.com", "password": "clave-segura-2"}
    client.post("/api/usuarios", json=payload)
    response = client.post("/api/usuarios", json=payload)
    assert response.status_code == 409
    assert response.json()["codigo"] == "EMAIL_DUPLICADO"


def test_registro_concurrente_del_mismo_correo_devuelve_409(monkeypatch):
    hash_original = usuarios_main.hash_password

    def otra_peticion_registra_el_correo_primero(password):
        # Entre la comprobación previa y el INSERT, otra petición registra el mismo correo.
        with usuarios_main.SessionLocal() as otra:
            otra.add(Usuario(nombre="Otra", email="carrera@correo.com", password_hash="x", rol="cliente"))
            otra.commit()
        return hash_original(password)

    monkeypatch.setattr(usuarios_main, "hash_password", otra_peticion_registra_el_correo_primero)
    response = client.post(
        "/api/usuarios",
        json={"nombre": "Carrera", "email": "carrera@correo.com", "password": "clave-segura-5"},
    )
    assert response.status_code == 409
    assert response.json()["codigo"] == "EMAIL_DUPLICADO"


def test_password_corta_indica_el_minimo_de_caracteres():
    response = client.post(
        "/api/usuarios",
        json={"nombre": "Ana", "email": "corta@correo.com", "password": "corta"},
    )
    assert response.status_code == 400
    body = response.json()
    assert body["codigo"] == "DATOS_INVALIDOS"
    assert body["errores"] == [{"campo": "password", "mensaje": "password debe tener al menos 8 caracteres."}]
    assert body["mensaje"] == "password debe tener al menos 8 caracteres."


def test_email_invalido_indica_el_formato_esperado():
    response = client.post(
        "/api/usuarios",
        json={"nombre": "Ana", "email": "no-es-email", "password": "clave-segura-3"},
    )
    assert response.status_code == 400
    assert response.json()["errores"] == [
        {"campo": "email", "mensaje": "email debe ser una dirección válida, por ejemplo nombre@dominio.com."}
    ]


def test_nombre_vacio_indica_que_es_obligatorio():
    response = client.post(
        "/api/usuarios",
        json={"nombre": "", "email": "vacio@correo.com", "password": "clave-segura-4"},
    )
    assert response.status_code == 400
    assert response.json()["errores"] == [{"campo": "nombre", "mensaje": "nombre no puede estar vacío."}]


def test_campo_faltante_indica_que_es_obligatorio():
    response = client.post("/api/usuarios", json={"nombre": "Ana", "email": "falta@correo.com"})
    assert response.status_code == 400
    assert response.json()["errores"] == [{"campo": "password", "mensaje": "password es obligatorio."}]


def test_varios_errores_se_informan_todos_a_la_vez():
    response = client.post(
        "/api/usuarios",
        json={"nombre": "", "email": "no-es-email", "password": "corta"},
    )
    body = response.json()
    campos = {e["campo"] for e in body["errores"]}
    assert campos == {"nombre", "email", "password"}
    assert len(body["errores"]) == 3
