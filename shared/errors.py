"""Uniform error contract: {"codigo": str, "mensaje": str}."""

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.openapi.utils import get_openapi
from fastapi.responses import JSONResponse
from pydantic import BaseModel


class CampoError(BaseModel):
    campo: str
    mensaje: str


class ErrorOut(BaseModel):
    """Body of every error response. `errores` is present only for 400 DATOS_INVALIDOS."""

    codigo: str
    mensaje: str
    errores: list[CampoError] | None = None


_DESCRIPCIONES = {
    400: "Datos inválidos (DATOS_INVALIDOS)",
    401: "Token o credenciales no válidos",
    404: "Recurso no encontrado",
    409: "Conflicto con el estado actual",
    503: "Servicio dependiente no disponible",
}


def errores(*codigos: int) -> dict:
    """OpenAPI `responses` entry for the given error status codes."""
    return {c: {"model": ErrorOut, "description": _DESCRIPCIONES[c]} for c in codigos}


class ApiError(Exception):
    def __init__(self, status_code: int, codigo: str, mensaje: str):
        super().__init__(mensaje)
        self.status_code = status_code
        self.codigo = codigo
        self.mensaje = mensaje


def register_error_handlers(app: FastAPI) -> None:
    _publish_error_contract(app)

    @app.exception_handler(ApiError)
    async def _handle_api_error(request: Request, exc: ApiError):
        return JSONResponse(
            status_code=exc.status_code,
            content={"codigo": exc.codigo, "mensaje": exc.mensaje},
        )

    @app.exception_handler(RequestValidationError)
    async def _handle_validation_error(request: Request, exc: RequestValidationError):
        # The guide's contract uses 400 for invalid data (FastAPI defaults to 422).
        errores = [_describe_field_error(error) for error in exc.errors()]
        return JSONResponse(
            status_code=400,
            content={
                "codigo": "DATOS_INVALIDOS",
                "mensaje": " ".join(e["mensaje"] for e in errores),
                "errores": errores,
            },
        )


def _describe_field_error(error: dict) -> dict:
    """Turn one Pydantic error into a field-specific message the client can act on."""
    campo = str(error["loc"][-1]) if error.get("loc") else "request"
    tipo = error["type"]
    ctx = error.get("ctx", {})

    if tipo == "missing":
        mensaje = f"{campo} es obligatorio."
    elif tipo == "string_too_short" and ctx.get("min_length") == 1:
        mensaje = f"{campo} no puede estar vacío."
    elif tipo == "string_too_short":
        mensaje = f"{campo} debe tener al menos {ctx['min_length']} caracteres."
    elif tipo == "string_too_long":
        mensaje = f"{campo} debe tener como máximo {ctx['max_length']} caracteres."
    elif campo == "email":
        mensaje = "email debe ser una dirección válida, por ejemplo nombre@dominio.com."
    elif tipo.startswith("int_parsing"):
        mensaje = f"{campo} debe ser un número entero."
    elif tipo.startswith("date"):
        mensaje = f"{campo} debe ser una fecha con formato AAAA-MM-DD."
    else:
        mensaje = f"{campo} no es válido."

    return {"campo": campo, "mensaje": mensaje}


def _publish_error_contract(app: FastAPI) -> None:
    """Remove FastAPI's default 422 from the OpenAPI document.

    Validation errors are answered with 400 and ErrorOut (see the handler above),
    so the published contract must say the same.
    """

    def openapi() -> dict:
        if app.openapi_schema:
            return app.openapi_schema
        schema = get_openapi(title=app.title, version=app.version, routes=app.routes)
        for operaciones in schema.get("paths", {}).values():
            for operacion in operaciones.values():
                operacion.get("responses", {}).pop("422", None)
        componentes = schema.get("components", {}).get("schemas", {})
        componentes.pop("HTTPValidationError", None)
        componentes.pop("ValidationError", None)
        app.openapi_schema = schema
        return schema

    app.openapi = openapi
