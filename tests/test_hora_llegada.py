from fastapi.testclient import TestClient

from shared.security import create_token
from vuelos.main import app

vuelos = TestClient(app)
ADMIN = {"Authorization": f"Bearer {create_token('admin@aerovuelo.com', rol='administrador')['token']}"}
BASE = {"origen": "UIO", "destino": "CUE", "fecha": "2031-05-05", "precio": 60, "avionId": 1, "activo": True}


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


def test_factura_xml_incluye_hora_llegada_del_vuelo():
    from datetime import date

    from shared.factura import construir_factura_xml

    xml = construir_factura_xml(
        1,
        "ana@correo.com",
        [45.0],
        date(2031, 1, 1),
        vuelo={"origen": "UIO", "destino": "GYE", "fecha": "2031-05-05", "hora": "08:30", "horaLlegada": "09:25"},
    )
    assert "<horaLlegada>09:25</horaLlegada>" in xml


def test_factura_xml_sin_hora_llegada_no_agrega_la_etiqueta():
    from datetime import date

    from shared.factura import construir_factura_xml

    xml = construir_factura_xml(
        1,
        "ana@correo.com",
        [45.0],
        date(2031, 1, 1),
        vuelo={"origen": "UIO", "destino": "GYE", "fecha": "2031-05-05", "hora": "08:30", "horaLlegada": None},
    )
    assert "horaLlegada" not in xml


def test_factura_xml_trae_los_mismos_datos_que_el_pdf():
    from datetime import date

    from shared.factura import construir_factura_xml

    xml = construir_factura_xml(
        7,
        "Ana Torres",
        [45.0],
        date(2031, 1, 1),
        boletos=[{"pasajero": "Ana Torres", "tipoDocumento": "cedula", "documento": "1710034065", "asiento": "1C", "precio": 45.0}],
        vuelo={"id": 3, "origen": "UIO", "destino": "MAD", "fecha": "2031-05-05", "hora": "22:10", "horaLlegada": "16:20"},
        correo="ana@correo.com",
    )
    assert "<emisor><nombre>AeroVuelo</nombre><descripcion>Sky Booking System</descripcion></emisor>" in xml
    assert "<correo>ana@correo.com</correo>" in xml
    assert "<reserva>7</reserva>" in xml
    assert "<id>3</id><origen>UIO</origen><ciudadOrigen>Quito</ciudadOrigen><destino>MAD</destino><ciudadDestino>Madrid</ciudadDestino>" in xml
    assert "<hora>22:10</hora><horaLlegada>16:20</horaLlegada>" in xml
