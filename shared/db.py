"""Database selection: SQLite or SQL Server, chosen with DB_PROVIDER.

Each bounded context owns one database:
- identidad: S1 and S2 (users and credentials)
- vuelos: S3 (flights)
- reservas: S4 and S5 (reservations)
- aviones: S6 (aircraft registry)
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
    "aviones": ("AVIONES_DB", "aviones.db"),
}

SQLSERVER_DATABASES = {
    "identidad": "ReservasIdentidad",
    "vuelos": "ReservasVuelos",
    "reservas": "ReservasReservas",
    "aviones": "ReservasAviones",
}


# PostgreSQL (Supabase): one database, one schema per bounded context. The schemas are created by
# supabase/001_esquema.sql; the services never create them.
POSTGRES_SCHEMAS = {
    "identidad": "identidad",
    "vuelos": "vuelos",
    "reservas": "reservas",
    "aviones": "aviones",
}


def _provider() -> str:
    provider = os.getenv("DB_PROVIDER", "sqlite").strip().lower()
    if provider not in {"sqlite", "sqlserver", "postgres"}:
        raise ValueError(
            f"DB_PROVIDER must be 'sqlite', 'sqlserver' or 'postgres', got '{provider}'."
        )
    return provider


def revocacion_activa() -> bool:
    """True when the services share one database (Supabase), so identidad.tokens can be consulted."""
    return _provider() == "postgres"


def database_url(name: str) -> str:
    """Return the SQLAlchemy URL for the named context, using the configured provider."""
    provider = _provider()
    if provider == "sqlite":
        env_var, default_file = SQLITE_FILES[name]
        path = Path(os.getenv(env_var, os.path.join("data", default_file))).resolve()
        return f"sqlite:///{path.as_posix()}"
    if provider == "postgres":
        return _postgres_url()
    return _sqlserver_url(SQLSERVER_DATABASES[name])


def _postgres_url() -> str:
    """Connection string from DATABASE_URL (the Supabase 'session pooler' or direct URI)."""
    url = os.getenv("DATABASE_URL", "").strip()
    if not url:
        raise ValueError("DATABASE_URL is required when DB_PROVIDER=postgres (Supabase connection URI).")
    if url.startswith("postgresql://"):
        url = "postgresql+psycopg://" + url.removeprefix("postgresql://")
    return url


def postgres_connect_args(name: str) -> dict:
    """Send the context's schema as the search_path, so unqualified table names land in it."""
    return {"options": f"-csearch_path={POSTGRES_SCHEMAS[name]}"}


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
    elif url.startswith("postgresql"):
        engine = create_engine(url, pool_pre_ping=True, connect_args=postgres_connect_args(name))
    else:
        _create_sqlserver_database_if_missing(SQLSERVER_DATABASES[name])
        engine = create_engine(url, pool_pre_ping=True)
    return engine, sessionmaker(bind=engine, autoflush=False)


def add_column_if_missing(engine, table: str, column: str, ddl: str) -> None:
    """Add a column to an existing table if it is missing (create_all never alters tables).

    `ALTER TABLE t ADD <column> <ddl>` is valid on both SQLite and SQL Server. Two services
    may run this at the same time on one database; the loser re-checks and stops if the
    column already exists.
    """
    from sqlalchemy import inspect, text
    from sqlalchemy.exc import DatabaseError

    def _exists() -> bool:
        return any(c["name"] == column for c in inspect(engine).get_columns(table))

    if _exists():
        return
    try:
        with engine.begin() as connection:
            connection.execute(text(f"ALTER TABLE {table} ADD {column} {ddl}"))
    except DatabaseError:
        if not _exists():
            raise


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
