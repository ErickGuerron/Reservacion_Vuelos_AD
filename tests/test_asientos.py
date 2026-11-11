"""Seat selection and flight administration, end to end across S3, S4 and S5.

S4 and S5 call S3 over HTTP. Here those calls are routed in-process to the S3 TestClient,
so the whole flow runs against real databases (SQLite, isolated in conftest).
"""

import pytest
from fastapi.testclient import TestClient

from gestion import main as gestion_main
from gestion.main import app as gestion_app
from reservas import main as reservas_main
from reservas.main import app as reservas_app
from shared.security import ROL_ADMIN, create_token
from vuelos.main import app as vuelos_app

vuelos = TestClient(vuelos_app)
reservas = TestClient(reservas_app)
gestion = TestClient(gestion_app)

ADMIN = {"Authorization": f"Bearer {create_token('admin@aerovuelo.com', rol=ROL_ADMIN)['token']}"}
CLIENTE = {"Authorization": f"Bearer {create_token('asientos-pasajero@correo.com')['token']}"}
OTRO_CLIENTE = {"Authorization": f"Bearer {create_token('asientos-otro@correo.com')['token']}"}
# 18 asientos (mínimo permitido) = 3 filas de 3 + 3 (A-C a un lado del pasillo, D-F al otro).
VUELO_NUEVO = {
    "origen": "uio",
    "destino": "gye",
    "fecha": "2030-06-01",
    "precio": 60,
    "avionId": 1,  # avión de prueba con 18 asientos
    "activo": True,  # publicado: los clientes pueden reservar
}
CODIGOS_18 = [f"{fila}{letra}" for fila in (1, 2, 3) for letra in "ABCDEF"]


@pytest.fixture
def enlace_a_vuelos(monkeypatch):
    """Route S4/S5 calls to S3 in-process: same paths, same JSON bodies, same status codes."""
    base = reservas_main.FLIGHTS_URL

    def _ruta(url: str) -> str:
        return url.replace(base, "")

    def _get(url, **_):
        return vuelos.get(_ruta(url))

    def _post(url, json=None, **_):
        return vuelos.post(_ruta(url), json=json)

    monkeypatch.setattr(reservas_main.httpx, "get", _get)
    monkeypatch.setattr(reservas_main.httpx, "post", _post)
    monkeypatch.setattr(gestion_main.httpx, "post", _post)


def _crear_vuelo_admin(**cambios) -> int:
    response = vuelos.post("/api/admin/vuelos", json={**VUELO_NUEVO, **cambios}, headers=ADMIN)
    assert response.status_code == 201, response.text
    return response.json()["id"]


def _ocupados(vuelo_id: int) -> list[str]:
    mapa = vuelos.get(f"/api/vuelos/{vuelo_id}/asientos").json()
    return [a["codigo"] for a in mapa["asientos"] if a["ocupado"]]


# ----- Administración de vuelos -----


def test_admin_crea_vuelo_con_mapa_de_asientos_y_disponibilidad():
    vuelo_id = _crear_vuelo_admin()
    detalle = vuelos.get(f"/api/vuelos/{vuelo_id}").json()
    assert detalle == {
        "id": vuelo_id,
        "origen": "UIO",
        "destino": "GYE",
        "fecha": "2030-06-01",
        "hora": "08:00",
        "horaLlegada": None,  # campo aditivo: sin hora de llegada cargada
        "precio": 60.0,
        "asientosDisponibles": 18,
    }
    mapa = vuelos.get(f"/api/vuelos/{vuelo_id}/asientos").json()
    assert mapa["filas"] == 3
    assert mapa["columnas"] == ["A", "B", "C", "D", "E", "F"]
    assert mapa["asientosLibres"] == 18
    assert [a["codigo"] for a in mapa["asientos"]] == CODIGOS_18


def test_admin_guarda_la_hora_de_salida_al_crear_y_editar():
    vuelo_id = _crear_vuelo_admin(hora="17:45")
    assert vuelos.get(f"/api/vuelos/{vuelo_id}").json()["hora"] == "17:45"

    edicion = vuelos.put(f"/api/admin/vuelos/{vuelo_id}", json={**VUELO_NUEVO, "hora": "06:05"}, headers=ADMIN)
    assert edicion.status_code == 200, edicion.text
    assert edicion.json()["hora"] == "06:05"
    assert vuelos.get(f"/api/vuelos/{vuelo_id}").json()["hora"] == "06:05"


