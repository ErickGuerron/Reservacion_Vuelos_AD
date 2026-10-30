"""Demo console: switching services on and off. Real processes are replaced by stubs."""

import pytest

from gateway import estado
from orquestador import __main__ as consola
from orquestador.servicios import SERVICIOS, buscar


@pytest.fixture
def estado_tmp(tmp_path, monkeypatch):
    monkeypatch.setenv("GATEWAY_ESTADO", str(tmp_path / "estado.json"))
    monkeypatch.setattr(consola, "PROCESOS", tmp_path / "procesos.json")
    monkeypatch.setattr(consola, "RUNTIME", tmp_path)
    monkeypatch.setattr(consola, "LOGS", tmp_path / "logs")
    return tmp_path


def test_la_consola_gestiona_el_gateway_y_los_cinco_servicios():
    claves = [s.clave for s in SERVICIOS]
    assert claves == ["gateway", "usuarios", "autenticacion", "vuelos", "reservas", "gestion"]
    assert buscar("gateway").puerto == 8000
    assert {s.puerto for s in SERVICIOS if s.clave != "gateway"} == {5001, 5002, 5003, 5004, 5005}


def test_desactivar_marca_el_servicio_y_detiene_su_proceso(estado_tmp, monkeypatch):
    detenidos = []
    monkeypatch.setattr(consola, "_parar", lambda s: detenidos.append(s.clave) or "detenido")
    consola.main(["desactivar", "reservas"])
    assert estado.habilitado("reservas") is False
    assert detenidos == ["reservas"]


def test_activar_vuelve_a_habilitar_y_arranca_el_servicio(estado_tmp, monkeypatch):
    arrancados = []
    monkeypatch.setattr(consola, "_arrancar", lambda s: arrancados.append(s.clave) or "activo")
    estado.fijar_habilitado("reservas", False)
    consola.main(["activar", "reservas"])
    assert estado.habilitado("reservas") is True
    assert arrancados == ["reservas"]


def test_el_gateway_no_se_puede_desactivar(estado_tmp):
    with pytest.raises(SystemExit):
        consola.main(["desactivar", "gateway"])


def test_servicio_inexistente_se_rechaza(estado_tmp):
    with pytest.raises(SystemExit):
        consola.main(["desactivar", "inventado"])


def test_iniciar_omite_los_servicios_desactivados(estado_tmp, monkeypatch, capsys):
    arrancados = []
    monkeypatch.setattr(consola, "_arrancar", lambda s: arrancados.append(s.clave) or "activo")
    estado.fijar_habilitado("vuelos", False)
    consola.main(["iniciar"])
    assert "vuelos" not in arrancados
    assert "gateway" in arrancados and "gestion" in arrancados
    assert "omitido: desactivado" in capsys.readouterr().out


def test_estado_muestra_los_servicios_desactivados(estado_tmp, monkeypatch, capsys):
    monkeypatch.setattr(consola, "_responde", lambda puerto: False)
    estado.fijar_habilitado("autenticacion", False)
    consola.main(["estado"])
    salida = capsys.readouterr().out
    linea = next(l for l in salida.splitlines() if "Autenticación" in l)
    assert "desactivado" in linea
