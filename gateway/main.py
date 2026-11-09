"""API Gateway (port 8000): the single entry point for clients.

Every public request is forwarded to the service that owns it (see gateway/rutas.py).
- Services switched off with the console answer 503 SERVICIO_DESACTIVADO.
- Internal endpoints are not routed: 404 RUTA_NO_EXISTE.
- CORS is set only here. The services' own CORS headers are dropped when forwarding,
  so browsers never receive duplicated Access-Control-* headers.

GET /api/gateway/servicios reports, for each service, whether it is enabled and whether it answers.
"""

import asyncio

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, Response

from gateway import estado
from gateway.rutas import PUERTOS, resolver
from shared.cors import enable_cors

NOMBRES = {
    "usuarios": "S1 Usuarios",
    "autenticacion": "S2 Autenticación",
    "vuelos": "S3 Vuelos",
    "reservas": "S4 Reservas",
    "gestion": "S5 Gestión de reservas",
    "aviones": "S6 Aviones",
}

# Hop-by-hop headers and the ones the gateway or httpx recomputes.
_NO_REENVIAR = {
    "host",
    "content-length",
    "connection",
    "keep-alive",
    "transfer-encoding",
    "te",
    "trailer",
    "upgrade",
    "proxy-authenticate",
    "proxy-authorization",
}
METODOS = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

app = FastAPI(title="API Gateway - Reservas SOA", version="1.0.0")
enable_cors(app)

_cliente: httpx.AsyncClient | None = None


def cliente_http() -> httpx.AsyncClient:
    global _cliente
    if _cliente is None:
        _cliente = httpx.AsyncClient(timeout=10)
    return _cliente


def _url(servicio: str, path: str, query: str) -> str:
    base = f"http://127.0.0.1:{PUERTOS[servicio]}{path}"
    return f"{base}?{query}" if query else base


def _error(status: int, codigo: str, mensaje: str) -> JSONResponse:
    return JSONResponse(status_code=status, content={"codigo": codigo, "mensaje": mensaje})


def _cabeceras_de_respuesta(cabeceras: httpx.Headers) -> dict[str, str]:
    return {
        k: v
        for k, v in cabeceras.items()
        if k.lower() not in _NO_REENVIAR and not k.lower().startswith("access-control-")
    }


async def _responde(servicio: str) -> bool:
    try:
        respuesta = await cliente_http().get(f"http://127.0.0.1:{PUERTOS[servicio]}/openapi.json", timeout=1)
        return respuesta.status_code == 200
    except httpx.HTTPError:
        return False


@app.get("/api/gateway/servicios", summary="Estado de cada servicio: habilitado y respondiendo")
async def estado_servicios():
    claves = list(PUERTOS)
    respondiendo = await asyncio.gather(*(_responde(c) for c in claves))
    return [
        {
            "clave": clave,
            "nombre": NOMBRES[clave],
            "puerto": PUERTOS[clave],
            "habilitado": estado.habilitado(clave),
            "respondiendo": ok,
        }
        for clave, ok in zip(claves, respondiendo)
    ]


@app.api_route("/{ruta:path}", methods=METODOS, include_in_schema=False)
async def reenviar(ruta: str, request: Request):
    path = "/" + ruta
    servicio = resolver(path, request.method)
    if servicio is None:
        return _error(404, "RUTA_NO_EXISTE", "La ruta no existe en el gateway.")
    if not estado.habilitado(servicio):
        return _error(503, "SERVICIO_DESACTIVADO", f"El servicio {NOMBRES[servicio]} está desactivado.")

    cabeceras = {k: v for k, v in request.headers.items() if k.lower() not in _NO_REENVIAR}
    cuerpo = await request.body()
    try:
        respuesta = await cliente_http().request(
            request.method,
            _url(servicio, path, request.url.query),
            headers=cabeceras,
            content=cuerpo,
        )
    except httpx.HTTPError:
        return _error(503, "SERVICIO_NO_DISPONIBLE", f"El servicio {NOMBRES[servicio]} no responde.")

    return Response(
        content=respuesta.content,
        status_code=respuesta.status_code,
        headers=_cabeceras_de_respuesta(respuesta.headers),
    )
