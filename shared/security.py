"""Password hashing and JWT helpers shared by all services.

All services must use the same JWT_SECRET and algorithm to validate tokens
issued by the authentication service.
"""

import datetime as dt
import hashlib
import hmac
import os
import secrets

import jwt
from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from shared.errors import ApiError

ALGORITHM = "HS256"
TOKEN_MINUTES = 60
_PBKDF2_ITERATIONS = 100_000
_bearer = HTTPBearer(auto_error=False)


def _secret() -> str:
    return os.getenv("JWT_SECRET", "change-me-in-production")


def hash_password(password: str) -> str:
    salt = secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), _PBKDF2_ITERATIONS).hex()
    return f"{salt}${digest}"


def verify_password(password: str, stored: str) -> bool:
    salt, digest = stored.split("$")
    candidate = hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), _PBKDF2_ITERATIONS).hex()
    return hmac.compare_digest(candidate, digest)


def create_token(email: str) -> dict:
    expires = dt.datetime.now(dt.timezone.utc) + dt.timedelta(minutes=TOKEN_MINUTES)
    token = jwt.encode({"sub": email, "exp": expires}, _secret(), algorithm=ALGORITHM)
    return {"token": token, "expiraEn": TOKEN_MINUTES * 60}


def current_user_email(credentials: HTTPAuthorizationCredentials | None = Depends(_bearer)) -> str:
    if credentials is None:
        raise ApiError(401, "TOKEN_REQUERIDO", "Debe enviar un token Bearer.")
    try:
        payload = jwt.decode(credentials.credentials, _secret(), algorithms=[ALGORITHM])
    except jwt.PyJWTError:
        raise ApiError(401, "TOKEN_INVALIDO", "El token no es válido o ha expirado.")
    return payload["sub"]
