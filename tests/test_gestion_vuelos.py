"""Gestión de vuelos por el administrador: editar sin reservas, activar y desactivar.

Un vuelo inactivo no se muestra a los clientes ni acepta reservas; el administrador sí lo ve.
"""

from fastapi.testclient import TestClient

from shared.security import ROL_ADMIN, create_token
from vuelos.main import app as vuelos_app

vuelos = TestClient(vuelos_app)
ADMIN = {"Authorization": f"Bearer {create_token('admin@aerovuelo.com', rol=ROL_ADMIN)['token']}"}
CLIENTE = {"Authorization": f"Bearer {create_token('gestion-cliente@correo.com')['token']}"}
DATOS = {"origen": "UIO", "destino": "GYE", "fecha": "2030-07-01", "precio": 70, "totalAsientos": 18}


def _crear(activo: bool = True) -> int:
    response = vuelos.post("/api/admin/vuelos", json={**DATOS, "activo": activo}, headers=ADMIN)
    assert response.status_code == 201, response.text
    return response.json()["id"]


def test_vuelo_nuevo_queda_como_borrador_si_no_se_indica_lo_contrario():
    response = vuelos.post("/api/admin/vuelos", json=DATOS, headers=ADMIN)
    assert response.status_code == 201
    vuelo_id = response.json()["id"]
    assert vuelo_id not in [v["id"] for v in vuelos.get("/api/vuelos").json()]
    listado = {v["id"]: v for v in vuelos.get("/api/admin/vuelos", headers=ADMIN).json()}
    assert listado[vuelo_id]["activo"] is False


def test_vuelo_creado_publicado_se_muestra_a_los_clientes():
    vuelo_id = _crear(activo=True)
    assert vuelo_id in [v["id"] for v in vuelos.get("/api/vuelos").json()]


def _reservar_asiento(vuelo_id: int, reserva_id: int, asiento: str):
    """Reserva directa en S3 (uso interno), sin pasar por S4."""
    return vuelos.post(
        f"/api/internal/vuelos/{vuelo_id}/asientos/reservar-lote",
        json={"reservas": [{"reservaId": reserva_id, "asiento": asiento}]},
    )


def test_solo_administradores_ven_la_lista_completa():
    assert vuelos.get("/api/admin/vuelos", headers=CLIENTE).status_code == 403
    assert vuelos.get("/api/admin/vuelos", headers=ADMIN).status_code == 200


def test_vuelo_sin_reservas_se_edita_y_rehace_el_mapa():
    vuelo_id = _crear()
    response = vuelos.put(
        f"/api/admin/vuelos/{vuelo_id}",
        json={**DATOS, "origen": "GYE", "destino": "MAD", "precio": 80, "totalAsientos": 24},
        headers=ADMIN,
    )
    assert response.status_code == 200, response.text
    editado = response.json()
    assert editado["origen"] == "GYE" and editado["destino"] == "MAD"
    assert editado["totalAsientos"] == 24
    assert editado["asientosDisponibles"] == 24
    assert editado["editable"] is True
    mapa = vuelos.get(f"/api/vuelos/{vuelo_id}/asientos").json()
    assert len(mapa["asientos"]) == 24


def test_vuelo_con_reservas_no_se_edita():
    vuelo_id = _crear()
    assert _reservar_asiento(vuelo_id, 900001, "1A").status_code == 200
    response = vuelos.put(f"/api/admin/vuelos/{vuelo_id}", json={**DATOS, "precio": 99}, headers=ADMIN)
    assert response.status_code == 409
    assert response.json()["codigo"] == "VUELO_CON_RESERVAS"
    listado = {v["id"]: v for v in vuelos.get("/api/admin/vuelos", headers=ADMIN).json()}
    assert listado[vuelo_id]["editable"] is False
    assert listado[vuelo_id]["asientosOcupados"] == 1


def test_desactivar_oculta_al_cliente_y_activar_lo_devuelve():
    vuelo_id = _crear()
    assert vuelos.patch(f"/api/admin/vuelos/{vuelo_id}/estado", json={"activo": False}, headers=ADMIN).status_code == 200

    assert vuelo_id not in [v["id"] for v in vuelos.get("/api/vuelos").json()]
    detalle = vuelos.get(f"/api/vuelos/{vuelo_id}")
    assert detalle.status_code == 404
    assert detalle.json()["codigo"] == "VUELO_NO_DISPONIBLE"
    assert vuelos.get(f"/api/vuelos/{vuelo_id}/asientos").status_code == 404
    assert vuelo_id in [v["id"] for v in vuelos.get("/api/admin/vuelos", headers=ADMIN).json()]

    assert vuelos.patch(f"/api/admin/vuelos/{vuelo_id}/estado", json={"activo": True}, headers=ADMIN).status_code == 200
    assert vuelo_id in [v["id"] for v in vuelos.get("/api/vuelos").json()]


def test_vuelo_inactivo_no_acepta_reservas():
    vuelo_id = _crear()
    vuelos.patch(f"/api/admin/vuelos/{vuelo_id}/estado", json={"activo": False}, headers=ADMIN)
    response = _reservar_asiento(vuelo_id, 900002, "2B")
    assert response.status_code == 409
    assert response.json()["codigo"] == "VUELO_INACTIVO"
