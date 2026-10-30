"""Console to start, inspect and switch the services of the demo.

    python -m orquestador iniciar              start the gateway and every enabled service
    python -m orquestador estado               show enabled / running state of each process
    python -m orquestador desactivar reservas  stop a service; the gateway answers 503 for it
    python -m orquestador activar reservas     enable it again and start it
    python -m orquestador detener              stop everything

Processes run in the background (one uvicorn each). Their PIDs are kept in runtime/procesos.json
and their output in runtime/logs/.
"""

import argparse
import json
import os
import signal
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

from gateway import estado
from orquestador.servicios import SERVICIOS, Servicio, buscar

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "runtime"
PROCESOS = RUNTIME / "procesos.json"
LOGS = RUNTIME / "logs"
ESPERA_SEGUNDOS = 30


def _leer_procesos() -> dict[str, int]:
    if not PROCESOS.exists():
        return {}
    try:
        return json.loads(PROCESOS.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def _guardar_procesos(procesos: dict[str, int]) -> None:
    RUNTIME.mkdir(parents=True, exist_ok=True)
    PROCESOS.write_text(json.dumps(procesos, indent=2), encoding="utf-8")


def _responde(puerto: int) -> bool:
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{puerto}/openapi.json", timeout=1) as respuesta:
            return respuesta.status == 200
    except OSError:
        return False


def _arrancar(servicio: Servicio) -> str:
    if _responde(servicio.puerto):
        if servicio.clave in _leer_procesos():
            return "ya estaba respondiendo"
        # Something else owns the port: the console cannot stop it and it may run old code.
        return (
            f"el puerto {servicio.puerto} ya lo usa otro proceso que no inició la consola. "
            "Ciérrelo y vuelva a ejecutar 'iniciar' para que la consola lo gestione."
        )
    LOGS.mkdir(parents=True, exist_ok=True)
    log = open(LOGS / f"{servicio.clave}.log", "ab")
    comando = [sys.executable, "-m", "uvicorn", servicio.modulo, "--port", str(servicio.puerto)]
    flags = subprocess.CREATE_NEW_PROCESS_GROUP if os.name == "nt" else 0
    proceso = subprocess.Popen(comando, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, creationflags=flags)

    procesos = _leer_procesos()
    procesos[servicio.clave] = proceso.pid
    _guardar_procesos(procesos)

    limite = time.monotonic() + ESPERA_SEGUNDOS
    while time.monotonic() < limite:
        if proceso.poll() is not None:
            return f"terminó al arrancar (código {proceso.returncode}); revise runtime/logs/{servicio.clave}.log"
        if _responde(servicio.puerto):
            return "activo"
        time.sleep(0.5)
    return f"no respondió en {ESPERA_SEGUNDOS} s; revise runtime/logs/{servicio.clave}.log"


def _parar(servicio: Servicio) -> str:
    procesos = _leer_procesos()
    pid = procesos.pop(servicio.clave, None)
    _guardar_procesos(procesos)
    if pid is None:
        return "no tenía proceso registrado"
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        return "el proceso ya no estaba en ejecución"
    return "detenido"


def _estado_texto(servicio: Servicio) -> str:
    if servicio.desactivable and not estado.habilitado(servicio.clave):
        return "desactivado"
    if not _responde(servicio.puerto):
        return "detenido"
    return "activo" if servicio.clave in _leer_procesos() else "activo (no gestionado por la consola)"


def cmd_iniciar() -> None:
    for servicio in SERVICIOS:
        if not estado.habilitado(servicio.clave):
            print(f"{servicio.codigo:<3} {servicio.nombre:<22} omitido: desactivado")
            continue
        print(f"{servicio.codigo:<3} {servicio.nombre:<22} {_arrancar(servicio)}")
    print(f"\nGateway: http://localhost:{SERVICIOS[0].puerto}  (documentación en /docs)")


def cmd_estado() -> None:
    print(f"{'':<4}{'Servicio':<22}{'Puerto':<8}Estado")
    for servicio in SERVICIOS:
        print(f"{servicio.codigo:<4}{servicio.nombre:<22}{servicio.puerto:<8}{_estado_texto(servicio)}")


def cmd_desactivar(clave: str) -> None:
    servicio = buscar(clave)
    if not servicio.desactivable:
        raise SystemExit(f"El {servicio.nombre} no se puede desactivar.")
    estado.fijar_habilitado(clave, False)
    resultado = _parar(servicio)
    print(f"{servicio.codigo} {servicio.nombre}: desactivado; proceso {resultado}. El gateway responde 503 para sus rutas.")


def cmd_activar(clave: str) -> None:
    servicio = buscar(clave)
    estado.fijar_habilitado(clave, True)
    print(f"{servicio.codigo} {servicio.nombre}: habilitado; {_arrancar(servicio)}.")


def cmd_detener() -> None:
    for servicio in reversed(SERVICIOS):
        print(f"{servicio.codigo:<3} {servicio.nombre:<22} {_parar(servicio)}")


def main(argumentos: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(prog="python -m orquestador", description="Consola de la demo de servicios.")
    sub = parser.add_subparsers(dest="comando", required=True)
    sub.add_parser("iniciar", help="Arranca el gateway y los servicios habilitados")
    sub.add_parser("estado", help="Muestra el estado de cada servicio")
    sub.add_parser("detener", help="Detiene todo")
    for nombre, ayuda in (("desactivar", "Detiene un servicio y lo marca como desactivado"), ("activar", "Habilita y arranca un servicio")):
        p = sub.add_parser(nombre, help=ayuda)
        p.add_argument("servicio", choices=[s.clave for s in SERVICIOS if s.desactivable])

    args = parser.parse_args(argumentos)
    if args.comando == "iniciar":
        cmd_iniciar()
    elif args.comando == "estado":
        cmd_estado()
    elif args.comando == "detener":
        cmd_detener()
    elif args.comando == "desactivar":
        cmd_desactivar(args.servicio)
    elif args.comando == "activar":
        cmd_activar(args.servicio)


if __name__ == "__main__":
    main()
