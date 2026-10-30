"""API gateway: routing, forwarding, CORS handling and service switches.

Forwarding is tested with an httpx MockTransport, so no service needs to be running.
"""

import httpx
import pytest
from fastapi.testclient import TestClient

from gateway import estado
from gateway import main as gateway_main
from gateway.main import app
from gateway.rutas import resolver

client = TestClient(app)


@pytest.fixture
def estado_tmp(tmp_path, monkeypatch):
    monkeypatch.setenv("GATEWAY_ESTADO", str(tmp_path / "estado.json"))
    return tmp_path / "estado.json"


def _backend(monkeypatch, handler):
    """Replace the outgoing HTTP client with one that calls `handler` instead of the network."""
    monkeypatch.setattr(gateway_main, "cliente_http", lambda: httpx.AsyncClient(transport=httpx.MockTransport(handler)))


# ----- Tabla de rutas -----


@pytest.mark.parametrize(
    "path, method, servicio",
    [
        ("/api/usuarios", "POST", "usuarios"),
        ("/api/admin/usuarios/3/rol", "PUT", "usuarios"),
        ("/api/auth/login", "POST", "autenticacion"),
        ("/api/vuelos", "GET", "vuelos"),
        ("/api/vuelos/2/asientos", "GET", "vuelos"),
        ("/api/admin/vuelos", "POST", "vuelos"),
        ("/api/reservas", "POST", "reservas"),
        ("/api/reservas", "GET", "gestion"),
        ("/api/reservas/7", "DELETE", "gestion"),
    ],
)
def test_cada_ruta_publica_llega_a_su_servicio(path, method, servicio):
    assert resolver(path, method) == servicio


@pytest.mark.parametrize(
    "path, method",
    [
        ("/api/internal/vuelos/1/asientos/reservar", "POST"),
        ("/api/internal/reservas/1/liberar", "POST"),
        ("/api/reservasx", "GET"),
        ("/api/vuelos_secretos", "GET"),
        ("/api/reservas", "PUT"),
    ],
)
def test_rutas_internas_o_desconocidas_no_se_enrutan(path, method):
    assert resolver(path, method) is None


# ----- Reenvío -----


def test_reenvia_metodo_query_cabeceras_y_cuerpo(monkeypatch, estado_tmp):
    capturada = {}

    def backend(request: httpx.Request) -> httpx.Response:
        capturada.update(method=request.method, url=str(request.url), auth=request.headers.get("authorization"), body=request.content)
        return httpx.Response(201, json={"id": 9}, headers={"content-type": "application/json"})

    _backend(monkeypatch, backend)
    response = client.post(
        "/api/reservas",
        json={"vueloId": 1, "pasajero": "Ana Torres"},
        headers={"Authorization": "Bearer abc"},
    )
    assert response.status_code == 201
    assert response.json() == {"id": 9}
    assert capturada["method"] == "POST"
    assert capturada["url"] == "http://127.0.0.1:5004/api/reservas"
    assert capturada["auth"] == "Bearer abc"
    assert b'"pasajero"' in capturada["body"]


def test_reenvia_la_query_string(monkeypatch, estado_tmp):
    capturada = {}

    def backend(request: httpx.Request) -> httpx.Response:
        capturada["url"] = str(request.url)
        return httpx.Response(200, json=[])

    _backend(monkeypatch, backend)
    client.get("/api/vuelos", params={"origen": "UIO", "fecha": "2026-11-10"})
    assert capturada["url"] == "http://127.0.0.1:5003/api/vuelos?origen=UIO&fecha=2026-11-10"


def test_no_duplica_las_cabeceras_cors_del_servicio(monkeypatch, estado_tmp):
    def backend(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={}, headers={"access-control-allow-origin": "http://sitio-ajeno.example"})

    _backend(monkeypatch, backend)
    response = client.get("/api/vuelos")
    assert response.headers.get("access-control-allow-origin") != "http://sitio-ajeno.example"


def test_preflight_de_flutter_lo_responde_el_gateway(estado_tmp):
    response = client.options(
        "/api/reservas",
        headers={
            "Origin": "http://localhost:54321",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "authorization,content-type",
        },
    )
    assert response.headers["access-control-allow-origin"] == "http://localhost:54321"


def test_ruta_interna_responde_404_sin_llamar_a_ningun_servicio(monkeypatch, estado_tmp):
    def nunca(request):
        raise AssertionError("no debe reenviarse")

    _backend(monkeypatch, nunca)
    response = client.post("/api/internal/reservas/1/liberar")
    assert response.status_code == 404
    assert response.json()["codigo"] == "RUTA_NO_EXISTE"


def test_servicio_caido_responde_503_con_el_contrato_de_error(monkeypatch, estado_tmp):
    def caido(request):
        raise httpx.ConnectError("connection refused")

    _backend(monkeypatch, caido)
    response = client.get("/api/vuelos")
    assert response.status_code == 503
    assert response.json()["codigo"] == "SERVICIO_NO_DISPONIBLE"


# ----- Desactivar y reactivar -----


def test_servicio_desactivado_responde_503_sin_reenviar(monkeypatch, estado_tmp):
    estado.fijar_habilitado("reservas", False)

    def nunca(request):
        raise AssertionError("un servicio desactivado no debe recibir peticiones")

    _backend(monkeypatch, nunca)
    response = client.post("/api/reservas", json={"vueloId": 1, "pasajero": "Ana Torres"}, headers={"Authorization": "Bearer x"})
    assert response.status_code == 503
    assert response.json()["codigo"] == "SERVICIO_DESACTIVADO"


def test_reactivar_restablece_el_enrutado(monkeypatch, estado_tmp):
    estado.fijar_habilitado("vuelos", False)
    estado.fijar_habilitado("vuelos", True)
    _backend(monkeypatch, lambda request: httpx.Response(200, json=[]))
    assert client.get("/api/vuelos").status_code == 200


def test_desactivar_un_servicio_no_afecta_a_los_demas(monkeypatch, estado_tmp):
    estado.fijar_habilitado("usuarios", False)
    _backend(monkeypatch, lambda request: httpx.Response(200, json=[]))
    assert client.get("/api/vuelos").status_code == 200
    assert client.post("/api/usuarios", json={}).status_code == 503


def test_estado_servicios_muestra_habilitado_y_respondiendo(monkeypatch, estado_tmp):
    estado.fijar_habilitado("gestion", False)

    def sin_respuesta(request):
        raise httpx.ConnectError("connection refused")

    _backend(monkeypatch, sin_respuesta)
    servicios = {s["clave"]: s for s in client.get("/api/gateway/servicios").json()}
    assert servicios["gestion"]["habilitado"] is False
    assert servicios["vuelos"]["habilitado"] is True
    assert servicios["vuelos"]["respondiendo"] is False
