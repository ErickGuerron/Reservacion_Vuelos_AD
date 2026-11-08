"""Password hashing and JWT helpers shared by all services.

All services must use the same JWT_SECRET and algorithm to validate tokens
issued by the authentication service.

Passwords: bcrypt (cost 12). Hashes created before bcrypt (PBKDF2-SHA256, format
"salt$digest") still verify and are upgraded to bcrypt on the next successful login.

Roles: "cliente" (default) and "administrador". The role is stored in the identity
database (usuarios.rol) and copied into the JWT "rol" claim at login. Accounts listed
in ADMIN_EMAILS are always administrators (bootstrap); the API cannot demote them.
"""

import datetime as dt
import hashlib
import hmac
import os
import secrets
from typing import NamedTuple

import bcrypt
import jwt
from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from shared import db
from shared import tokens as _tokens
from shared.errors import ApiError

ALGORITHM = "HS256"
TOKEN_MINUTES = 60
ROL_CLIENTE = "cliente"
ROL_ADMIN = "administrador"
ROLES = (ROL_CLIENTE, ROL_ADMIN)
BCRYPT_ROUNDS = 12
BCRYPT_MAX_BYTES = 72  # bcrypt ignores or rejects anything longer
_PBKDF2_ITERATIONS = 100_000
_BCRYPT_PREFIXES = ("$2a$", "$2b$", "$2y$")
_bearer = HTTPBearer(auto_error=False)


def _secret() -> str:
    return os.getenv("JWT_SECRET", "change-me-in-production")


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt(rounds=BCRYPT_ROUNDS)).decode()


def verify_password(password: str, stored: str) -> bool:
    if stored.startswith(_BCRYPT_PREFIXES):
        encoded = password.encode()
        if len(encoded) > BCRYPT_MAX_BYTES:
            return False
        return bcrypt.checkpw(encoded, stored.encode())
    return _verify_legacy_pbkdf2(password, stored)


def needs_rehash(stored: str) -> bool:
    """True when the stored hash is not bcrypt yet and must be replaced after a successful login."""
    return not stored.startswith(_BCRYPT_PREFIXES)


def _verify_legacy_pbkdf2(password: str, stored: str) -> bool:
    try:
        salt, digest = stored.split("$")
    except ValueError:
        return False
    candidate = hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), _PBKDF2_ITERATIONS).hex()
    return hmac.compare_digest(candidate, digest)


def es_admin_de_configuracion(email: str) -> bool:
    """Accounts named in ADMIN_EMAILS (comma-separated, read at call time)."""
    admins = {e.strip().lower() for e in os.getenv("ADMIN_EMAILS", "").split(",") if e.strip()}
    return email.lower() in admins


def create_token(email: str, rol: str = ROL_CLIENTE, nombre: str | None = None) -> dict:
    expires = dt.datetime.now(dt.timezone.utc) + dt.timedelta(minutes=TOKEN_MINUTES)
    # jti makes every token unique: two logins in the same second must not produce the same JWT.
    claims = {"sub": email, "rol": rol, "exp": expires, "jti": secrets.token_hex(16)}
    if nombre:
        # Name copied at login: other services read it from the token, without calling S1.
        claims["nombre"] = nombre
    token = jwt.encode(claims, _secret(), algorithm=ALGORITHM)
    return {"token": token, "expiraEn": TOKEN_MINUTES * 60}


def _payload(credentials: HTTPAuthorizationCredentials | None) -> dict:
    if credentials is None:
        raise ApiError(401, "TOKEN_REQUERIDO", "Debe enviar un token Bearer.")
    try:
        payload = jwt.decode(credentials.credentials, _secret(), algorithms=[ALGORITHM])
    except jwt.PyJWTError:
        raise ApiError(401, "TOKEN_INVALIDO", "El token no es válido o ha expirado.")
    # Firma y expiración ya están verificadas; con base compartida también se comprueba la revocación.
    if db.revocacion_activa() and not _tokens.token_activo(credentials.credentials):
        raise ApiError(401, "TOKEN_REVOCADO", "El token fue revocado o ya no está activo.")
    return payload


def current_user_email(credentials: HTTPAuthorizationCredentials | None = Depends(_bearer)) -> str:
    return _payload(credentials)["sub"]


def current_token(credentials: HTTPAuthorizationCredentials | None = Depends(_bearer)) -> str:
    """El token crudo, ya validado (firma, expiración y revocación). Lo usa el cierre de sesión."""
    _payload(credentials)
    return credentials.credentials


class Cuenta(NamedTuple):
    email: str
    nombre: str | None


def current_cliente_cuenta(credentials: HTTPAuthorizationCredentials | None = Depends(_bearer)) -> Cuenta:
    """Para reservar: solo cuentas de cliente. Los administradores gestionan vuelos, no reservan."""
    payload = _payload(credentials)
    if payload.get("rol") == ROL_ADMIN:
        raise ApiError(403, "PERMISO_DENEGADO", "Los administradores no pueden reservar vuelos. Use una cuenta de cliente.")
    return Cuenta(email=payload["sub"], nombre=payload.get("nombre"))


def current_cliente_email(credentials: HTTPAuthorizationCredentials | None = Depends(_bearer)) -> str:
    return current_cliente_cuenta(credentials).email


def current_admin_email(credentials: HTTPAuthorizationCredentials | None = Depends(_bearer)) -> str:
    payload = _payload(credentials)
    if payload.get("rol") != ROL_ADMIN:
        raise ApiError(403, "PERMISO_DENEGADO", "Se requiere una cuenta de administrador.")
    return payload["sub"]
