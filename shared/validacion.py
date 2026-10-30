"""Reglas de validación de entrada compartidas por todos los servicios.

El frontend (cliente_flutter/lib/core/validadores.dart) aplica las mismas reglas antes de enviar,
pero la validación real está aquí: nunca se confía solo en el cliente.

Reglas generales:
- El texto se normaliza a NFC (los acentos quedan en una sola forma).
- No se aceptan espacios al inicio ni al final, ni espacios repetidos.
- No se aceptan emojis, símbolos ni caracteres de control en ningún texto.
- Nombres de personas: solo letras, espacio, apóstrofe y guion.
- Campos numéricos: solo dígitos (y un punto decimal donde corresponda).
"""

import re
import unicodedata

MAX_NOMBRE = 100
MAX_TEXTO = 100

# Puntuación permitida en textos libres (además de letras, dígitos y espacio simple).
SIGNOS_TEXTO = set(".,'-()/&:;!?¿¡\"")

NOMBRE_RE = re.compile(r"[^\W\d_]+(?:[ '\-][^\W\d_]+)*")  # letras Unicode (acentos y ñ), sin dígitos ni símbolos
PRECIO_RE = re.compile(r"[0-9]{1,6}(?:\.[0-9]{1,2})?")
IATA_RE = re.compile(r"[A-Za-z]{3}")
ASIENTO_RE = re.compile(r"([1-9][0-9]{0,2})([A-F])")
EMAIL_RE = re.compile(r"[^\s@]+@[^\s@]+\.[^\s@]{2,}")


def normalizar(valor: str) -> str:
    return unicodedata.normalize("NFC", valor)


def _sin_bordes_ni_dobles(valor: str, campo: str) -> None:
    if valor != valor.strip():
        raise ValueError(f"{campo} no puede empezar ni terminar con espacios.")
    if "  " in valor:
        raise ValueError(f"{campo} no puede tener espacios repetidos.")


def _solo_caracteres_permitidos(valor: str, campo: str) -> None:
    for caracter in valor:
        categoria = unicodedata.category(caracter)
        if categoria.startswith("L") or categoria == "Nd" or caracter == " " or caracter in SIGNOS_TEXTO:
            continue
        raise ValueError(f"{campo} contiene caracteres no permitidos (emojis, símbolos o caracteres de control).")


def validar_texto(valor: str, campo: str = "texto", minimo: int = 1, maximo: int = MAX_TEXTO) -> str:
    """Texto libre: letras, números, espacios simples y puntuación básica."""
    valor = normalizar(valor)
    _sin_bordes_ni_dobles(valor, campo)
    _solo_caracteres_permitidos(valor, campo)
    if not minimo <= len(valor) <= maximo:
        raise ValueError(f"{campo} debe tener entre {minimo} y {maximo} caracteres.")
    return valor


def validar_nombre_persona(valor: str, campo: str = "nombre") -> str:
    """Nombre de una persona: solo letras, con espacio, apóstrofe o guion entre palabras."""
    valor = normalizar(valor)
    _sin_bordes_ni_dobles(valor, campo)
    if not 2 <= len(valor) <= MAX_NOMBRE:
        raise ValueError(f"{campo} debe tener entre 2 y {MAX_NOMBRE} caracteres.")
    if not NOMBRE_RE.fullmatch(valor):
        raise ValueError(f"{campo} solo puede tener letras, espacios, apóstrofes y guiones.")
    return valor


def validar_nombre_pasajero(valor: str, campo: str = "El nombre del pasajero") -> str:
    """Nombre del pasajero en un boleto: exactamente dos palabras, nombre y apellido."""
    valor = validar_nombre_persona(valor, campo)
    if len(valor.split(" ")) != 2:
        raise ValueError(f"{campo} debe tener dos palabras: nombre y apellido.")
    return valor


def validar_iata(valor: str, campo: str = "código") -> str:
    """Código IATA de tres letras; se devuelve en mayúsculas."""
    if not IATA_RE.fullmatch(valor):
        raise ValueError(f"{campo} debe tener exactamente 3 letras.")
    return valor.upper()


def validar_codigo_asiento(valor: str) -> str:
    """Código de asiento: número de fila (sin ceros al inicio) seguido de una letra de la A a la F."""
    valor = valor.upper()
    if not ASIENTO_RE.fullmatch(valor):
        raise ValueError("El asiento debe tener el formato número y letra, por ejemplo 12C (letras de la A a la F).")
    return valor


def validar_email(valor: str) -> str:
    if any(caracter.isspace() for caracter in valor):
        raise ValueError("El correo no puede tener espacios.")
    if not EMAIL_RE.fullmatch(valor):
        raise ValueError("El correo electrónico no es válido.")
    return valor


def validar_password(valor: str) -> str:
    if valor != valor.strip():
        raise ValueError("La contraseña no puede empezar ni terminar con espacios.")
    if any(unicodedata.category(caracter) == "Cc" for caracter in valor):
        raise ValueError("La contraseña contiene caracteres de control.")
    return valor


def validar_solo_numero(valor: object, campo: str = "valor") -> object:
    """Rechaza textos y booleanos en campos numéricos: solo se aceptan números JSON."""
    if isinstance(valor, (str, bool)):
        raise ValueError(f"{campo} debe ser un número.")
    return valor
