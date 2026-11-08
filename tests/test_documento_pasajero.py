"""Documento (cédula o pasaporte) de cada pasajero: validación, listado y detalle de la factura XML."""

import pytest
from fastapi.testclient import TestClient

from gestion import main as gestion_main
from gestion.main import app as gestion_app
from reservas import main as reservas_main
from reservas.main import app as reservas_app
from shared.security import create_token
from shared.validacion import validar_cedula, validar_documento

reservas = TestClient(reservas_app)
gestion = TestClient(gestion_app)

CEDULA_VALIDA = "1710034065"
CEDULA_VALIDA_2 = "1713175071"


@pytest.fixture(autouse=True)
def _servicios_locales(monkeypatch):
    monkeypatch.setattr(
        reservas_main,
        "reservar_lote_s3",
        lambda vuelo_id, items: {reserva_id: asiento or "1A" for reserva_id, asiento in items},
    )
    monkeypatch.setattr(
        reservas_main,
        "obtener_vuelo",
        lambda vuelo_id: {"id": vuelo_id, "asientosDisponibles": 5, "precio": 45.0},
    )
    monkeypatch.setattr(
        gestion_main,
        "obtener_vuelo_para_factura",
        lambda vuelo_id: {"origen": "UIO", "destino": "GYE", "fecha": "2026-11-10", "hora": "08:30"},
    )


def _auth(email: str) -> dict:
    return {"Authorization": f"Bearer {create_token(email)['token']}"}


def _lote(email: str, items: list[dict]):
    return reservas.post("/api/reservas/lote", json={"vueloId": 1, "reservas": items}, headers=_auth(email))


def test_validar_cedula_acepta_cedulas_reales_y_rechaza_el_resto():
    assert validar_cedula(CEDULA_VALIDA) == CEDULA_VALIDA
    for mala in ["1710034066", "123", "abcdefghij", "9910034065", "1760034065"]:
        with pytest.raises(ValueError):
            validar_cedula(mala)


def test_validar_documento_pasaporte_y_tipo_desconocido():
    assert validar_documento("pasaporte", "ab123456") == ("pasaporte", "AB123456")
    with pytest.raises(ValueError):
        validar_documento("pasaporte", "12")
    with pytest.raises(ValueError):
        validar_documento("licencia", "123456")


def test_lote_guarda_el_documento_y_el_listado_lo_devuelve():
    email = "documento@correo.com"
    response = _lote(
        email,
        [
            {"pasajero": "Ana Torres", "asiento": "1C", "tipoDocumento": "cedula", "documento": CEDULA_VALIDA},
            {"pasajero": "John Smith", "asiento": "3A", "tipoDocumento": "pasaporte", "documento": "ab123456"},
        ],
    )
    assert response.status_code == 201
    listado = gestion.get("/api/reservas", headers=_auth(email)).json()
    assert [(r["tipoDocumento"], r["documento"]) for r in listado] == [("cedula", CEDULA_VALIDA), ("pasaporte", "AB123456")]


def test_cedula_invalida_devuelve_400_y_no_guarda_nada():
    response = _lote("mala@correo.com", [{"pasajero": "Ana Torres", "tipoDocumento": "cedula", "documento": "1710034066"}])
    assert response.status_code == 400
    assert gestion.get("/api/reservas", headers=_auth("mala@correo.com")).json() == []


def test_tipo_y_numero_van_juntos():
    response = _lote("junto@correo.com", [{"pasajero": "Ana Torres", "documento": CEDULA_VALIDA}])
    assert response.status_code == 400


def test_documento_sigue_siendo_opcional_para_clientes_anteriores():
    response = _lote("sindoc@correo.com", [{"pasajero": "Ana Torres", "asiento": "2B"}])
    assert response.status_code == 201
    assert response.json()[0]["documento"] is None


def test_factura_xml_incluye_vuelo_y_boletos_sin_cambiar_los_totales():
    email = "boletos@correo.com"
    lote = _lote(
        email,
        [
            {"pasajero": "Ana Torres", "asiento": "1C", "tipoDocumento": "cedula", "documento": CEDULA_VALIDA},
            {"pasajero": "Luis Mora", "asiento": "3A", "tipoDocumento": "cedula", "documento": CEDULA_VALIDA_2},
        ],
    ).json()[0]["loteId"]
    xml = gestion.get(f"/api/reservas/lote/{lote}/factura", headers=_auth(email)).text
    assert "<subtotal>90.00</subtotal>" in xml
    assert '<iva porcentaje="15">13.50</iva>' in xml
    assert "<total>103.50</total>" in xml
    assert "<origen>UIO</origen><ciudadOrigen>Quito</ciudadOrigen><destino>GYE</destino><ciudadDestino>Guayaquil</ciudadDestino><fecha>2026-11-10</fecha><hora>08:30</hora></vuelo>" in xml
    assert f"<boleto><pasajero>Ana Torres</pasajero><tipoDocumento>cedula</tipoDocumento><documento>{CEDULA_VALIDA}</documento><asiento>1C</asiento><precio>45.00</precio></boleto>" in xml
    assert "<asiento>3A</asiento>" in xml
