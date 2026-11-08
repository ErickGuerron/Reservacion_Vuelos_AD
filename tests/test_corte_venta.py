"""Corte de venta: no se reserva un vuelo que sale en menos de 3 horas (hora de Ecuador).

La hora actual se simula parchando _ahora_venta, para que las pruebas no dependan del reloj.
"""

from datetime import datetime

import pytest
from fastapi.testclient import TestClient

from shared.security import ROL_ADMIN, create_token
from vuelos import main as vuelos_main
from vuelos.main import ZONA_HORARIA_VENTA, app as vuelos_app

vuelos = TestClient(vuelos_app)
ADMIN = {"Authorization": f"Bearer {create_token('admin@aerovuelo.com', rol=ROL_ADMIN)['token']}"}
# Salida el 1 de junio de 2030 a las 08:00 (hora de Ecuador).
VUELO = {
    "origen": "UIO",
    "destino": "GYE",
    "fecha": "2030-06-01",
    "hora": "08:00",
    "precio": 60,
    "totalAsientos": 18,
    "activo": True,
}


def _ahora(year: int, month: int, day: int, hour: int, minute: int) -> datetime:
    return datetime(year, month, day, hour, minute, tzinfo=ZONA_HORARIA_VENTA)


def _vuelo_publicado() -> int:
    response = vuelos.post("/api/admin/vuelos", json=VUELO, headers=ADMIN)
    assert response.status_code == 201, response.text
    return response.json()["id"]


def _reservar(vuelo_id: int, reserva_id: int):
    return vuelos.post(
        f"/api/internal/vuelos/{vuelo_id}/asientos/reservar-lote",
        json={"reservas": [{"reservaId": reserva_id}]},
    )


@pytest.mark.parametrize(
    "ahora",
    [
        _ahora(2030, 6, 1, 5, 30),  # faltan 2h30: dentro del corte
        _ahora(2030, 6, 1, 7, 59),  # faltan 1 minuto
    ],
)
def test_no_reserva_con_menos_de_3_horas_para_la_salida(monkeypatch, ahora):
    vuelo_id = _vuelo_publicado()
    monkeypatch.setattr(vuelos_main, "_ahora_venta", lambda: ahora)

    response = _reservar(vuelo_id, 990001)

    assert response.status_code == 409
    assert response.json()["codigo"] == "RESERVA_CERRADA"


def test_reserva_exactamente_3_horas_antes_de_la_salida(monkeypatch):
    vuelo_id = _vuelo_publicado()
    monkeypatch.setattr(vuelos_main, "_ahora_venta", lambda: _ahora(2030, 6, 1, 5, 0))

    assert _reservar(vuelo_id, 990002).status_code == 200


def test_reserva_con_mas_margen_que_el_corte(monkeypatch):
    vuelo_id = _vuelo_publicado()
    monkeypatch.setattr(vuelos_main, "_ahora_venta", lambda: _ahora(2030, 5, 31, 20, 0))

    assert _reservar(vuelo_id, 990003).status_code == 200


def test_reserva_individual_rechaza_un_borrador():
    borrador = {**VUELO, "activo": False}
    response = vuelos.post("/api/admin/vuelos", json=borrador, headers=ADMIN)
    vuelo_id = response.json()["id"]

    response = vuelos.post(f"/api/internal/vuelos/{vuelo_id}/asientos/reservar", json={"reservaId": 990005})

    assert response.status_code == 409
    assert response.json()["codigo"] == "VUELO_INACTIVO"


def test_reserva_individual_tambien_respeta_el_corte(monkeypatch):
    vuelo_id = _vuelo_publicado()
    monkeypatch.setattr(vuelos_main, "_ahora_venta", lambda: _ahora(2030, 6, 1, 6, 0))

    response = vuelos.post(f"/api/internal/vuelos/{vuelo_id}/asientos/reservar", json={"reservaId": 990004})

    assert response.status_code == 409
    assert response.json()["codigo"] == "RESERVA_CERRADA"
