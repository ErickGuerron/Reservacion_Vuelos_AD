import pytest
from fastapi.testclient import TestClient
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session

from gestion import main as gestion_main
from gestion.main import app as gestion_app
from reservas import main as reservas_main
from reservas.main import app as reservas_app
from shared.errors import ApiError
from shared.security import create_token

reservas = TestClient(reservas_app)
gestion = TestClient(gestion_app)


@pytest.fixture(autouse=True)
def _asientos_en_vuelos(monkeypatch):
    """Seat calls to S3 are answered locally; the real round trip is covered in test_asientos.py."""
    monkeypatch.setattr(
        reservas_main,
        "reservar_lote_s3",
        lambda vuelo_id, items: {reserva_id: asiento or "1A" for reserva_id, asiento in items},
    )
    monkeypatch.setattr(gestion_main, "cancelar_asientos_s3", lambda vuelo_id, reserva_id: None)
    monkeypatch.setattr(gestion_main, "restaurar_asiento_s3", lambda vuelo_id, reserva_id, asiento: None)


def _auth(email: str) -> dict:
    return {"Authorization": f"Bearer {create_token(email)['token']}"}


def _reservar(email: str, monkeypatch) -> int:
    monkeypatch.setattr(
        reservas_main,
        "obtener_vuelo",
        lambda vuelo_id: {"id": vuelo_id, "asientosDisponibles": 3},
    )
    response = reservas.post("/api/reservas", json={"vueloId": 1, "pasajero": "Pasajero Ruiz"}, headers=_auth(email))
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


def test_cancelar_fuera_del_corte_pide_liberar_el_asiento_con_su_vuelo(monkeypatch):
    reserva_id = _reservar("vuelo-cancela@correo.com", monkeypatch)
    llamadas = []
    monkeypatch.setattr(gestion_main, "cancelar_asientos_s3", lambda vuelo_id, reserva_id: llamadas.append((vuelo_id, reserva_id)))
    gestion.delete(f"/api/reservas/{reserva_id}", headers=_auth("vuelo-cancela@correo.com"))
    assert llamadas == [(1, reserva_id)]


def test_cancelar_dentro_del_corte_devuelve_409_y_la_reserva_sigue_confirmada(monkeypatch):
    reserva_id = _reservar("corte-cancela@correo.com", monkeypatch)

    def rechazo_por_corte(vuelo_id, reserva_id):
        raise ApiError(409, "RESERVA_CERRADA", "La venta de este vuelo cerró 3 horas antes de la salida.")

    monkeypatch.setattr(gestion_main, "cancelar_asientos_s3", rechazo_por_corte)
    response = gestion.delete(f"/api/reservas/{reserva_id}", headers=_auth("corte-cancela@correo.com"))

    assert response.status_code == 409
    assert response.json()["codigo"] == "RESERVA_CERRADA"
    assert gestion.get(f"/api/reservas/{reserva_id}", headers=_auth("corte-cancela@correo.com")).json()["estado"] == "confirmada"


def test_si_falla_guardar_la_cancelacion_se_restaura_el_asiento_en_s3(monkeypatch):
    reserva_id = _reservar("compensa-cancela@correo.com", monkeypatch)
    restaurados = []
    monkeypatch.setattr(
        gestion_main,
        "restaurar_asiento_s3",
        lambda vuelo_id, reserva_id, asiento: restaurados.append((vuelo_id, reserva_id, asiento)),
    )

    def fallo_al_guardar(self):
        raise OperationalError("COMMIT", {}, Exception("conexión perdida"))

    monkeypatch.setattr(Session, "commit", fallo_al_guardar)
    response = gestion.delete(f"/api/reservas/{reserva_id}", headers=_auth("compensa-cancela@correo.com"))

    assert response.status_code == 503
    assert response.json()["codigo"] == "SERVICIO_NO_DISPONIBLE"
    assert restaurados == [(1, reserva_id, "1A")]


def test_cancelar_reserva_ajena_devuelve_404(monkeypatch):
    reserva_id = _reservar("duena@correo.com", monkeypatch)
    response = gestion.delete(f"/api/reservas/{reserva_id}", headers=_auth("intruso@correo.com"))
    assert response.status_code == 404
    assert response.json()["codigo"] == "RESERVA_NO_EXISTE"


