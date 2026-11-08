"""Revocation check for JWT tokens against identidad.tokens (Supabase only).

The JWT signature and expiry are always checked locally (shared.security). When the services
share one database, a token is also accepted only while its row in identidad.tokens is
'activo' and not expired. If that database does not answer, the request is refused (503):
a token whose state cannot be verified is never accepted.
"""

import datetime as dt
import hashlib

from sqlalchemy.exc import SQLAlchemyError

from shared.db import session_factory
from shared.errors import ApiError
from shared.models import Token

_session_local = None


def _sesion():
    global _session_local
    if _session_local is None:
        _, _session_local = session_factory("identidad")
    return _session_local


def _consultar_estado(digest: str) -> bool:
    ahora = dt.datetime.now(dt.timezone.utc)
    with _sesion()() as db:
        fila = db.query(Token).filter(Token.token == digest).first()
        if fila is None or fila.estado != "activo":
            return False
        expiracion = fila.expiracion
        # Todo lo que se guarda está en UTC. Un driver que devuelva fechas sin zona (SQLite) se interpreta como UTC.
        if expiracion.tzinfo is None:
            expiracion = expiracion.replace(tzinfo=dt.timezone.utc)
        return expiracion > ahora


def revocar_token(db, token: str) -> None:
    """Marca como revocado el token dado (cierre de sesión). Un token ya revocado no cambia."""
    digest = hashlib.sha256(token.encode()).hexdigest()
    db.query(Token).filter(Token.token == digest, Token.estado == "activo").update(
        {"estado": "revocado"}, synchronize_session=False
    )


def revocar_tokens_de_usuario(db, usuario_id: int) -> None:
    """Revoca todos los tokens activos de un usuario (p. ej. al cambiar su rol)."""
    db.query(Token).filter(Token.usuario_id == usuario_id, Token.estado == "activo").update(
        {"estado": "revocado"}, synchronize_session=False
    )


def token_activo(token: str) -> bool:
    digest = hashlib.sha256(token.encode()).hexdigest()
    try:
        return _consultar_estado(digest)
    except SQLAlchemyError:
        raise ApiError(503, "SERVICIO_NO_DISPONIBLE", "No se puede verificar la sesión en este momento.")
