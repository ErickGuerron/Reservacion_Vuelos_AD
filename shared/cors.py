"""CORS so the browser client (cliente/) can call every service.

Allowed origins come from CORS_ORIGINS (comma-separated). The default covers the
client served locally with: python -m http.server 8080 --directory cliente
"""

import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from shared import config  # noqa: F401  loads .env before settings are read

DEFAULT_ORIGINS = "http://localhost:8080,http://127.0.0.1:8080,http://localhost:8083,http://127.0.0.1:8083"


def allowed_origins() -> list[str]:
    raw = os.getenv("CORS_ORIGINS", DEFAULT_ORIGINS)
    return [origin.strip() for origin in raw.split(",") if origin.strip()]


def enable_cors(app: FastAPI) -> None:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=allowed_origins(),
        allow_methods=["GET", "POST", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type"],
    )
