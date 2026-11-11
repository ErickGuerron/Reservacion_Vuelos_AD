"""La reserva no mantiene una transacción abierta mientras S3 toma los asientos.

Antes, S4 insertaba la reserva, llamaba a S3 con la transacción abierta y confirmaba al final.
Con una sola conexión por proceso (Supabase), eso bloqueaba a todas las demás peticiones.
"""

import uuid

import pytest
from fastapi.testclient import TestClient

from reservas import main as reservas_main
from sqlalchemy.orm import Session

from reservas.main import app as reservas_app
from shared.errors import ApiError
from shared.models import Reserva, ReservaAsiento
from shared.security import create_token

client = TestClient(reservas_app)


def _cabeceras():
    email = f"transaccion-{uuid.uuid4().hex[:10]}@correo.com"
    return email, {"Authorization": f"Bearer {create_token(email)['token']}"}


@pytest.fixture
def vuelo_simulado(monkeypatch):
    monkeypatch.setattr(
        reservas_main, "obtener_vuelo", lambda vuelo_id: {"id": vuelo_id, "asientosDisponibles": 5, "precio": 10.0}
    )


def test_la_reserva_queda_guardada_antes_de_llamar_a_s3(monkeypatch, vuelo_simulado):
    visto = {}

    def s3_simulado(vuelo_id, items, version=None):
        # Otra sesión, en otra conexión, ya debe ver la reserva: la transacción se confirmó antes de llamar a S3.
        with reservas_main.SessionLocal() as otra:
            visto["pendientes"] = otra.query(Reserva).filter(Reserva.estado == "pendiente").count()
        return {reserva_id: "1A" for reserva_id, _ in items}

    monkeypatch.setattr(reservas_main, "reservar_lote_s3", s3_simulado)
    email, cabeceras = _cabeceras()
    response = client.post("/api/reservas", json={"vueloId": 1, "pasajero": "Ana Torres"}, headers=cabeceras)

    assert response.status_code == 201, response.text
    assert visto["pendientes"] >= 1
    assert response.json()["estado"] == "confirmada"


def test_si_s3_falla_no_queda_ninguna_reserva_ni_asiento(monkeypatch, vuelo_simulado):
    liberados = []

    def s3_caido(vuelo_id, items, version=None):
        raise ApiError(503, "SERVICIO_NO_DISPONIBLE", "El servicio de vuelos no está disponible.")

    monkeypatch.setattr(reservas_main, "reservar_lote_s3", s3_caido)
    monkeypatch.setattr(reservas_main, "liberar_reservas_s3", lambda ids: liberados.extend(ids))
    email, cabeceras = _cabeceras()
    response = client.post("/api/reservas", json={"vueloId": 1, "pasajero": "Ana Torres"}, headers=cabeceras)

    assert response.status_code == 503
    with reservas_main.SessionLocal() as db:
        assert db.query(Reserva).filter(Reserva.usuario_email == email).count() == 0
    assert liberados  # por si S3 tomó los asientos y la respuesta se perdió (timeout)


def test_si_falla_el_guardado_final_se_liberan_los_asientos(monkeypatch, vuelo_simulado):
    liberados = []

    def s3_ok(vuelo_id, items, version=None):
        return {reserva_id: "1A" for reserva_id, _ in items}

    class _Fallo(Exception):
        pass

    monkeypatch.setattr(reservas_main, "reservar_lote_s3", s3_ok)
    monkeypatch.setattr(reservas_main, "liberar_reservas_s3", lambda ids: liberados.extend(ids))
    _, cabeceras = _cabeceras()
    original_commit = Session.commit

    def commit_roto(self):
        if any(isinstance(obj, ReservaAsiento) for obj in self.new):
            raise _Fallo("db caída")
        return original_commit(self)

    monkeypatch.setattr(Session, "commit", commit_roto)
    with pytest.raises(_Fallo):
        client.post("/api/reservas", json={"vueloId": 1, "pasajero": "Ana Torres"}, headers=cabeceras)
    assert liberados  # S3 ya tomó los asientos: deben devolverse