def test_consultar_una_reserva_propia(monkeypatch):
    reserva_id = _reservar("consulta@correo.com", monkeypatch)
    response = gestion.get(f"/api/reservas/{reserva_id}", headers=_auth("consulta@correo.com"))
    assert response.status_code == 200
    cuerpo = response.json()
    assert cuerpo["id"] == reserva_id
    assert cuerpo["estado"] == "confirmada"
    assert cuerpo["asiento"] == "1A"


def test_consultar_reserva_ajena_o_inexistente_devuelve_404(monkeypatch):
    reserva_id = _reservar("duena2@correo.com", monkeypatch)
    ajena = gestion.get(f"/api/reservas/{reserva_id}", headers=_auth("intruso2@correo.com"))
    inexistente = gestion.get("/api/reservas/999999", headers=_auth("duena2@correo.com"))
    assert ajena.status_code == 404
    assert inexistente.status_code == 404
    assert ajena.json()["codigo"] == inexistente.json()["codigo"] == "RESERVA_NO_EXISTE"


def _lote_de_dos(email: str, monkeypatch) -> int:
    monkeypatch.setattr(
        reservas_main,
        "obtener_vuelo",
        lambda vuelo_id: {"id": vuelo_id, "asientosDisponibles": 5, "precio": 89.0},
    )
    response = reservas.post(
        "/api/reservas/lote",
        json={"vueloId": 1, "reservas": [{"pasajero": "Ana Torres"}, {"pasajero": "Luis Mora"}]},
        headers=_auth(email),
    )
    assert response.status_code == 201
    return response.json()[0]["loteId"]


def test_factura_xml_del_lote_usa_iva_15_por_ciento(monkeypatch):
    lote_id = _lote_de_dos("factura@correo.com", monkeypatch)
    response = gestion.get(f"/api/reservas/lote/{lote_id}/factura", headers=_auth("factura@correo.com"))
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("application/xml")
    xml = response.text
    assert "<pasajeros>2</pasajeros>" in xml
    assert "<subtotal>178.00</subtotal>" in xml
    assert "<iva porcentaje=\"15\">26.70</iva>" in xml
    assert "<total>204.70</total>" in xml


def test_factura_usa_el_nombre_de_la_cuenta_del_token(monkeypatch):
    lote_id = _lote_de_dos("nombre@correo.com", monkeypatch)
    token = create_token("nombre@correo.com", nombre="Juan Pérez")
    response = gestion.get(
        f"/api/reservas/lote/{lote_id}/factura",
        headers={"Authorization": f"Bearer {token['token']}"},
    )
    assert "<cliente>Juan Pérez</cliente>" in response.text


def test_factura_excluye_reservas_canceladas(monkeypatch):
    monkeypatch.setattr(
        reservas_main,
        "obtener_vuelo",
        lambda vuelo_id: {"id": vuelo_id, "asientosDisponibles": 5, "precio": 89.0},
    )
    creadas = reservas.post(
        "/api/reservas/lote",
        json={"vueloId": 1, "reservas": [{"pasajero": "Ana Torres"}, {"pasajero": "Luis Mora"}]},
        headers=_auth("parcial@correo.com"),
    ).json()
    lote_id = creadas[0]["loteId"]
    gestion.delete(f"/api/reservas/{creadas[1]['id']}", headers=_auth("parcial@correo.com"))
    response = gestion.get(f"/api/reservas/lote/{lote_id}/factura", headers=_auth("parcial@correo.com"))
    assert "<pasajeros>1</pasajeros>" in response.text
    assert "<subtotal>89.00</subtotal>" in response.text


def test_factura_de_lote_ajeno_devuelve_404(monkeypatch):
    lote_id = _lote_de_dos("dueno-factura@correo.com", monkeypatch)
    response = gestion.get(f"/api/reservas/lote/{lote_id}/factura", headers=_auth("otro-factura@correo.com"))
    assert response.status_code == 404
    assert response.json()["codigo"] == "LOTE_NO_EXISTE"


def test_listar_sin_token_devuelve_401():
    response = gestion.get("/api/reservas")
    assert response.status_code == 401
