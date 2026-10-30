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

import bcrypt
import jwt
from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

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


def create_token(email: str, rol: str = ROL_CLIENTE) -> dict:
    expires = dt.datetime.now(dt.timezone.utc) + dt.timedelta(minutes=TOKEN_MINUTES)
    token = jwt.encode({"sub": email, "rol": rol, "exp": expires}, _secret(), algorithm=ALGORITHM)
    return {"token": token, "expiraEn": TOKEN_MINUTES * 60}


def _payload(credentials: HTTPAuthorizationCredentials | None) -> dict:
    if credentials is None:
        raise ApiError(401, "TOKEN_REQUERIDO", "Debe enviar un token Bearer.")
    try:
        return jwt.decode(credentials.credentials, _secret(), algorithms=[ALGORITHM])
    except jwt.PyJWTError:
        raise ApiError(401, "TOKEN_INVALIDO", "El token no es válido o ha expirado.")


def current_user_email(credentials: HTTPAuthorizationCredentials | None = Depends(_bearer)) -> str:
    return _payload(credentials)["sub"]


def current_cliente_email(credentials: HTTPAuthorizationCredentials | None = Depends(_bearer)) -> str:
    """Para reservar: solo cuentas de cliente. Los administradores gestionan vuelos, no reservan."""
    payload = _payload(credentials)
    if payload.get("rol") == ROL_ADMIN:
        raise ApiError(403, "PERMISO_DENEGADO", "Los administradores no pueden reservar vuelos. Use una cuenta de cliente.")
    return payload["sub"]


def current_admin_email(credentials: HTTPAuthorizationCredentials | None = Depends(_bearer)) -> str:
    payload = _payload(credentials)
    if payload.get("rol") != ROL_ADMIN:
        raise ApiError(403, "PERMISO_DENEGADO", "Se requiere una cuenta de administrador.")
    return payload["sub"]