@pytest.mark.parametrize("hora", ["24:00", "8:30", "12:60", "1230", "", "ab:cd"])
def test_hora_fuera_de_formato_hh_mm_devuelve_400(hora):
    response = vuelos.post("/api/admin/vuelos", json={**VUELO_NUEVO, "hora": hora}, headers=ADMIN)
    assert response.status_code == 400


@pytest.mark.parametrize("avion_id, capacidad", [(1, 18), (2, 24), (4, 180)])
def test_el_vuelo_tiene_los_asientos_de_su_avion(avion_id, capacidad):
    vuelo_id = _crear_vuelo_admin(avionId=avion_id)
    assert vuelos.get(f"/api/vuelos/{vuelo_id}/asientos").json()["asientosLibres"] == capacidad


def test_avion_con_capacidad_fuera_de_politica_devuelve_400():
    response = vuelos.post("/api/admin/vuelos", json={**VUELO_NUEVO, "avionId": 6}, headers=ADMIN)
    assert response.status_code == 400
    assert response.json()["codigo"] == "DATOS_INVALIDOS"


def test_creacion_sin_token_devuelve_401():
    response = vuelos.post("/api/admin/vuelos", json=VUELO_NUEVO)
    assert response.status_code == 401
    assert response.json()["codigo"] == "TOKEN_REQUERIDO"


def test_creacion_con_cuenta_cliente_devuelve_403():
    response = vuelos.post("/api/admin/vuelos", json=VUELO_NUEVO, headers=CLIENTE)
    assert response.status_code == 403
    assert response.json()["codigo"] == "PERMISO_DENEGADO"


def test_creacion_valida_origen_destino_y_fecha():
    mismo_origen = vuelos.post("/api/admin/vuelos", json={**VUELO_NUEVO, "destino": "UIO"}, headers=ADMIN)
    assert mismo_origen.status_code == 400
    assert mismo_origen.json()["mensaje"] == "El origen y el destino deben ser distintos."

    pasado = vuelos.post("/api/admin/vuelos", json={**VUELO_NUEVO, "fecha": "2001-01-01"}, headers=ADMIN)
    assert pasado.status_code == 400

    datos_malos = vuelos.post("/api/admin/vuelos", json={**VUELO_NUEVO, "precio": -1}, headers=ADMIN)
    assert datos_malos.status_code == 400
    assert datos_malos.json()["codigo"] == "DATOS_INVALIDOS"


def test_mapa_de_vuelo_inexistente_devuelve_404():
    response = vuelos.get("/api/vuelos/999999/asientos")
    assert response.status_code == 404
    assert response.json()["codigo"] == "VUELO_NO_EXISTE"


def test_admin_emails_son_de_configuracion():
    from shared.security import es_admin_de_configuracion

    assert es_admin_de_configuracion("ADMIN@aerovuelo.com")
    assert not es_admin_de_configuracion("asientos-pasajero@correo.com")


# ----- Selección de asientos por el cliente -----


def test_cliente_elige_asiento_y_queda_ocupado(enlace_a_vuelos):
    vuelo_id = _crear_vuelo_admin()
    response = reservas.post(
        "/api/reservas",
        json={"vueloId": vuelo_id, "pasajero": "Ana Torres", "asiento": "1b"},
        headers=CLIENTE,
    )
    assert response.status_code == 201
    assert response.json()["asiento"] == "1B"

    mapa = vuelos.get(f"/api/vuelos/{vuelo_id}/asientos").json()
    assert _ocupados(vuelo_id) == ["1B"]
    assert mapa["asientosLibres"] == 17
    assert vuelos.get(f"/api/vuelos/{vuelo_id}").json()["asientosDisponibles"] == 17


