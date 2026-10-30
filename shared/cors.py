"""CORS so browser clients (the HTML client in cliente/ and the Flutter web app) can call every service.

Allowed origins come from two sources, both applied:
- CORS_ORIGINS (comma-separated, explicit list).
- CORS_ORIGIN_REGEX (default: any localhost / 127.0.0.1 port). Flutter web and
  `flutter run -d chrome` pick a random port, so an explicit list cannot cover them.
  Set CORS_ORIGIN_REGEX to an empty value to disable the regex.
"""

import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from shared import config  # noqa: F401  loads .env before settings are read

DEFAULT_ORIGINS = "http://localhost:8080,http://127.0.0.1:8080,http://localhost:8083,http://127.0.0.1:8083"
DEFAULT_ORIGIN_REGEX = r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$"


def allowed_origins() -> list[str]:
    raw = os.getenv("CORS_ORIGINS", DEFAULT_ORIGINS)
    return [origin.strip() for origin in raw.split(",") if origin.strip()]


def allowed_origin_regex() -> str | None:
    raw = os.getenv("CORS_ORIGIN_REGEX", DEFAULT_ORIGIN_REGEX).strip()
    return raw or None


def enable_cors(app: FastAPI) -> None:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=allowed_origins(),
        allow_origin_regex=allowed_origin_regex(),
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type"],
    )
