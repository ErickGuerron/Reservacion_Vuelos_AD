"""Los administradores gestionan vuelos pero no reservan: solo las cuentas de cliente pueden reservar."""

from fastapi.testclient import TestClient

from reservas.main import app as reservas_app
from shared.security import ROL_ADMIN, create_token

reservas = TestClient(reservas_app)
ADMIN = {"Authorization": f"Bearer {create_token('admin@aerovuelo.com', rol=ROL_ADMIN)['token']}"}
CLIENTE = {"Authorization": f"Bearer {create_token('reserva-cliente@correo.com')['token']}"}


def test_administrador_no_puede_reservar_un_vuelo():
    response = reservas.post("/api/reservas", json={"vueloId": 1, "pasajero": "Ana Torres"}, headers=ADMIN)
    assert response.status_code == 403
    assert response.json()["codigo"] == "PERMISO_DENEGADO"


def test_administrador_no_puede_reservar_en_lote():
    response = reservas.post(
        "/api/reservas/lote",
        json={"vueloId": 1, "reservas": [{"pasajero": "Ana Torres"}]},
        headers=ADMIN,
    )
    assert response.status_code == 403


def test_administrador_no_puede_cambiar_asiento():
    response = reservas.put("/api/reservas/1/asiento", json={"asiento": "2B"}, headers=ADMIN)
    assert response.status_code == 403


def test_cliente_sigue_pudiendo_intentar_reservar():
    # Sin vuelo real no se confirma la reserva, pero la cuenta de cliente pasa el control de rol (no es 403).
    response = reservas.post("/api/reservas", json={"vueloId": 999999, "pasajero": "Ana Torres"}, headers=CLIENTE)
    assert response.status_code != 403


def test_administrador_no_ve_reservas_aunque_tenga_alguna_de_una_cuenta_anterior():
    from gestion.main import app as gestion_app

    gestion = TestClient(gestion_app)
    assert gestion.get("/api/reservas", headers=ADMIN).status_code == 403
    assert gestion.delete("/api/reservas/1", headers=ADMIN).status_code == 403
