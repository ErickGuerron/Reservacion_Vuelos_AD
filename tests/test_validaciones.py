"""Reglas de validación de entrada (shared/validacion.py) y su aplicación en los endpoints."""

import pytest
from fastapi.testclient import TestClient

from reservas.main import app as reservas_app
from shared.security import create_token
from shared.validacion import (
    validar_codigo_asiento,
    validar_email,
    validar_iata,
    validar_nombre_persona,
    validar_password,
    validar_texto,
)
from usuarios.main import app as usuarios_app

usuarios = TestClient(usuarios_app)
reservas = TestClient(reservas_app)
AUTH = {"Authorization": f"Bearer {create_token('validacion@correo.com')['token']}"}


# ----- Nombres de personas -----


@pytest.mark.parametrize("nombre", ["Ana", "José Ramírez", "Niño Peña", "O'Neil", "Ana-María", "Ñandú"])
def test_nombres_validos(nombre):
    assert validar_nombre_persona(nombre) == nombre


@pytest.mark.parametrize(
    "nombre",
    [
        "Ana 😀",  # emoji
        "Ana\u2764",  # símbolo
        "Ana123",  # dígitos
        "Ana_Maria",  # guion bajo
        " Ana",  # espacio al inicio
        "Ana ",  # espacio al final
        "Ana  Maria",  # espacios repetidos
        "A",  # demasiado corto
        "Ana\tMaria",  # tabulador
    ],
)
def test_nombres_invalidos(nombre):
    with pytest.raises(ValueError):
        validar_nombre_persona(nombre)


# ----- Texto libre -----


def test_texto_libre_acepta_puntuacion_basica_y_rechaza_emojis():
    assert validar_texto("Vuelo, directo (sin escalas)!") == "Vuelo, directo (sin escalas)!"
    with pytest.raises(ValueError):
        validar_texto("Vuelo 🛫")


def test_texto_libre_normaliza_acentos_a_nfc():
    decompuesto = "Jose\u0301"  # "José" con el acento como carácter combinado
    assert validar_texto(decompuesto) == "José"


# ----- Códigos IATA, asientos, correo y contraseña -----


@pytest.mark.parametrize("codigo", ["UIO", "gye", "MAD"])
def test_iata_valido_en_mayusculas(codigo):
    assert validar_iata(codigo) == codigo.upper()


@pytest.mark.parametrize("codigo", ["UI1", "UIOX", "UI ", " UIO", "U-O"])
def test_iata_invalido(codigo):
    with pytest.raises(ValueError):
        validar_iata(codigo)


@pytest.mark.parametrize("asiento", ["12C", "1a", "30F"])
def test_asiento_valido(asiento):
    assert validar_codigo_asiento(asiento) == asiento.upper()


@pytest.mark.parametrize("asiento", ["012C", "12G", " 12C", "12 C", "C12", "1AB"])
def test_asiento_invalido(asiento):
    with pytest.raises(ValueError):
        validar_codigo_asiento(asiento)


def test_correo_sin_espacios():
    assert validar_email("ana@correo.com") == "ana@correo.com"
    with pytest.raises(ValueError):
        validar_email("ana @correo.com")


def test_contrasena_sin_espacios_en_los_bordes():
    assert validar_password("clave con espacio") == "clave con espacio"
    with pytest.raises(ValueError):
        validar_password(" clave1234")
    with pytest.raises(ValueError):
        validar_password("clave1234 ")


# ----- Aplicación en los endpoints -----


def test_registro_rechaza_nombre_con_emoji():
    response = usuarios.post(
        "/api/usuarios",
        json={"nombre": "Ana 😀", "email": "emoji@correo.com", "password": "clave-segura-1"},
    )
    assert response.status_code == 400
    assert response.json()["codigo"] == "DATOS_INVALIDOS"


def test_registro_rechaza_nombre_con_espacio_inicial():
    response = usuarios.post(
        "/api/usuarios",
        json={"nombre": " Ana Maria", "email": "espacio@correo.com", "password": "clave-segura-1"},
    )
    assert response.status_code == 400


def test_reserva_rechaza_nombre_de_pasajero_con_digitos():
    response = reservas.post(
        "/api/reservas",
        json={"vueloId": 1, "pasajero": "Pasajero 2"},
        headers=AUTH,
    )
    assert response.status_code == 400
    assert response.json()["codigo"] == "DATOS_INVALIDOS"


def test_reserva_rechaza_asiento_con_formato_invalido():
    response = reservas.post(
        "/api/reservas",
        json={"vueloId": 1, "pasajero": "Ana Torres", "asiento": "12G"},
        headers=AUTH,
    )
    assert response.status_code == 400


def test_lote_rechaza_nombre_con_emoji_antes_de_tocar_los_asientos():
    response = reservas.post(
        "/api/reservas/lote",
        json={"vueloId": 1, "reservas": [{"pasajero": "Ana 😀"}]},
        headers=AUTH,
    )
    assert response.status_code == 400


def test_cambio_de_asiento_rechaza_formato_invalido():
    response = reservas.put("/api/reservas/1/asiento", json={"asiento": "ZZ"}, headers=AUTH)
    assert response.status_code == 400


def test_vuelo_id_como_texto_se_rechaza():
    response = reservas.post("/api/reservas", json={"vueloId": "1", "pasajero": "Ana Torres"}, headers=AUTH)
    assert response.status_code == 400


@pytest.mark.parametrize("pasajero", ["Ana", "Ana Maria Torres", "Ana  Torres"])
def test_pasajero_debe_tener_nombre_y_apellido(pasajero):
    response = reservas.post("/api/reservas", json={"vueloId": 1, "pasajero": pasajero}, headers=AUTH)
    assert response.status_code == 400


def test_validar_nombre_pasajero_acepta_dos_palabras():
    from shared.validacion import validar_nombre_pasajero

    assert validar_nombre_pasajero("José Ramírez") == "José Ramírez"
    with pytest.raises(ValueError):
        validar_nombre_pasajero("Ana")
