"""Database selection: SQLite or SQL Server, chosen with DB_PROVIDER.

Each bounded context owns one database:
- identidad: S1 and S2 (users and credentials)
- vuelos: S3 (flights)
- reservas: S4 and S5 (reservations)
"""

import os
from pathlib import Path
from urllib.parse import quote_plus

from sqlalchemy import create_engine
from sqlalchemy.exc import DatabaseError
from sqlalchemy.orm import sessionmaker

from shared import config  # noqa: F401  loads .env before settings are read

SQLITE_FILES = {
    "identidad": ("IDENTITY_DB", "identidad.db"),
    "vuelos": ("FLIGHTS_DB", "vuelos.db"),
    "reservas": ("BOOKINGS_DB", "reservas.db"),
}

SQLSERVER_DATABASES = {
    "identidad": "ReservasIdentidad",
    "vuelos": "ReservasVuelos",
    "reservas": "ReservasReservas",
}


def _provider() -> str:
    provider = os.getenv("DB_PROVIDER", "sqlite").strip().lower()
    if provider not in {"sqlite", "sqlserver"}:
        raise ValueError(f"DB_PROVIDER must be 'sqlite' or 'sqlserver', got '{provider}'.")
    return provider


def database_url(name: str) -> str:
    """Return the SQLAlchemy URL for the named context, using the configured provider."""
    if _provider() == "sqlite":
        env_var, default_file = SQLITE_FILES[name]
        path = Path(os.getenv(env_var, os.path.join("data", default_file))).resolve()
        return f"sqlite:///{path.as_posix()}"
    return _sqlserver_url(SQLSERVER_DATABASES[name])


def _sqlserver_url(database: str) -> str:
    server = os.getenv("SQLSERVER_SERVER", "localhost")
    driver = os.getenv("SQLSERVER_DRIVER", "ODBC Driver 18 for SQL Server")
    parts = [
        f"DRIVER={{{driver}}}",
        f"SERVER={server}",
        f"DATABASE={database}",
        "TrustServerCertificate=yes",  # local development certificates
    ]
    user = os.getenv("SQLSERVER_USER")
    if user:
        password = os.getenv("SQLSERVER_PASSWORD", "").replace("}", "}}")
        parts += [f"UID={user}", "PWD={" + password + "}"]
    else:
        parts.append("Trusted_Connection=yes")
    return "mssql+pyodbc:///?odbc_connect=" + quote_plus(";".join(parts))


def _create_sqlserver_database_if_missing(database: str) -> None:
    """SQL Server does not create databases on connect, so create the context's database once."""
    master = create_engine(_sqlserver_url("master"), isolation_level="AUTOCOMMIT")
    try:
        with master.connect() as connection:
            connection.exec_driver_sql(
                f"IF DB_ID(N'{database}') IS NULL CREATE DATABASE [{database}]"
            )
    finally:
        master.dispose()


def session_factory(name: str):
    """Return (engine, SessionLocal) for the named bounded context."""
    url = database_url(name)
    if url.startswith("sqlite"):
        Path(url.removeprefix("sqlite:///")).parent.mkdir(parents=True, exist_ok=True)
        engine = create_engine(url, connect_args={"check_same_thread": False})
    else:
        _create_sqlserver_database_if_missing(SQLSERVER_DATABASES[name])
        engine = create_engine(url, pool_pre_ping=True)
    return engine, sessionmaker(bind=engine, autoflush=False)


def create_tables(engine, base, tables) -> None:
    """Create the service's tables if missing.

    Two services share each database (S1/S2 and S4/S5). When both start at the same
    time, both may see the table missing and one CREATE fails with "already exists".
    A second pass then finds the table and does nothing.
    """
    try:
        base.metadata.create_all(engine, tables=tables)
    except DatabaseError:
        base.metadata.create_all(engine, tables=tables)
