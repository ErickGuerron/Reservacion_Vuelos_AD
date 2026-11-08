import pytest
from fastapi.testclient import TestClient
from sqlalchemy.exc import OperationalError

from gestion.main import app as gestion_app
from shared import tokens
from shared.security import create_token

gestion = TestClient(gestion_app)
EMAIL = "revocado@correo.com"


def _auth() -> dict:
    return {"Authorization": f"Bearer {create_token(EMAIL)['token']}"}


@pytest.fixture
def supabase(monkeypatch):
    """Simulate DB_PROVIDER=postgres: revocation is checked against identidad.tokens."""
    monkeypatch.setenv("DB_PROVIDER", "postgres")


def test_token_revocado_devuelve_401(supabase, monkeypatch):
    monkeypatch.setattr(tokens, "token_activo", lambda token: False)
    response = gestion.get("/api/reservas", headers=_auth())
    assert response.status_code == 401
    assert response.json()["codigo"] == "TOKEN_REVOCADO"


def test_token_activo_pasa_la_validacion(supabase, monkeypatch):
    monkeypatch.setattr(tokens, "token_activo", lambda token: True)
    response = gestion.get("/api/reservas", headers=_auth())
    assert response.status_code == 200


def test_base_caida_rechaza_el_token_con_503(supabase, monkeypatch):
    def _caida(token):
        raise OperationalError("SELECT", {}, Exception("connection refused"))

    monkeypatch.setattr(tokens, "_consultar_estado", _caida)
    response = gestion.get("/api/reservas", headers=_auth())
    assert response.status_code == 503
    assert response.json()["codigo"] == "SERVICIO_NO_DISPONIBLE"


def test_sqlite_no_consulta_la_revocacion(monkeypatch):
    monkeypatch.setenv("DB_PROVIDER", "sqlite")

    def _no_debe_llamarse(token):
        raise AssertionError("SQLite no comparte identidad.tokens con los demás servicios")

    monkeypatch.setattr(tokens, "token_activo", _no_debe_llamarse)
    assert gestion.get("/api/reservas", headers=_auth()).status_code == 200


def test_el_token_se_busca_por_su_hash_sha256(monkeypatch):
    import hashlib

    consultados = []
    monkeypatch.setattr(tokens, "_consultar_estado", lambda digest: consultados.append(digest) or True)
    monkeypatch.setenv("DB_PROVIDER", "postgres")
    token = create_token(EMAIL)["token"]
    assert tokens.token_activo(token) is True
    assert consultados == [hashlib.sha256(token.encode()).hexdigest()]
