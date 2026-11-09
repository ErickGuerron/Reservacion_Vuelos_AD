from datetime import date, datetime, timezone

from fastapi.testclient import TestClient

from shared.horarios import franja_de, salida_es_futura
from shared.security import create_token
from vuelos.main import app

vuelos = TestClient(app)
ADMIN = {"Authorization": f"Bearer {create_token('admin@aerovuelo.com', rol='administrador')['token']}"}
BASE = {"origen": "UIO", "destino": "GYE", "fecha": "2031-08-08", "hora": "08:30", "precio": 50, "avionId": 1, "activo": True}


def _crear(**cambios):
    return vuelos.post("/api/admin/vuelos", json={**BASE, **cambios}, headers=ADMIN)


def test_franja_de_la_hora_de_salida():
    assert [franja_de(h) for h in ("00:00", "05:59", "06:00", "11:59", "12:00", "17:59", "18:00", "23:59")] == [
        "madrugada", "madrugada", "manana", "manana", "tarde", "tarde", "noche", "noche",
    ]


def test_salida_futura_usa_la_hora_local_del_origen():
    ahora = datetime(2031, 1, 1, 12, 0, tzinfo=timezone.utc)  # 07:00 en Ecuador
    assert salida_es_futura("UIO", date(2031, 1, 1), "07:30", ahora)
    assert not salida_es_futura("UIO", date(2031, 1, 1), "06:30", ahora)
    assert not salida_es_futura("MAD", date(2031, 1, 1), "13:00", ahora)  # 12:00 UTC en Madrid (UTC+1) ya pasó


def test_crear_vuelo_con_salida_pasada_devuelve_400():
    respuesta = _crear(fecha="2020-01-01")
    assert respuesta.status_code == 400


def test_estimacion_de_ruta_nacional():
    r = vuelos.get("/api/vuelos/estimacion", params={"origen": "UIO", "destino": "GYE", "fecha": "2031-08-08", "hora": "08:30"})
    assert r.status_code == 200
    cuerpo = r.json()
    assert cuerpo["duracionHabitual"] == 55
    assert cuerpo["horaLlegadaSugerida"] == "09:25"
    assert cuerpo["valida"] is None


def test_estimacion_a_madrid_respeta_el_horario_de_verano():
    invierno = vuelos.get("/api/vuelos/estimacion", params={"origen": "UIO", "destino": "MAD", "fecha": "2031-01-10", "hora": "22:10"}).json()
    verano = vuelos.get("/api/vuelos/estimacion", params={"origen": "UIO", "destino": "MAD", "fecha": "2031-07-10", "hora": "22:10"}).json()
    assert invierno["horaLlegadaSugerida"] == "13:55"  # Madrid UTC+1
    assert verano["horaLlegadaSugerida"] == "14:55"  # Madrid UTC+2


def test_estimacion_de_ruta_desconocida_devuelve_404():
    r = vuelos.get("/api/vuelos/estimacion", params={"origen": "UIO", "destino": "CUE", "fecha": "2031-08-08", "hora": "08:30"})
    assert r.status_code == 404


def test_llegada_coherente_con_la_ruta_se_acepta():
    assert _crear(horaLlegada="09:25", fecha="2031-08-09").status_code == 201


def test_llegada_que_no_corresponde_a_la_duracion_habitual_devuelve_400():
    r = _crear(horaLlegada="12:00", fecha="2031-08-10")
    assert r.status_code == 400
    assert "lo habitual es" in r.json()["mensaje"]


def test_llegada_igual_a_la_salida_en_la_misma_zona_devuelve_400():
    assert _crear(horaLlegada="08:30", fecha="2031-08-11").status_code == 400


def test_vuelo_a_madrid_con_llegada_al_dia_siguiente_se_acepta():
    r = _crear(destino="MAD", hora="22:10", horaLlegada="13:55", fecha="2031-01-10")
    assert r.status_code == 201


def test_ruta_desconocida_no_valida_la_duracion():
    assert _crear(destino="CUE", horaLlegada="12:00", fecha="2031-08-12").status_code == 201


def test_editar_tambien_valida_el_horario():
    id_ = _crear(fecha="2031-08-13").json()["id"]
    r = vuelos.put(f"/api/admin/vuelos/{id_}", json={**BASE, "fecha": "2031-08-13", "horaLlegada": "08:30"}, headers=ADMIN)
    assert r.status_code == 400


def test_filtro_por_franja_de_la_hora_de_salida():
    noche = _crear(fecha="2031-08-14", hora="19:00").json()["id"]
    madrugada = _crear(fecha="2031-08-14", hora="05:30").json()["id"]
    ids = lambda franja: {v["id"] for v in vuelos.get("/api/vuelos", params={"origen": "UIO", "destino": "GYE", "franja": franja}).json()}  # noqa: E731
    assert noche in ids("noche") and madrugada not in ids("noche")
    assert madrugada in ids("madrugada") and noche not in ids("madrugada")
    assert vuelos.get("/api/vuelos", params={"franja": "mediodia"}).status_code == 400
