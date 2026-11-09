"""Password hashing (bcrypt, with PBKDF2 upgrade) and the cliente / administrador roles."""

import hashlib

import jwt
from fastapi.testclient import TestClient

from autenticacion.main import app as auth_app
from shared.models import Usuario
from shared.security import ROL_ADMIN, ROL_CLIENTE, hash_password, needs_rehash, verify_password
from usuarios import main as usuarios_main
from usuarios.main import app as usuarios_app
from vuelos.main import app as vuelos_app

usuarios = TestClient(usuarios_app)
auth = TestClient(auth_app)
vuelos = TestClient(vuelos_app)

PASSWORD = "clave-roles-123"
ADMIN_CONFIG = "admin@aerovuelo.com"  # listed in ADMIN_EMAILS by tests/conftest.py
VUELO = {"origen": "UIO", "destino": "MAD", "fecha": "2031-03-03", "precio": 500, "avionId": 1}


def _registrar(email: str) -> int:
    response = usuarios.post("/api/usuarios", json={"nombre": "Rol", "email": email, "password": PASSWORD})
    assert response.status_code == 201, response.text
    return response.json()["id"]


def _login(email: str) -> dict:
    response = auth.post("/api/auth/login", json={"email": email, "password": PASSWORD})
    assert response.status_code == 200, response.text
    return response.json()


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _usuario_en_bd(email: str) -> Usuario:
    with usuarios_main.SessionLocal() as db:
        return db.query(Usuario).filter(Usuario.email == email).first()


def _admin_token() -> str:
    """Token of the configured admin. Registering is idempotent for the tests: 409 means it already exists."""
    usuarios.post("/api/usuarios", json={"nombre": "Admin", "email": ADMIN_CONFIG, "password": PASSWORD})
    return _login(ADMIN_CONFIG)["token"]


# ----- Contraseñas -----


def test_contrasena_nueva_se_guarda_con_bcrypt():
    email = "bcrypt-nueva@correo.com"
    _registrar(email)
    assert _usuario_en_bd(email).password_hash.startswith("$2b$")
    assert _login(email)["rol"] == ROL_CLIENTE


def test_verify_password_acepta_bcrypt_y_rechaza_clave_erronea():
    stored = hash_password("clave-correcta")
    assert verify_password("clave-correcta", stored)
    assert not verify_password("otra-clave", stored)
    assert not needs_rehash(stored)


def test_hash_pbkdf2_heredado_sigue_valiendo_y_se_actualiza_a_bcrypt():
    email = "heredada@correo.com"
    salt = "ab" * 16
    digest = hashlib.pbkdf2_hmac("sha256", PASSWORD.encode(), salt.encode(), 100_000).hex()
    with usuarios_main.SessionLocal() as db:
        db.add(Usuario(nombre="Heredada", email=email, password_hash=f"{salt}${digest}", rol=ROL_CLIENTE))
        db.commit()

    assert needs_rehash(f"{salt}${digest}")
    _login(email)
    assert _usuario_en_bd(email).password_hash.startswith("$2b$")
    _login(email)  # still works after the upgrade


def test_contrasena_de_mas_de_72_bytes_se_rechaza_en_el_registro():
    response = usuarios.post(
        "/api/usuarios",
        json={"nombre": "Larga", "email": "larga@correo.com", "password": "a" * 73},
    )
    assert response.status_code == 400
    assert response.json()["errores"] == [
        {"campo": "password", "mensaje": "password no puede superar 72 bytes (unos 72 caracteres)."}
    ]


def test_verify_password_con_clave_demasiado_larga_devuelve_false():
    assert not verify_password("a" * 100, hash_password("a" * 72))


# ----- Roles -----


def test_registro_asigna_rol_cliente_y_lo_devuelve():
    response = usuarios.post(
        "/api/usuarios",
        json={"nombre": "Nuevo", "email": "rol-nuevo@correo.com", "password": PASSWORD},
    )
    assert response.status_code == 201
    assert response.json()["rol"] == ROL_CLIENTE


def test_login_devuelve_el_rol_en_el_cuerpo_y_en_el_token():
    _registrar("rol-login@correo.com")
    body = _login("rol-login@correo.com")
    assert body["rol"] == ROL_CLIENTE
    assert jwt.decode(body["token"], options={"verify_signature": False})["rol"] == ROL_CLIENTE


def test_admin_de_configuracion_entra_como_administrador():
    _admin_token()
    assert _login(ADMIN_CONFIG)["rol"] == ROL_ADMIN
    assert _usuario_en_bd(ADMIN_CONFIG).rol == ROL_ADMIN


