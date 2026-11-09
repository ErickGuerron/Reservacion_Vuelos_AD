"""Isolate every test run in a temporary directory before services are imported."""

import os
import tempfile

_tmp = tempfile.mkdtemp(prefix="reservas-soa-tests-")
os.environ["IDENTITY_DB"] = os.path.join(_tmp, "identidad.db")
os.environ["FLIGHTS_DB"] = os.path.join(_tmp, "vuelos.db")
os.environ["BOOKINGS_DB"] = os.path.join(_tmp, "reservas.db")
os.environ["AVIONES_DB"] = os.path.join(_tmp, "aviones.db")
os.environ["JWT_SECRET"] = "test-secret-with-at-least-32-bytes!!"
# Tests always use SQLite, regardless of the developer's .env (SQL Server is verified separately).
os.environ["DB_PROVIDER"] = "sqlite"
# CORS and roles are pinned here so the suite does not depend on the developer's .env.
os.environ["CORS_ORIGINS"] = "http://localhost:8080,http://127.0.0.1:8080,http://localhost:8083,http://127.0.0.1:8083"
os.environ["CORS_ORIGIN_REGEX"] = r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$"
os.environ["ADMIN_EMAILS"] = "admin@aerovuelo.com"

import pytest  # noqa: E402

# Aviones que S3 "conoce" en las pruebas: id -> (capacidad, activo). Ver _aviones_de_prueba.
AVIONES_PRUEBA = {1: (18, True), 2: (24, True), 3: (36, True), 4: (180, True), 5: (18, False), 6: (20, True)}  # 6: capacidad fuera de política (no es múltiplo de 6)


@pytest.fixture(autouse=True)
def _aviones_de_prueba(monkeypatch):
    """Vuelos (S3) consultan a S6 para conocer la capacidad. Las pruebas usan una tabla fija en vez de HTTP.

    Las pruebas de integración con S6 de verdad restauran la función real (tests/test_vuelos_aviones.py).
    """
    from shared.errors import ApiError
    from vuelos import main as vuelos_main

    def obtener_avion(avion_id: int) -> dict:
        if avion_id not in AVIONES_PRUEBA:
            raise ApiError(404, "AVION_NO_EXISTE", "El avión no existe.")
        capacidad, activo = AVIONES_PRUEBA[avion_id]
        return {"id": avion_id, "nombre": f"Avion {avion_id}", "capacidad": capacidad, "activo": activo}

    monkeypatch.setattr(vuelos_main, "obtener_avion", obtener_avion)
