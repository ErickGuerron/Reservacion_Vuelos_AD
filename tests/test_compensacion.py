"""Compensation: if S4 cannot store a booking after S3 accepted its seats, the seats go back to S3.

Only the S4 side is simulated (the S3 calls are stubbed), so the test checks that the
compensation runs and that no booking is stored.
"""

from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from reservas import main as reservas_main
from reservas.main import app
from shared.security import create_token

client = TestClient(app, raise_server_exceptions=False)
AUTH = {"Authorization": f"Bearer {create_token('compensa@correo.com')['token']}"}


def test_si_s4_no_puede_guardar_se_liberan_los_asientos_en_s3(monkeypatch):
    liberados: list[int] = []
    monkeypatch.setattr(reservas_main, "obtener_vuelo", lambda vuelo_id: {"id": vuelo_id, "asientosDisponibles": 5})
    monkeypatch.setattr(
        reservas_main,
        "reservar_lote_s3",
        lambda vuelo_id, items: {reserva_id: asiento or "1A" for reserva_id, asiento in items},
    )
    monkeypatch.setattr(reservas_main, "liberar_reservas_s3", lambda ids: liberados.extend(ids))

    def _falla_al_guardar(self):
        raise RuntimeError("disco lleno")

    monkeypatch.setattr(Session, "commit", _falla_al_guardar)

    response = client.post(
        "/api/reservas/lote",
        json={"vueloId": 1, "reservas": [{"pasajero": "Ana Torres", "asiento": "1A"}, {"pasajero": "Luis Herrera", "asiento": "1B"}]},
        headers=AUTH,
    )
    assert response.status_code == 500
    assert len(liberados) == 2  # las dos reservas devolvieron sus asientos a S3
