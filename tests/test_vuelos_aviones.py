"""Vuelos con avión: S3 toma la capacidad del avión registrado en S6 (integración real, en proceso).

S3 llama a S6 con httpx.get; aquí esas llamadas se enrutan al TestClient de S6 para usar la base real.
"""

import httpx
import pytest
from fastapi.testclient import TestClient

from aviones.main import app as aviones_app
from shared.security import ROL_ADMIN, create_token
from vuelos import main as vuelos_main
from vuelos.main import app as vuelos_app

# Capturada al importar, antes de que la fixture autouse de conftest la sustituya.
OBTENER_AVION_REAL = vuelos_main.obtener_avion

vuelos = TestClient(vuelos_app)
aviones = TestClient(aviones_app)
ADMIN = {"Authorization": f"Bearer {create_token('admin@aerovuelo.com', rol=ROL_ADMIN)['token']}"}


@pytest.fixture
def s6_real(monkeypatch):
    """S3 consulta a S6 de verdad (misma base de datos de pruebas, sin red)."""
    monkeypatch.setattr(vuelos_main, "obtener_avion", OBTENER_AVION_REAL)

    def _get(url, timeout=None, **_):
        return aviones.get(url.replace(vuelos_main.AVIONES_URL, ""))

    monkeypatch.setattr(vuelos_main.httpx, "get", _get)


def _registrar_avion(nombre: str, capacidad: int) -> int:
    response = aviones.post("/api/admin/aviones", json={"nombre": nombre, "capacidad": capacidad}, headers=ADMIN)
    assert response.status_code == 201, response.text
    return response.json()["id"]


def _vuelo(avion_id: int, **cambios) -> dict:
    return {
        "origen": "UIO",
        "destino": "GYE",
        "fecha": "2030-09-01",
        "hora": "08:00",
        "precio": 55,
        "avionId": avion_id,
        "activo": True,
        **cambios,
    }


def test_el_vuelo_tiene_tantos_asientos_como_la_capacidad_del_avion(s6_real):
    avion_id = _registrar_avion("Integracion 90", 90)

    response = vuelos.post("/api/admin/vuelos", json=_vuelo(avion_id), headers=ADMIN)

    assert response.status_code == 201, response.text
    cuerpo = response.json()
    assert cuerpo["asientosDisponibles"] == 90
    mapa = vuelos.get(f"/api/vuelos/{cuerpo['id']}/asientos").json()
    assert len(mapa["asientos"]) == 90
    assert mapa["asientosLibres"] == 90


def test_avion_inexistente_devuelve_404_y_no_crea_el_vuelo(s6_real):
    antes = len(vuelos.get("/api/admin/vuelos", headers=ADMIN).json())

    response = vuelos.post("/api/admin/vuelos", json=_vuelo(999997), headers=ADMIN)

    assert response.status_code == 404
    assert response.json()["codigo"] == "AVION_NO_EXISTE"
    assert len(vuelos.get("/api/admin/vuelos", headers=ADMIN).json()) == antes


def test_avion_inactivo_no_se_puede_asignar_a_un_vuelo_nuevo(s6_real):
    avion_id = _registrar_avion("Retirado Avion", 18)
    aviones.patch(f"/api/admin/aviones/{avion_id}/estado", json={"activo": False}, headers=ADMIN)

    response = vuelos.post("/api/admin/vuelos", json=_vuelo(avion_id), headers=ADMIN)

    assert response.status_code == 409
    assert response.json()["codigo"] == "AVION_INACTIVO"


def test_si_s6_no_responde_no_se_crea_el_vuelo(monkeypatch):
    monkeypatch.setattr(vuelos_main, "obtener_avion", OBTENER_AVION_REAL)

    def _caido(url, timeout=None, **_):
        raise httpx.ConnectError("sin conexión")

    monkeypatch.setattr(vuelos_main.httpx, "get", _caido)

    response = vuelos.post("/api/admin/vuelos", json=_vuelo(1), headers=ADMIN)

    assert response.status_code == 503
    assert response.json()["codigo"] == "SERVICIO_NO_DISPONIBLE"


def test_crear_vuelo_sin_avion_devuelve_400(s6_real):
    cuerpo = _vuelo(1)
    del cuerpo["avionId"]

    response = vuelos.post("/api/admin/vuelos", json=cuerpo, headers=ADMIN)

    assert response.status_code == 400
    assert response.json()["codigo"] == "DATOS_INVALIDOS"


def test_el_total_de_asientos_ya_no_se_envia_al_crear(s6_real):
    avion_id = _registrar_avion("Sin Total Campo", 18)

    response = vuelos.post("/api/admin/vuelos", json={**_vuelo(avion_id), "totalAsientos": 30}, headers=ADMIN)

    assert response.status_code == 201
    assert response.json()["asientosDisponibles"] == 18  # manda el avión (capacidad 18), no el campo antiguo


def test_editar_vuelo_con_otro_avion_rehace_el_mapa(s6_real):
    avion_pequeno = _registrar_avion("Editar Pequeno", 18)
    avion_grande = _registrar_avion("Editar Grande", 54)
    vuelo_id = vuelos.post("/api/admin/vuelos", json=_vuelo(avion_pequeno), headers=ADMIN).json()["id"]

    response = vuelos.put(f"/api/admin/vuelos/{vuelo_id}", json=_vuelo(avion_grande), headers=ADMIN)

    assert response.status_code == 200
    assert response.json()["totalAsientos"] == 54
    assert response.json()["avionId"] == avion_grande
    assert vuelos.get(f"/api/vuelos/{vuelo_id}/asientos").json()["asientosLibres"] == 54


def test_editar_vuelo_con_reservas_no_cambia_de_avion(s6_real):
    avion_a = _registrar_avion("Con Reservas A", 18)
    avion_b = _registrar_avion("Con Reservas B", 36)
    vuelo_id = vuelos.post("/api/admin/vuelos", json=_vuelo(avion_a), headers=ADMIN).json()["id"]
    # Un asiento tomado de verdad en S3 (la misma llamada que hace S4 al reservar).
    assert vuelos.post(f"/api/internal/vuelos/{vuelo_id}/asientos/reservar", json={"reservaId": 880001}).status_code == 200

    response = vuelos.put(f"/api/admin/vuelos/{vuelo_id}", json=_vuelo(avion_b), headers=ADMIN)

    assert response.status_code == 409
    assert response.json()["codigo"] == "VUELO_CON_RESERVAS"


def test_cambiar_la_capacidad_del_avion_no_altera_los_vuelos_existentes(s6_real):
    avion_id = _registrar_avion("Capacidad Fija", 18)
    vuelo_id = vuelos.post("/api/admin/vuelos", json=_vuelo(avion_id), headers=ADMIN).json()["id"]

    aviones.put(f"/api/admin/aviones/{avion_id}", json={"nombre": "Capacidad Fija", "capacidad": 36}, headers=ADMIN)

    assert vuelos.get(f"/api/vuelos/{vuelo_id}/asientos").json()["asientosLibres"] == 18


def test_los_vuelos_anteriores_no_tienen_avion(s6_real):
    listado = vuelos.get("/api/admin/vuelos", headers=ADMIN).json()

    # Los vuelos sembrados al arrancar son anteriores al registro de aviones.
    assert any(v["avionId"] is None for v in listado)
