"""Factura XML de un lote de reservas (S5).

Subtotal = suma de precio por pasajero de las reservas confirmadas del lote.
IVA = 15% del subtotal. Total = subtotal + IVA. Montos redondeados a centavos (media hacia arriba).
"""

from datetime import date
from decimal import ROUND_HALF_UP, Decimal
from xml.sax.saxutils import escape

IVA_PORCENTAJE = 15
_IVA = Decimal(IVA_PORCENTAJE) / Decimal(100)
_CENTAVO = Decimal("0.01")

EMISOR = "AeroVuelo"
EMISOR_DESCRIPCION = "Sky Booking System"
# Ciudad de cada aeropuerto conocido; el PDF del cliente muestra "Quito a Guayaquil" con la misma lista.
CIUDADES = {"UIO": "Quito", "GYE": "Guayaquil", "MAD": "Madrid"}


def _dinero(valor: Decimal) -> Decimal:
    return valor.quantize(_CENTAVO, rounding=ROUND_HALF_UP)


def calcular_totales(precios: list[float | None]) -> dict[str, Decimal]:
    """Reservas sin precio (anteriores al lote) cuentan como 0: su precio nunca se guardó."""
    subtotal = _dinero(sum((Decimal(str(p)) for p in precios if p is not None), Decimal("0")))
    iva = _dinero(subtotal * _IVA)
    return {"subtotal": subtotal, "iva": iva, "total": subtotal + iva}


def _vuelo_xml(vuelo: dict | None) -> str:
    if not vuelo:
        return ""
    datos = dict(vuelo)
    # Mismos datos que el PDF: número de vuelo y ciudades además de aeropuertos, fecha y horas.
    datos["ciudadOrigen"] = CIUDADES.get(str(vuelo.get("origen") or "").upper())
    datos["ciudadDestino"] = CIUDADES.get(str(vuelo.get("destino") or "").upper())
    campos = "".join(
        f"<{etiqueta}>{escape(str(datos[nombre]))}</{etiqueta}>"
        for nombre, etiqueta in (
            ("id", "id"),
            ("origen", "origen"),
            ("ciudadOrigen", "ciudadOrigen"),
            ("destino", "destino"),
            ("ciudadDestino", "ciudadDestino"),
            ("fecha", "fecha"),
            ("hora", "hora"),
            ("horaLlegada", "horaLlegada"),
        )
        if datos.get(nombre) is not None
    )
    return f"<vuelo>{campos}</vuelo>" if campos else ""


def _boletos_xml(boletos: list[dict] | None) -> str:
    if not boletos:
        return ""
    filas = []
    for b in boletos:
        filas.append(
            "<boleto>"
            f"<pasajero>{escape(b['pasajero'])}</pasajero>"
            f"<tipoDocumento>{escape(b.get('tipoDocumento') or '')}</tipoDocumento>"
            f"<documento>{escape(b.get('documento') or '')}</documento>"
            f"<asiento>{escape(b.get('asiento') or '')}</asiento>"
            f"<precio>{_dinero(Decimal(str(b.get('precio') or 0))):.2f}</precio>"
            "</boleto>"
        )
    return "<boletos>" + "".join(filas) + "</boletos>"


def construir_factura_xml(
    lote_id: int,
    cliente: str,
    precios: list[float | None],
    emitida: date,
    boletos: list[dict] | None = None,
    vuelo: dict | None = None,
    correo: str | None = None,
) -> str:
    totales = calcular_totales(precios)
    return (
        "<factura>"
        f"<numero>P001-{lote_id:06d}</numero>"
        f"<fecha>{emitida.isoformat()}</fecha>"
        f"<emisor><nombre>{EMISOR}</nombre><descripcion>{EMISOR_DESCRIPCION}</descripcion></emisor>"
        f"<cliente>{escape(cliente)}</cliente>"
        f"{f'<correo>{escape(correo)}</correo>' if correo else ''}"
        f"<reserva>{lote_id}</reserva>"
        f"<pasajeros>{len(precios)}</pasajeros>"
        f"<subtotal>{totales['subtotal']:.2f}</subtotal>"
        f"<iva porcentaje=\"{IVA_PORCENTAJE}\">{totales['iva']:.2f}</iva>"
        f"<total>{totales['total']:.2f}</total>"
        f"{_vuelo_xml(vuelo)}"
        f"{_boletos_xml(boletos)}"
        "</factura>"
    )
