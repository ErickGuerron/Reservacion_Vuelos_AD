"""Horarios de vuelo: franjas del día, salida futura y duración habitual por ruta.

Las horas se guardan como HH:MM locales de cada aeropuerto. La duración de un vuelo se calcula pasando
salida y llegada a UTC con la zona de cada aeropuerto (Ecuador UTC-5 sin horario de verano, Madrid con él).
Las duraciones son promedios de vuelos habituales (tiempo en bloque) y se ajustan aquí.
"""

from datetime import date, datetime, timedelta, timezone

try:  # En Windows hace falta el paquete tzdata (requirements.txt).
    from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
except ImportError:  # pragma: no cover
    ZoneInfo = None  # type: ignore[assignment]

ZONAS = {"UIO": "America/Guayaquil", "GYE": "America/Guayaquil", "MAD": "Europe/Madrid"}

# Minutos de vuelo habituales por ruta (origen, destino).
DURACIONES_MIN = {
    ("UIO", "GYE"): 55,
    ("GYE", "UIO"): 55,
    ("UIO", "MAD"): 585,
    ("MAD", "UIO"): 640,
    ("GYE", "MAD"): 590,
    ("MAD", "GYE"): 640,
}

# Un vuelo se acepta si dura el habitual +/- 25 % (mínimo 20 minutos de margen).
TOLERANCIA_PORCENTAJE = 0.25
TOLERANCIA_MINIMA_MIN = 20

# Franjas por hora de salida: [desde, hasta) en horas.
FRANJAS = {"madrugada": (0, 6), "manana": (6, 12), "tarde": (12, 18), "noche": (18, 24)}

_ECUADOR = timezone(timedelta(hours=-5))


def franja_de(hora: str) -> str:
    h = int(hora.split(":")[0])
    return next(nombre for nombre, (desde, hasta) in FRANJAS.items() if desde <= h < hasta)


def _zona(codigo: str):
    nombre = ZONAS.get(codigo.upper())
    if nombre is None or ZoneInfo is None:
        return None
    try:
        return ZoneInfo(nombre)
    except ZoneInfoNotFoundError:
        return None


def _local(codigo: str, dia: date, hora: str) -> datetime:
    h, m = (int(p) for p in hora.split(":"))
    return datetime(dia.year, dia.month, dia.day, h, m, tzinfo=_zona(codigo) or _ECUADOR)


def salida_es_futura(origen: str, fecha: date, hora: str, ahora: datetime | None = None) -> bool:
    """La salida, en la hora local del aeropuerto de origen, es posterior a este momento."""
    return _local(origen, fecha, hora) > (ahora or datetime.now(timezone.utc))


def duracion_habitual(origen: str, destino: str) -> int | None:
    return DURACIONES_MIN.get((origen.upper(), destino.upper()))


def limites(habitual: int) -> tuple[int, int]:
    margen = max(TOLERANCIA_MINIMA_MIN, round(habitual * TOLERANCIA_PORCENTAJE))
    return habitual - margen, habitual + margen


def _duracion_real(origen: str, destino: str, fecha: date, hora: str, hora_llegada: str) -> int | None:
    """Minutos entre la salida y la primera llegada posterior con esa hora local (hasta dos días después)."""
    if _zona(origen) is None or _zona(destino) is None:
        return None
    salida = _local(origen, fecha, hora)
    for dias in range(3):
        llegada = _local(destino, fecha + timedelta(days=dias), hora_llegada)
        if llegada > salida:
            return int((llegada - salida).total_seconds() // 60)
    return None


def _texto(minutos: int) -> str:
    h, m = divmod(minutos, 60)
    return f"{h} h {m:02d} min" if h else f"{m} min"


def estimar(origen: str, destino: str, fecha: date, hora: str, hora_llegada: str | None = None) -> dict | None:
    """Duración habitual de la ruta, llegada sugerida y, si se da una llegada, si es coherente. None si no hay datos."""
    habitual = duracion_habitual(origen, destino)
    if habitual is None or _zona(origen) is None or _zona(destino) is None:
        return None
    minimo, maximo = limites(habitual)
    sugerida = (_local(origen, fecha, hora) + timedelta(minutes=habitual)).astimezone(_zona(destino)).strftime("%H:%M")
    resultado: dict = {
        "duracionHabitual": habitual,
        "duracionMinima": minimo,
        "duracionMaxima": maximo,
        "horaLlegadaSugerida": sugerida,
        "duracionIndicada": None,
        "valida": None,
        "mensaje": None,
    }
    if hora_llegada:
        real = _duracion_real(origen, destino, fecha, hora, hora_llegada)
        resultado["duracionIndicada"] = real
        resultado["valida"] = real is not None and minimo <= real <= maximo
        if not resultado["valida"]:
            resultado["mensaje"] = (
                f"Con salida {hora} y llegada {hora_llegada} el vuelo {origen.upper()} → {destino.upper()} duraría "
                f"{_texto(real) if real is not None else 'un tiempo no válido'}; lo habitual es {_texto(habitual)} "
                f"(entre {_texto(minimo)} y {_texto(maximo)}). La llegada sugerida es {sugerida}."
            )
    return resultado


def validar_horario(origen: str, destino: str, fecha: date, hora: str, hora_llegada: str | None) -> str | None:
    """Motivo por el que el horario no es válido, o None. La duración solo se controla en rutas conocidas."""
    if not salida_es_futura(origen, fecha, hora):
        return "La salida debe ser en el futuro: la fecha y la hora de salida ya pasaron."
    if hora_llegada:
        if hora_llegada == hora and ZONAS.get(origen) == ZONAS.get(destino):
            return "La hora de llegada no puede ser igual a la de salida."
        estimacion = estimar(origen, destino, fecha, hora, hora_llegada)
        if estimacion is not None and estimacion["valida"] is False:
            return estimacion["mensaje"]
    return None
