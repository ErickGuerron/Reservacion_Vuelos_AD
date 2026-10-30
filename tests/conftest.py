"""Isolate every test run in a temporary directory before services are imported."""

import os
import tempfile

_tmp = tempfile.mkdtemp(prefix="reservas-soa-tests-")
os.environ["IDENTITY_DB"] = os.path.join(_tmp, "identidad.db")
os.environ["FLIGHTS_DB"] = os.path.join(_tmp, "vuelos.db")
os.environ["BOOKINGS_DB"] = os.path.join(_tmp, "reservas.db")
os.environ["JWT_SECRET"] = "test-secret-with-at-least-32-bytes!!"
# Tests always use SQLite, regardless of the developer's .env (SQL Server is verified separately).
os.environ["DB_PROVIDER"] = "sqlite"
# CORS and roles are pinned here so the suite does not depend on the developer's .env.
os.environ["CORS_ORIGINS"] = "http://localhost:8080,http://127.0.0.1:8080,http://localhost:8083,http://127.0.0.1:8083"
os.environ["CORS_ORIGIN_REGEX"] = r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$"
os.environ["ADMIN_EMAILS"] = "admin@aerovuelo.com"