def test_cliente_no_puede_listar_usuarios_y_sin_token_devuelve_401():
    _registrar("listado-cliente@correo.com")
    token = _login("listado-cliente@correo.com")["token"]
    assert usuarios.get("/api/admin/usuarios", headers=_auth(token)).status_code == 403
    assert usuarios.get("/api/admin/usuarios").status_code == 401


def test_administrador_lista_usuarios_con_su_rol():
    response = usuarios.get("/api/admin/usuarios", headers=_auth(_admin_token()))
    assert response.status_code == 200
    roles = {u["email"]: u["rol"] for u in response.json()}
    assert roles[ADMIN_CONFIG] == ROL_ADMIN


def test_administrador_promueve_y_degrada_con_efecto_en_login_y_en_vuelos():
    email = "promovido@correo.com"
    usuario_id = _registrar(email)
    admin = _admin_token()

    promovido = usuarios.put(f"/api/admin/usuarios/{usuario_id}/rol", json={"rol": ROL_ADMIN}, headers=_auth(admin))
    assert promovido.status_code == 200
    assert promovido.json()["rol"] == ROL_ADMIN

    nuevo_admin = _login(email)
    assert nuevo_admin["rol"] == ROL_ADMIN
    assert vuelos.post("/api/admin/vuelos", json=VUELO, headers=_auth(nuevo_admin["token"])).status_code == 201

    degradado = usuarios.put(f"/api/admin/usuarios/{usuario_id}/rol", json={"rol": ROL_CLIENTE}, headers=_auth(admin))
    assert degradado.status_code == 200
    assert _login(email)["rol"] == ROL_CLIENTE

    # Known limit: S3 trusts the token claim until it expires (60 min). S1 checks the database.
    assert usuarios.get("/api/admin/usuarios", headers=_auth(nuevo_admin["token"])).status_code == 403
    assert vuelos.post("/api/admin/vuelos", json=VUELO, headers=_auth(nuevo_admin["token"])).status_code == 201


def test_cliente_no_puede_cambiar_roles():
    objetivo = _registrar("objetivo-rol@correo.com")
    _registrar("cliente-rol@correo.com")
    cliente = _login("cliente-rol@correo.com")["token"]
    response = usuarios.put(f"/api/admin/usuarios/{objetivo}/rol", json={"rol": ROL_ADMIN}, headers=_auth(cliente))
    assert response.status_code == 403


def test_rol_invalido_devuelve_400():
    objetivo = _registrar("rol-invalido@correo.com")
    response = usuarios.put(
        f"/api/admin/usuarios/{objetivo}/rol", json={"rol": "superusuario"}, headers=_auth(_admin_token())
    )
    assert response.status_code == 400
    assert response.json()["codigo"] == "DATOS_INVALIDOS"


def test_usuario_inexistente_devuelve_404():
    response = usuarios.put(
        "/api/admin/usuarios/999999/rol", json={"rol": ROL_CLIENTE}, headers=_auth(_admin_token())
    )
    assert response.status_code == 404
    assert response.json()["codigo"] == "USUARIO_NO_EXISTE"


def test_administrador_de_configuracion_no_se_puede_degradar_desde_la_api():
    _admin_token()
    response = usuarios.put(
        f"/api/admin/usuarios/{_usuario_en_bd(ADMIN_CONFIG).id}/rol",
        json={"rol": ROL_CLIENTE},
        headers=_auth(_login(ADMIN_CONFIG)["token"]),
    )
    assert response.status_code == 409
    assert response.json()["codigo"] == "ADMIN_DE_CONFIGURACION"


def test_no_se_degrada_al_ultimo_administrador(monkeypatch):
    # Sin la lista de configuración, el criterio es solo la cantidad de administradores en la base.
    monkeypatch.setattr(usuarios_main, "es_admin_de_configuracion", lambda email: False)
    yo_id = _registrar("ultimo-admin@correo.com")
    usuarios.put(f"/api/admin/usuarios/{yo_id}/rol", json={"rol": ROL_ADMIN}, headers=_auth(_admin_token()))
    yo = _login("ultimo-admin@correo.com")["token"]

    with usuarios_main.SessionLocal() as db:
        otros = [u.id for u in db.query(Usuario).filter(Usuario.rol == ROL_ADMIN, Usuario.id != yo_id).all()]
    for otro in otros:
        assert usuarios.put(f"/api/admin/usuarios/{otro}/rol", json={"rol": ROL_CLIENTE}, headers=_auth(yo)).status_code == 200

    response = usuarios.put(f"/api/admin/usuarios/{yo_id}/rol", json={"rol": ROL_CLIENTE}, headers=_auth(yo))
    assert response.status_code == 409
    assert response.json()["codigo"] == "ULTIMO_ADMINISTRADOR"
