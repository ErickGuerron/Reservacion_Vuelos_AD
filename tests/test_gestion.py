from fastapi.testclient import TestClient

from gestion.main import app as gestion_app
from reservas import main as reservas_main
from reservas.main import app as reservas_app
from shared.security import create_token

reservas = TestClient(reservas_app)
gestion = TestClient(gestion_app)


def _auth(email: str) -> dict:
    return {"Authorization": f"Bearer {create_token(email)['token']}"}


def _reservar(email: str, monkeypatch) -> int:
    monkeypatch.setattr(
        reservas_main,
        "obtener_vuelo",
        lambda vuelo_id: {"id": vuelo_id, "asientosDisponibles": 3},
    )
    response = reservas.post("/api/reservas", json={"vueloId": 1, "pasajero": "Pasajero"}, headers=_auth(email))
    assert response.status_code == 201
    return response.json()["id"]


def test_listar_devuelve_solo_las_reservas_del_usuario(monkeypatch):
    _reservar("lista@correo.com", monkeypatch)
    response = gestion.get("/api/reservas", headers=_auth("lista@correo.com"))
    assert response.status_code == 200
    reservas_usuario = response.json()
    assert reservas_usuario
    assert all(r["estado"] in {"confirmada", "cancelada"} for r in reservas_usuario)
    assert gestion.get("/api/reservas", headers=_auth("otro@correo.com")).json() == []


def test_cancelar_reserva_propia(monkeypatch):
    reserva_id = _reservar("cancela@correo.com", monkeypatch)
    response = gestion.delete(f"/api/reservas/{reserva_id}", headers=_auth("cancela@correo.com"))
    assert response.status_code == 200
    assert response.json() == {"id": reserva_id, "estado": "cancelada"}


def test_cancelar_dos_veces_devuelve_409(monkeypatch):
    reserva_id = _reservar("doble@correo.com", monkeypatch)
    gestion.delete(f"/api/reservas/{reserva_id}", headers=_auth("doble@correo.com"))
    response = gestion.delete(f"/api/reservas/{reserva_id}", headers=_auth("doble@correo.com"))
    assert response.status_code == 409
    assert response.json()["codigo"] == "RESERVA_YA_CANCELADA"


def test_cancelar_reserva_ajena_devuelve_404(monkeypatch):
    reserva_id = _reservar("duena@correo.com", monkeypatch)
    response = gestion.delete(f"/api/reservas/{reserva_id}", headers=_auth("intruso@correo.com"))
    assert response.status_code == 404
    assert response.json()["codigo"] == "RESERVA_NO_EXISTE"


def test_listar_sin_token_devuelve_401():
    response = gestion.get("/api/reservas")
    assert response.status_code == 401
