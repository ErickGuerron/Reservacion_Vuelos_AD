"""Seat layout helpers. Seat codes combine row and column letter: "1A", "12C"."""

import math

LETRAS = "ABCDEFGH"
MAX_FILAS = 50
MAX_COLUMNAS = len(LETRAS)
COLUMNAS_LEGADO = 6  # layout used for flights created before seat selection existed

# Configuración de cabina de la aerolínea: 3 asientos a cada lado del pasillo (3 + 3).
COLUMNAS_POR_FILA = 6
MIN_ASIENTOS = 18  # 3 filas
MAX_ASIENTOS = 180  # 30 filas (capacidad típica de un A320 en rutas nacionales)


def validar_total_asientos(total: int) -> str | None:
    """Return the reason the total is not allowed, or None when it is valid.

    Rows are filled 3 + 3, so the total must be a multiple of 6 (the seats of each side come in groups of 3).
    """
    if total < MIN_ASIENTOS or total > MAX_ASIENTOS:
        return f"El total de asientos debe estar entre {MIN_ASIENTOS} y {MAX_ASIENTOS}."
    if total % COLUMNAS_POR_FILA != 0:
        return f"El total de asientos debe ser múltiplo de {COLUMNAS_POR_FILA} (filas de 3 + 3)."
    return None


def layout_para_total(total: int) -> list[dict]:
    """Seat map for a valid total: full rows of 3 + 3 seats (A-C on one side, D-F on the other)."""
    return generar_asientos(total // COLUMNAS_POR_FILA, COLUMNAS_POR_FILA)


def generar_asientos(filas: int, columnas: int) -> list[dict]:
    """Full grid of `filas` rows with `columnas` seats each, ordered by row then column."""
    return [
        {"codigo": f"{fila}{LETRAS[columna]}", "fila": fila, "columna": LETRAS[columna]}
        for fila in range(1, filas + 1)
        for columna in range(columnas)
    ]


def generar_asientos_para_total(total: int, columnas: int = COLUMNAS_LEGADO) -> list[dict]:
    """Exactly `total` seats laid out in `columnas` columns (the last row may be partial)."""
    if total <= 0:
        return []
    filas = math.ceil(total / columnas)
    return generar_asientos(filas, columnas)[:total]
