"""Versión del mapa de asientos (control de concurrencia optimista).

Cada cambio de asientos de un vuelo incrementa `version`. Una reserva que llega con una versión
vieja se rechaza completa (409 MAPA_DESACTUALIZADO) y no toma ningún asiento: el cliente recarga
el mapa y conserva solo los asientos que siguen libres.
"""

import uuid

import pytest
from fastapi.testclient import TestClient

from reservas import main as reservas_main
from reservas.main import app as reservas_app
from shared.security import ROL_ADMIN, create_token
from vuelos.main import app as vuelos_app

vuelos = TestClient(vuelos_app)
reservas = TestClient(reservas_app)
ADMIN = {"Authorization": f"Bearer {create_token('admin@aerovuelo.com', rol=ROL_ADMIN)['token']}"}
VUELO = {
    "origen": "uio",
    "destino": "gye",
    "fecha": "2030-07-01",
    "precio": 60,
    "avionId": 1,  # 18 asientos
    "activo": True,
}


def _vuelo() -> int:
    response = vuelos.post("/api/admin/vuelos", json=VUELO, headers=ADMIN)
    assert response.status_code == 201, response.text
    return response.json()["id"]


def _version(vuelo_id: int) -> int:
    return vuelos.get(f"/api/vuelos/{vuelo_id}/asientos").json()["version"]


def _reservar(vuelo_id: int, reserva_id: int, asiento: str | None, version: int | None = None):
    cuerpo = {"reservas": [{"reservaId": reserva_id, "asiento": asiento}]}
    if version is not None:
        cuerpo["version"] = version
    return vuelos.post(f"/api/internal/vuelos/{vuelo_id}/asientos/reservar-lote", json=cuerpo)


def _ids() -> int:
    return uuid.uuid4().int % 10**6 + 10**6  # ids de reserva ficticios, únicos por prueba


def test_el_mapa_expone_la_version_del_vuelo():
    vuelo_id = _vuelo()
    version = _version(vuelo_id)
    assert isinstance(version, int)


def test_cada_reserva_incrementa_la_version():
    vuelo_id = _vuelo()
    antes = _version(vuelo_id)
    assert _reservar(vuelo_id, _ids(), "1A").status_code == 200
    assert _version(vuelo_id) == antes + 1


def test_version_vieja_se_rechaza_sin_tomar_asientos():
    vuelo_id = _vuelo()
    vieja = _version(vuelo_id)
    assert _reservar(vuelo_id, _ids(), "1A").status_code == 200  # otro pasajero cambia el mapa

    response = _reservar(vuelo_id, _ids(), "2B", version=vieja)

    assert response.status_code == 409
    assert response.json()["codigo"] == "MAPA_DESACTUALIZADO"
    mapa = vuelos.get(f"/api/vuelos/{vuelo_id}/asientos").json()
    ocupados = [a["codigo"] for a in mapa["asientos"] if a["ocupado"]]
    assert ocupados == ["1A"]  # 2B quedó libre: la respuesta no tomó nada


def test_version_actual_se_acepta():
    vuelo_id = _vuelo()
    actual = _version(vuelo_id)
    assert _reservar(vuelo_id, _ids(), "1A", version=actual).status_code == 200


def test_sin_version_se_mantiene_el_comportamiento_anterior():
    vuelo_id = _vuelo()
    assert _reservar(vuelo_id, _ids(), "1A").status_code == 200


def test_liberar_una_reserva_incrementa_la_version():
    vuelo_id = _vuelo()
    reserva = _ids()
    assert _reservar(vuelo_id, reserva, "1A").status_code == 200
    antes = _version(vuelo_id)
    assert vuelos.post(f"/api/internal/reservas/{reserva}/liberar").status_code == 200
    assert _version(vuelo_id) == antes + 1