def test_asiento_ya_ocupado_devuelve_409_y_no_guarda_la_reserva(enlace_a_vuelos):
    vuelo_id = _crear_vuelo_admin()
    reservas.post("/api/reservas", json={"vueloId": vuelo_id, "pasajero": "Ana Torres", "asiento": "2A"}, headers=CLIENTE)
    response = reservas.post(
        "/api/reservas",
        json={"vueloId": vuelo_id, "pasajero": "Luis Herrera", "asiento": "2A"},
        headers=OTRO_CLIENTE,
    )
    assert response.status_code == 409
    assert response.json()["codigo"] == "ASIENTO_OCUPADO"
    assert [r for r in gestion.get("/api/reservas", headers=OTRO_CLIENTE).json() if r["vueloId"] == vuelo_id] == []
    assert vuelos.get(f"/api/vuelos/{vuelo_id}").json()["asientosDisponibles"] == 17


def test_asiento_inexistente_devuelve_404(enlace_a_vuelos):
    vuelo_id = _crear_vuelo_admin()
    response = reservas.post("/api/reservas", json={"vueloId": vuelo_id, "pasajero": "Ana Torres", "asiento": "99A"}, headers=CLIENTE)
    assert response.status_code == 404
    assert response.json()["codigo"] == "ASIENTO_NO_EXISTE"


def test_sin_asiento_se_asigna_el_primero_libre(enlace_a_vuelos):
    vuelo_id = _crear_vuelo_admin()
    reservas.post("/api/reservas", json={"vueloId": vuelo_id, "pasajero": "Ana Torres", "asiento": "1A"}, headers=CLIENTE)
    response = reservas.post("/api/reservas", json={"vueloId": vuelo_id, "pasajero": "Luis Herrera"}, headers=OTRO_CLIENTE)
    assert response.status_code == 201
    assert response.json()["asiento"] == "1B"


def test_vuelo_lleno_devuelve_409_sin_asientos(enlace_a_vuelos):
    vuelo_id = _crear_vuelo_admin()
    for i in range(18):
        assert reservas.post("/api/reservas", json={"vueloId": vuelo_id, "pasajero": f"Pasajero Ruiz{chr(65 + i)}"}, headers=CLIENTE).status_code == 201
    response = reservas.post("/api/reservas", json={"vueloId": vuelo_id, "pasajero": "Luis Herrera"}, headers=OTRO_CLIENTE)
    assert response.status_code == 409
    assert response.json()["codigo"] == "SIN_ASIENTOS"


def test_cancelar_libera_el_asiento_para_otro_pasajero(enlace_a_vuelos):
    vuelo_id = _crear_vuelo_admin()
    reserva = reservas.post(
        "/api/reservas", json={"vueloId": vuelo_id, "pasajero": "Ana Torres", "asiento": "1A"}, headers=CLIENTE
    ).json()
    assert gestion.get("/api/reservas", headers=CLIENTE).json()[-1]["asiento"] == "1A"

    assert gestion.delete(f"/api/reservas/{reserva['id']}", headers=CLIENTE).status_code == 200
    assert vuelos.get(f"/api/vuelos/{vuelo_id}").json()["asientosDisponibles"] == 18

    siguiente = reservas.post(
        "/api/reservas", json={"vueloId": vuelo_id, "pasajero": "Luis Herrera", "asiento": "1A"}, headers=OTRO_CLIENTE
    )
    assert siguiente.status_code == 201


# ----- Cambio de asiento de una reserva propia -----


def test_cliente_cambia_su_asiento_y_libera_el_anterior(enlace_a_vuelos):
    vuelo_id = _crear_vuelo_admin()
    reserva = reservas.post(
        "/api/reservas", json={"vueloId": vuelo_id, "pasajero": "Ana Torres", "asiento": "1A"}, headers=CLIENTE
    ).json()

    response = reservas.put(f"/api/reservas/{reserva['id']}/asiento", json={"asiento": "2c"}, headers=CLIENTE)
    assert response.status_code == 200
    assert response.json()["asiento"] == "2C"
    assert _ocupados(vuelo_id) == ["2C"]
    assert vuelos.get(f"/api/vuelos/{vuelo_id}").json()["asientosDisponibles"] == 17


