from fastapi.testclient import TestClient

from vuelos.main import app

client = TestClient(app)


def test_busqueda_sin_filtros_devuelve_vuelos_sembrados():
    response = client.get("/api/vuelos")
    assert response.status_code == 200
    vuelos = response.json()
    assert len(vuelos) >= 4
    assert {"id", "origen", "destino", "fecha", "precio", "asientosDisponibles"} <= set(vuelos[0])


def test_busqueda_filtra_por_origen_y_destino():
    response = client.get("/api/vuelos", params={"origen": "uio", "destino": "gye"})
    assert response.status_code == 200
    vuelos = response.json()
    assert vuelos
    assert all(v["origen"] == "UIO" and v["destino"] == "GYE" for v in vuelos)


def test_busqueda_filtra_por_fecha():
    response = client.get("/api/vuelos", params={"fecha": "2026-11-15"})
    assert response.status_code == 200
    assert all(v["fecha"] == "2026-11-15" for v in response.json())


def test_detalle_de_vuelo_existente():
    vuelo_id = client.get("/api/vuelos").json()[0]["id"]
    response = client.get(f"/api/vuelos/{vuelo_id}")
    assert response.status_code == 200
    assert response.json()["id"] == vuelo_id


def test_detalle_de_vuelo_inexistente_devuelve_404():
    response = client.get("/api/vuelos/999999")
    assert response.status_code == 404
    assert response.json()["codigo"] == "VUELO_NO_EXISTE"


def test_fecha_invalida_devuelve_400():
    response = client.get("/api/vuelos", params={"fecha": "no-es-fecha"})
    assert response.status_code == 400
    assert response.json()["errores"] == [
        {"campo": "fecha", "mensaje": "fecha debe ser una fecha con formato AAAA-MM-DD."}
    ]