def test_cambiar_asiento_incrementa_la_version():
    vuelo_id = _vuelo()
    reserva = _ids()
    assert _reservar(vuelo_id, reserva, "1A").status_code == 200
    antes = _version(vuelo_id)
    response = vuelos.post(
        f"/api/internal/reservas/{reserva}/cambiar-asiento",
        json={"vueloId": vuelo_id, "asiento": "2C"},
    )
    assert response.status_code == 200
    assert _version(vuelo_id) == antes + 1


def test_s4_reenvia_la_version_que_recibe_del_cliente(monkeypatch):
    capturado = {}

    def s3_simulado(vuelo_id, items, version=None):
        capturado["version"] = version
        return {reserva_id: "1A" for reserva_id, _ in items}

    monkeypatch.setattr(
        reservas_main, "obtener_vuelo", lambda vuelo_id: {"id": vuelo_id, "asientosDisponibles": 5, "precio": 10.0}
    )
    monkeypatch.setattr(reservas_main, "reservar_lote_s3", s3_simulado)
    email = f"version-{uuid.uuid4().hex[:8]}@correo.com"
    cabeceras = {"Authorization": f"Bearer {create_token(email)['token']}"}

    response = reservas.post(
        "/api/reservas",
        json={"vueloId": 1, "pasajero": "Ana Torres", "versionMapa": 7},
        headers=cabeceras,
    )

    assert response.status_code == 201, response.text
    assert capturado["version"] == 7

def test_cambio_de_asiento_con_version_vieja_se_rechaza_sin_moverlo():
    vuelo_id = _vuelo()
    reserva = _ids()
    assert _reservar(vuelo_id, reserva, "1A").status_code == 200
    vieja = _version(vuelo_id)
    assert _reservar(vuelo_id, _ids(), "2B").status_code == 200  # otro pasajero cambia el mapa

    response = vuelos.post(
        f"/api/internal/reservas/{reserva}/cambiar-asiento",
        json={"vueloId": vuelo_id, "asiento": "3C", "version": vieja},
    )

    assert response.status_code == 409
    assert response.json()["codigo"] == "MAPA_DESACTUALIZADO"
    ocupados = [a["codigo"] for a in vuelos.get(f"/api/vuelos/{vuelo_id}/asientos").json()["asientos"] if a["ocupado"]]
    assert "1A" in ocupados and "3C" not in ocupados


def test_cambio_de_asiento_con_version_actual_se_acepta():
    vuelo_id = _vuelo()
    reserva = _ids()
    assert _reservar(vuelo_id, reserva, "1A").status_code == 200
    response = vuelos.post(
        f"/api/internal/reservas/{reserva}/cambiar-asiento",
        json={"vueloId": vuelo_id, "asiento": "3C", "version": _version(vuelo_id)},
    )
    assert response.status_code == 200


def test_s4_reenvia_la_version_al_cambiar_asiento(monkeypatch):
    capturado = {}

    def s3_reserva(vuelo_id, items, version=None):
        return {reserva_id: "1A" for reserva_id, _ in items}

    def s3_cambio(vuelo_id, reserva_id, asiento, version=None):
        capturado["version"] = version
        return asiento

    monkeypatch.setattr(
        reservas_main, "obtener_vuelo", lambda vuelo_id: {"id": vuelo_id, "asientosDisponibles": 5, "precio": 10.0}
    )
    monkeypatch.setattr(reservas_main, "reservar_lote_s3", s3_reserva)
    monkeypatch.setattr(reservas_main, "cambiar_asiento_s3", s3_cambio)
    email = f"version-cambio-{uuid.uuid4().hex[:8]}@correo.com"
    cabeceras = {"Authorization": f"Bearer {create_token(email)['token']}"}
    reserva = reservas.post("/api/reservas", json={"vueloId": 1, "pasajero": "Ana Torres"}, headers=cabeceras).json()

    response = reservas.put(
        f"/api/reservas/{reserva['id']}/asiento",
        json={"asiento": "2C", "versionMapa": 9},
        headers=cabeceras,
    )

    assert response.status_code == 200, response.text
    assert capturado["version"] == 9
