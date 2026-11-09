"""S6 - Registro de aviones (nombre y capacidad = número de asientos)."""

import pytest
from fastapi.testclient import TestClient

from aviones.main import app as aviones_app
from shared import db
from shared.security import ROL_ADMIN, create_token

aviones = TestClient(aviones_app)
ADMIN = {"Authorization": f"Bearer {create_token('admin@aerovuelo.com', rol=ROL_ADMIN)['token']}"}
CLIENTE = {"Authorization": f"Bearer {create_token('cliente-aviones@correo.com')['token']}"}


def _alta(nombre: str, capacidad: int = 18, **extra):
    return aviones.post("/api/admin/aviones", json={"nombre": nombre, "capacidad": capacidad, **extra}, headers=ADMIN)


def test_admin_registra_un_avion_con_nombre_y_capacidad():
    response = _alta("ATR 72", 72)

    assert response.status_code == 201
    cuerpo = response.json()
    assert cuerpo["nombre"] == "ATR 72"
    assert cuerpo["capacidad"] == 72
    assert cuerpo["activo"] is True
    assert isinstance(cuerpo["id"], int)


def test_cliente_no_puede_registrar_aviones():
    response = aviones.post("/api/admin/aviones", json={"nombre": "Cliente Jet", "capacidad": 18}, headers=CLIENTE)

    assert response.status_code == 403
    assert response.json()["codigo"] == "PERMISO_DENEGADO"


def test_registrar_sin_token_devuelve_401():
    response = aviones.post("/api/admin/aviones", json={"nombre": "Anonimo", "capacidad": 18})

    assert response.status_code == 401


@pytest.mark.parametrize("capacidad", [12, 186, 100, 0])
def test_capacidad_fuera_de_las_reglas_de_cabina_devuelve_400(capacidad):
    response = _alta(f"Cabina {capacidad}", capacidad)

    assert response.status_code == 400
    assert response.json()["codigo"] == "DATOS_INVALIDOS"


def test_nombre_con_simbolos_no_permitidos_devuelve_400():
    response = _alta("Avion ✈ Pro", 18)

    assert response.status_code == 400
    assert response.json()["errores"][0]["campo"] == "nombre"


@pytest.mark.parametrize("nombre", ["Piña Jet", "AÑO 2030", "Avion 😀"])
def test_nombre_con_enie_o_emoji_devuelve_400(nombre):
    response = _alta(nombre, 18)

    assert response.status_code == 400
    assert response.json()["codigo"] == "DATOS_INVALIDOS"
    assert response.json()["errores"][0]["campo"] == "nombre"


def test_nombre_duplicado_devuelve_409():
    assert _alta("Dup Avion", 18).status_code == 201

    response = _alta("Dup Avion", 36)

    assert response.status_code == 409
    assert response.json()["codigo"] == "AVION_DUPLICADO"


def test_listar_aviones_solo_para_administradores():
    _alta("Lista Avion", 24)

    response = aviones.get("/api/admin/aviones", headers=ADMIN)

    assert response.status_code == 200
    assert "Lista Avion" in [a["nombre"] for a in response.json()]
    assert aviones.get("/api/admin/aviones", headers=CLIENTE).status_code == 403


def test_editar_cambia_nombre_y_capacidad():
    avion_id = _alta("Editar Antes", 18).json()["id"]

    response = aviones.put(
        f"/api/admin/aviones/{avion_id}", json={"nombre": "Editar Despues", "capacidad": 48}, headers=ADMIN
    )

    assert response.status_code == 200
    assert response.json() == {"id": avion_id, "nombre": "Editar Despues", "capacidad": 48, "activo": True}


def test_editar_avion_inexistente_devuelve_404():
    response = aviones.put("/api/admin/aviones/999999", json={"nombre": "Nada", "capacidad": 18}, headers=ADMIN)

    assert response.status_code == 404
    assert response.json()["codigo"] == "AVION_NO_EXISTE"


def test_editar_a_un_nombre_ya_usado_devuelve_409():
    _alta("Nombre Ocupado", 18)
    avion_id = _alta("Nombre Libre", 18).json()["id"]

    response = aviones.put(f"/api/admin/aviones/{avion_id}", json={"nombre": "Nombre Ocupado", "capacidad": 18}, headers=ADMIN)

    assert response.status_code == 409
    assert response.json()["codigo"] == "AVION_DUPLICADO"


def test_desactivar_y_volver_a_activar_un_avion():
    avion_id = _alta("Estado Avion", 18).json()["id"]

    apagado = aviones.patch(f"/api/admin/aviones/{avion_id}/estado", json={"activo": False}, headers=ADMIN)
    encendido = aviones.patch(f"/api/admin/aviones/{avion_id}/estado", json={"activo": True}, headers=ADMIN)

    assert apagado.json()["activo"] is False
    assert encendido.json()["activo"] is True


def test_consulta_interna_devuelve_el_avion_sin_token():
    avion_id = _alta("Interno Avion", 90).json()["id"]

    response = aviones.get(f"/api/internal/aviones/{avion_id}")

    assert response.status_code == 200
    assert response.json() == {"id": avion_id, "nombre": "Interno Avion", "capacidad": 90, "activo": True}


def test_consulta_interna_de_avion_inexistente_devuelve_404():
    response = aviones.get("/api/internal/aviones/999998")

    assert response.status_code == 404
    assert response.json()["codigo"] == "AVION_NO_EXISTE"


def test_el_contexto_aviones_es_agnostico_del_motor():
    """Igual que los demás contextos: SQLite por archivo, PostgreSQL por esquema, SQL Server por base."""
    assert db.SQLITE_FILES["aviones"] == ("AVIONES_DB", "aviones.db")
    assert db.SQLSERVER_DATABASES["aviones"] == "ReservasAviones"
    assert db.POSTGRES_SCHEMAS["aviones"] == "aviones"
    assert db.postgres_connect_args("aviones") == {"options": "-csearch_path=aviones"}
