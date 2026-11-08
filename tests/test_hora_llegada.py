from fastapi.testclient import TestClient

from shared.security import create_token
from vuelos.main import app

vuelos = TestClient(app)
ADMIN = {"Authorization": f"Bearer {create_token('admin@aerovuelo.com', rol='administrador')['token']}"}
BASE = {"origen": "UIO", "destino": "CUE", "fecha": "2031-05-05", "precio": 60, "totalAsientos": 18, "activo": True}


def test_hora_llegada_se_guarda_y_se_publica():
    creado = vuelos.post("/api/admin/vuelos", json={**BASE, "hora": "08:30", "horaLlegada": "10:45"}, headers=ADMIN)
    assert creado.status_code == 201
    assert creado.json()["horaLlegada"] == "10:45"
    publico = vuelos.get(f"/api/vuelos/{creado.json()['id']}")
    assert publico.status_code == 200
    assert publico.json()["horaLlegada"] == "10:45"


def test_hora_llegada_es_opcional():
    creado = vuelos.post("/api/admin/vuelos", json={**BASE, "fecha": "2031-06-06"}, headers=ADMIN)
    assert creado.status_code == 201
    assert creado.json()["horaLlegada"] is None


def test_hora_llegada_con_formato_invalido_devuelve_400():
    respuesta = vuelos.post("/api/admin/vuelos", json={**BASE, "fecha": "2031-07-07", "horaLlegada": "25:00"}, headers=ADMIN)
    assert respuesta.status_code == 400
    assert respuesta.json()["codigo"] == "DATOS_INVALIDOS"
