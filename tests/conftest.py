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
