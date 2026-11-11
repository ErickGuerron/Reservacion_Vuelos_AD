import httpx
import pytest
from fastapi.testclient import TestClient

from reservas import main as reservas_main
from reservas.main import app
from shared.errors import ApiError
from shared.security import create_token

client = TestClient(app)
AUTH = {"Authorization": f"Bearer {create_token('viajero@correo.com')['token']}"}


@pytest.fixture(autouse=True)
def _asiento_en_vuelos(monkeypatch):
    """Seat holds are answered locally; the real S3 round trip is covered in test_asientos.py."""
    monkeypatch.setattr(
        reservas_main,
        "reservar_lote_s3",
        lambda vuelo_id, items, version=None: {reserva_id: asiento or "1A" for reserva_id, asiento in items},
    )


def test_reserva_sin_token_devuelve_401():
    response = client.post("/api/reservas", json={"vueloId": 1, "pasajero": "Ana Torres"})
    assert response.status_code == 401
    assert response.json()["codigo"] == "TOKEN_REQUERIDO"


def test_reserva_exitosa_con_vuelo_disponible(monkeypatch):
    monkeypatch.setattr(
        reservas_main,
        "obtener_vuelo",
        lambda vuelo_id: {"id": vuelo_id, "asientosDisponibles": 5},
    )
    response = client.post("/api/reservas", json={"vueloId": 7, "pasajero": "Ana Torres"}, headers=AUTH)
    assert response.status_code == 201
    body = response.json()
    assert body["vueloId"] == 7
    assert body["estado"] == "confirmada"


def test_reserva_lote_agrupa_pasajeros_y_guarda_el_precio(monkeypatch):
    monkeypatch.setattr(
        reservas_main,
        "obtener_vuelo",
        lambda vuelo_id: {"id": vuelo_id, "asientosDisponibles": 5, "precio": 89.0},
    )
    response = client.post(
        "/api/reservas/lote",
        json={"vueloId": 7, "reservas": [{"pasajero": "Ana Torres"}, {"pasajero": "Luis Mora"}]},
        headers=AUTH,
    )
    assert response.status_code == 201
    reservas = response.json()
    assert len(reservas) == 2
    lote_ids = {r["loteId"] for r in reservas}
    assert len(lote_ids) == 1
    assert lote_ids == {reservas[0]["id"]}
    assert all(r["precio"] == 89.0 for r in reservas)


def test_reserva_sin_asientos_devuelve_409(monkeypatch):
    monkeypatch.setattr(
        reservas_main,
        "obtener_vuelo",
        lambda vuelo_id: {"id": vuelo_id, "asientosDisponibles": 0},
    )
    response = client.post("/api/reservas", json={"vueloId": 8, "pasajero": "Ana Torres"}, headers=AUTH)
    assert response.status_code == 409
    assert response.json()["codigo"] == "SIN_ASIENTOS"


def test_vuelo_inexistente_devuelve_404_al_reservar(monkeypatch):
    def _no_existe(vuelo_id):
        raise ApiError(404, "VUELO_NO_EXISTE", "The flight does not exist.")

    monkeypatch.setattr(reservas_main, "obtener_vuelo", _no_existe)
    response = client.post("/api/reservas", json={"vueloId": 999, "pasajero": "Ana Torres"}, headers=AUTH)
    assert response.status_code == 404
    assert response.json()["codigo"] == "VUELO_NO_EXISTE"


def test_obtener_vuelo_mapea_404_del_servicio_de_vuelos(monkeypatch):
    request = httpx.Request("GET", "http://vuelos/api/vuelos/3")
    monkeypatch.setattr(httpx, "get", lambda *a, **k: httpx.Response(404, request=request))
    with pytest.raises(ApiError) as exc:
        reservas_main.obtener_vuelo(3)
    assert exc.value.codigo == "VUELO_NO_EXISTE"


def test_obtener_vuelo_devuelve_503_si_el_servicio_no_responde(monkeypatch):
    def _caido(*a, **k):
        raise httpx.ConnectError("connection refused")

    monkeypatch.setattr(httpx, "get", _caido)
    with pytest.raises(ApiError) as exc:
        reservas_main.obtener_vuelo(3)
    assert exc.value.status_code == 503
    assert exc.value.codigo == "SERVICIO_NO_DISPONIBLE"
