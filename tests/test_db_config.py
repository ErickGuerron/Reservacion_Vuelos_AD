from urllib.parse import parse_qs, urlparse

import pytest

from shared import db


def _odbc_params(url: str) -> str:
    return parse_qs(urlparse(url).query)["odbc_connect"][0]


def test_sqlite_es_el_proveedor_por_defecto(monkeypatch, tmp_path):
    archivo = tmp_path / "identidad.db"
    monkeypatch.setenv("DB_PROVIDER", "sqlite")
    monkeypatch.setenv("IDENTITY_DB", str(archivo))
    assert db.database_url("identidad") == f"sqlite:///{archivo.resolve().as_posix()}"


def test_sqlserver_usa_una_base_por_contexto(monkeypatch):
    monkeypatch.setenv("DB_PROVIDER", "sqlserver")
    monkeypatch.setenv("SQLSERVER_SERVER", "localhost")
    monkeypatch.setenv("SQLSERVER_USER", "sa")
    monkeypatch.setenv("SQLSERVER_PASSWORD", "clave")
    url = db.database_url("vuelos")
    assert url.startswith("mssql+pyodbc:///?odbc_connect=")
    params = _odbc_params(url)
    assert "SERVER=localhost" in params
    assert "DATABASE=ReservasVuelos" in params
    assert "UID=sa" in params
    assert "ODBC Driver 18 for SQL Server" in params


def test_sqlserver_escapa_la_contrasena_con_caracteres_especiales(monkeypatch):
    monkeypatch.setenv("DB_PROVIDER", "sqlserver")
    monkeypatch.setenv("SQLSERVER_SERVER", "localhost")
    monkeypatch.setenv("SQLSERVER_USER", "sa")
    monkeypatch.setenv("SQLSERVER_PASSWORD", "p@ss;w}rd")
    assert "PWD={p@ss;w}}rd}" in _odbc_params(db.database_url("reservas"))


def test_sqlserver_sin_usuario_usa_autenticacion_de_windows(monkeypatch):
    monkeypatch.setenv("DB_PROVIDER", "sqlserver")
    monkeypatch.setenv("SQLSERVER_SERVER", "localhost")
    monkeypatch.delenv("SQLSERVER_USER", raising=False)
    params = _odbc_params(db.database_url("identidad"))
    assert "Trusted_Connection=yes" in params
    assert "UID=" not in params


def test_proveedor_desconocido_falla_con_mensaje_claro(monkeypatch):
    monkeypatch.setenv("DB_PROVIDER", "oracle")
    with pytest.raises(ValueError, match="DB_PROVIDER"):
        db.database_url("identidad")


def test_create_tables_tolera_que_otro_servicio_la_cree_a_la_vez(monkeypatch, tmp_path):
    from sqlalchemy import create_engine, inspect
    from sqlalchemy.exc import OperationalError

    from shared.models import Base, Usuario

    engine = create_engine(f"sqlite:///{(tmp_path / 'carrera.db').as_posix()}")
    original = Base.metadata.create_all
    llamadas = []

    def primera_falla(*args, **kwargs):
        llamadas.append(1)
        if len(llamadas) == 1:
            original(*args, **kwargs)  # the other service wins the race
            raise OperationalError("CREATE TABLE usuarios", {}, Exception("table usuarios already exists"))
        return original(*args, **kwargs)

    monkeypatch.setattr(Base.metadata, "create_all", primera_falla)
    db.create_tables(engine, Base, [Usuario.__table__])
    assert len(llamadas) == 2
    assert "usuarios" in inspect(engine).get_table_names()