def test_cambio_a_asiento_ocupado_devuelve_409_y_conserva_el_anterior(enlace_a_vuelos):
    vuelo_id = _crear_vuelo_admin()
    mia = reservas.post(
        "/api/reservas", json={"vueloId": vuelo_id, "pasajero": "Ana Torres", "asiento": "1A"}, headers=CLIENTE
    ).json()
    reservas.post("/api/reservas", json={"vueloId": vuelo_id, "pasajero": "Luis Herrera", "asiento": "2A"}, headers=OTRO_CLIENTE)

    response = reservas.put(f"/api/reservas/{mia['id']}/asiento", json={"asiento": "2A"}, headers=CLIENTE)
    assert response.status_code == 409
    assert response.json()["codigo"] == "ASIENTO_OCUPADO"
    assert _ocupados(vuelo_id) == ["1A", "2A"]


def test_cambio_de_reserva_ajena_devuelve_404(enlace_a_vuelos):
    vuelo_id = _crear_vuelo_admin()
    reserva = reservas.post(
        "/api/reservas", json={"vueloId": vuelo_id, "pasajero": "Ana Torres", "asiento": "1A"}, headers=CLIENTE
    ).json()

    response = reservas.put(f"/api/reservas/{reserva['id']}/asiento", json={"asiento": "2B"}, headers=OTRO_CLIENTE)
    assert response.status_code == 404
    assert _ocupados(vuelo_id) == ["1A"]


def test_cambio_a_asiento_inexistente_devuelve_404_y_conserva_el_anterior(enlace_a_vuelos):
    vuelo_id = _crear_vuelo_admin()
    reserva = reservas.post(
        "/api/reservas", json={"vueloId": vuelo_id, "pasajero": "Ana Torres", "asiento": "1A"}, headers=CLIENTE
    ).json()

    response = reservas.put(f"/api/reservas/{reserva['id']}/asiento", json={"asiento": "99A"}, headers=CLIENTE)
    assert response.status_code == 404
    assert _ocupados(vuelo_id) == ["1A"]


def test_reserva_sin_servicio_de_vuelos_no_queda_guardada(monkeypatch):
    import httpx

    def _caido(*a, **k):
        raise httpx.ConnectError("connection refused")

    monkeypatch.setattr(reservas_main, "obtener_vuelo", lambda vuelo_id: {"id": vuelo_id, "asientosDisponibles": 3})
    monkeypatch.setattr(reservas_main.httpx, "post", _caido)
    before = len(gestion.get("/api/reservas", headers=OTRO_CLIENTE).json())
    response = reservas.post("/api/reservas", json={"vueloId": 1, "pasajero": "Ana Torres"}, headers=OTRO_CLIENTE)
    assert response.status_code == 503
    assert len(gestion.get("/api/reservas", headers=OTRO_CLIENTE).json()) == before


def test_vuelos_sembrados_tienen_mapa_de_asientos():
    vuelos_listados = vuelos.get("/api/vuelos").json()
    for vuelo in vuelos_listados:
        mapa = vuelos.get(f"/api/vuelos/{vuelo['id']}/asientos").json()
        assert mapa["asientosLibres"] == vuelo["asientosDisponibles"]


# ----- Reserva de varios asientos: todo o nada -----


def test_lote_reserva_todos_los_asientos_y_descuenta_el_cupo(enlace_a_vuelos):
    vuelo_id = _crear_vuelo_admin()
    response = reservas.post(
        "/api/reservas/lote",
        json={
            "vueloId": vuelo_id,
            "reservas": [
                {"pasajero": "Ana Torres", "asiento": "1A"},
                {"pasajero": "Luis Herrera", "asiento": "1B"},
                {"pasajero": "Rosa Paredes", "asiento": "1C"},
            ],
        },
        headers=CLIENTE,
    )
    assert response.status_code == 201, response.text
    assert [r["asiento"] for r in response.json()] == ["1A", "1B", "1C"]
    assert _ocupados(vuelo_id) == ["1A", "1B", "1C"]
    assert vuelos.get(f"/api/vuelos/{vuelo_id}").json()["asientosDisponibles"] == 15


def test_lote_con_un_asiento_ocupado_no_guarda_ninguna_reserva(enlace_a_vuelos):
    vuelo_id = _crear_vuelo_admin()
    reservas.post("/api/reservas", json={"vueloId": vuelo_id, "pasajero": "Otro Cliente", "asiento": "2B"}, headers=OTRO_CLIENTE)
    antes = len([r for r in gestion.get("/api/reservas", headers=CLIENTE).json() if r["vueloId"] == vuelo_id])

    response = reservas.post(
        "/api/reservas/lote",
        json={
            "vueloId": vuelo_id,
            "reservas": [{"pasajero": "Ana Torres", "asiento": "1D"}, {"pasajero": "Luis Herrera", "asiento": "2B"}],
        },
        headers=CLIENTE,
    )
    assert response.status_code == 409
    assert response.json()["codigo"] == "ASIENTO_OCUPADO"
    assert "2B" in response.json()["mensaje"]
    assert _ocupados(vuelo_id) == ["2B"]  # 1D no quedó tomado
    assert vuelos.get(f"/api/vuelos/{vuelo_id}").json()["asientosDisponibles"] == 17
    despues = len([r for r in gestion.get("/api/reservas", headers=CLIENTE).json() if r["vueloId"] == vuelo_id])
    assert despues == antes


def test_lote_con_el_mismo_asiento_dos_veces_falla_completo(enlace_a_vuelos):
    vuelo_id = _crear_vuelo_admin()
    response = reservas.post(
        "/api/reservas/lote",
        json={"vueloId": vuelo_id, "reservas": [{"pasajero": "Ana Torres", "asiento": "3A"}, {"pasajero": "Luis Herrera", "asiento": "3a"}]},
        headers=CLIENTE,
    )
    assert response.status_code == 409
    assert _ocupados(vuelo_id) == []
    assert vuelos.get(f"/api/vuelos/{vuelo_id}").json()["asientosDisponibles"] == 18


def test_lote_mayor_que_el_cupo_no_descuenta_nada(enlace_a_vuelos):
    vuelo_id = _crear_vuelo_admin()
    reservas_grandes = [{"pasajero": f"Pasajero Ruiz{chr(65 + i)}"} for i in range(19)]
    response = reservas.post("/api/reservas/lote", json={"vueloId": vuelo_id, "reservas": reservas_grandes}, headers=CLIENTE)
    assert response.status_code == 409
    assert response.json()["codigo"] == "SIN_ASIENTOS"
    assert vuelos.get(f"/api/vuelos/{vuelo_id}").json()["asientosDisponibles"] == 18


def test_lote_pide_un_token_valido(enlace_a_vuelos):
    vuelo_id = _crear_vuelo_admin()
    response = reservas.post("/api/reservas/lote", json={"vueloId": vuelo_id, "reservas": [{"pasajero": "Ana Torres"}]})
    assert response.status_code == 401


def test_una_reserva_no_puede_tener_dos_asientos_a_la_vez(enlace_a_vuelos):
    from sqlalchemy.exc import IntegrityError

    from shared.models import AsientoVuelo
    from vuelos import main as vuelos_main

    vuelo_id = _crear_vuelo_admin()
    reserva = reservas.post(
        "/api/reservas", json={"vueloId": vuelo_id, "pasajero": "Ana Torres", "asiento": "1A"}, headers=CLIENTE
    ).json()

    with vuelos_main.SessionLocal() as db:
        otro = db.query(AsientoVuelo).filter(AsientoVuelo.vuelo_id == vuelo_id, AsientoVuelo.codigo == "1B").one()
        otro.reserva_id = reserva["id"]
        with pytest.raises(IntegrityError):
            db.commit()
        db.rollback()
    assert _ocupados(vuelo_id) == ["1A"]


def test_cambio_de_asiento_que_falla_no_mueve_la_reserva(enlace_a_vuelos):
    vuelo_id = _crear_vuelo_admin()
    reserva = reservas.post(
        "/api/reservas", json={"vueloId": vuelo_id, "pasajero": "Ana Torres", "asiento": "1A"}, headers=CLIENTE
    ).json()
    reservas.post("/api/reservas", json={"vueloId": vuelo_id, "pasajero": "Luis Herrera", "asiento": "2A"}, headers=OTRO_CLIENTE)
    reservas.put(f"/api/reservas/{reserva['id']}/asiento", json={"asiento": "2A"}, headers=CLIENTE)
    assert _ocupados(vuelo_id) == ["1A", "2A"]
    assert gestion.get("/api/reservas", headers=CLIENTE).json()[-1]["asiento"] == "1A"
