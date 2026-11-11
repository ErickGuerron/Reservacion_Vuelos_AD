"""ORM models. Each service creates only the tables it owns."""

from datetime import date, datetime

from sqlalchemy import Boolean, CheckConstraint, Date, DateTime, Float, ForeignKey, Index, Integer, String, UniqueConstraint, text
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class Usuario(Base):
    __tablename__ = "usuarios"
    __table_args__ = (CheckConstraint("rol IN ('cliente', 'administrador')", name="ck_usuarios_rol"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    nombre: Mapped[str] = mapped_column(String(100))
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    # Roles: "cliente" or "administrador" (see shared.security.ROLES).
    rol: Mapped[str] = mapped_column(String(20), default="cliente", server_default="cliente")


# Column added after the first release. Existing databases get it through add_column_if_missing.
USUARIO_ROL_DDL = "VARCHAR(20) NOT NULL DEFAULT 'cliente'"


class Avion(Base):
    """Avión registrado por S6. La capacidad es el número de asientos (18 a 180, múltiplo de 6)."""

    __tablename__ = "aviones"
    __table_args__ = (
        CheckConstraint("capacidad >= 18 AND capacidad <= 180 AND capacidad % 6 = 0", name="ck_aviones_capacidad"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    nombre: Mapped[str] = mapped_column(String(60), unique=True)
    capacidad: Mapped[int] = mapped_column(Integer)
    # Un avión inactivo no puede asignarse a vuelos nuevos; los vuelos que ya lo usan conservan su mapa.
    activo: Mapped[bool] = mapped_column(Boolean, default=True, server_default="1")


class Vuelo(Base):
    __tablename__ = "vuelos"
    __table_args__ = (
        # El cupo nunca puede quedar negativo, aunque una operación concurrente llegue tarde.
        CheckConstraint("asientos_disponibles >= 0", name="ck_vuelos_disponibles_no_negativos"),
        CheckConstraint("asientos_disponibles <= 180", name="ck_vuelos_disponibles_maximo"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    origen: Mapped[str] = mapped_column(String(100))
    destino: Mapped[str] = mapped_column(String(100))
    fecha: Mapped[date] = mapped_column(Date)
    # Hora de salida en formato HH:MM (24 horas). Texto para que sea igual en SQLite y SQL Server.
    hora: Mapped[str] = mapped_column(String(5), default="08:00", server_default="08:00")
    precio: Mapped[float] = mapped_column(Float)
    asientos_disponibles: Mapped[int] = mapped_column(Integer)
    # Un vuelo inactivo (borrador) no se muestra a los clientes ni acepta reservas; el administrador sí lo ve.
    # Por defecto un vuelo nuevo queda como borrador: el administrador decide al crearlo si lo publica.
    activo: Mapped[bool] = mapped_column(Boolean, default=False, server_default="0")
    # Hora estimada de llegada en HH:MM (opcional). Puede ser al día siguiente; no se valida contra la salida.
    hora_llegada: Mapped[str | None] = mapped_column(String(5), nullable=True)
    # Avión asignado (S6). NULL = vuelo anterior al registro de aviones; no hay FK: el avión vive en otro servicio.
    avion_id: Mapped[int | None] = mapped_column(Integer, nullable=True, index=True)
    # Versión del mapa de asientos: sube en cada cambio de asientos (reserva, cancelación, cambio). Permite
    # detectar que el formulario del cliente está desactualizado (control de concurrencia optimista).
    version: Mapped[int] = mapped_column(Integer, default=0, server_default="0")


# Columns added after the first release. Existing databases get them through add_column_if_missing.
VUELO_ACTIVO_DDL = "BIT NOT NULL DEFAULT 1"
VUELO_HORA_DDL = "VARCHAR(5) NOT NULL DEFAULT '08:00'"
VUELO_HORA_LLEGADA_DDL = "VARCHAR(5) NULL"
VUELO_AVION_DDL = "INTEGER NULL"
VUELO_VERSION_DDL = "INTEGER NOT NULL DEFAULT 0"


class AsientoVuelo(Base):
    """Seat of a flight, owned by S3. reserva_id is set while the seat is taken (NULL = free)."""

    __tablename__ = "asientos_vuelo"
    __table_args__ = (
        UniqueConstraint("vuelo_id", "codigo", name="uq_asiento_vuelo_codigo"),
        CheckConstraint("columna IN ('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H')", name="ck_asiento_columna"),
        # Una reserva ocupa como máximo un asiento: la base de datos lo garantiza aunque una operación concurrente llegue tarde.
        Index(
            "uq_asiento_reserva",
            "reserva_id",
            unique=True,
            sqlite_where=text("reserva_id IS NOT NULL"),
            postgresql_where=text("reserva_id IS NOT NULL"),
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    vuelo_id: Mapped[int] = mapped_column(Integer, index=True)
    codigo: Mapped[str] = mapped_column(String(10))  # e.g. "12C"
    fila: Mapped[int] = mapped_column(Integer)
    columna: Mapped[str] = mapped_column(String(1))
    reserva_id: Mapped[int | None] = mapped_column(Integer, nullable=True, index=True)


class Token(Base):
    """Token emitido en cada login (S2). Se guarda el SHA-256 del JWT, nunca el JWT en claro."""

    __tablename__ = "tokens"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    usuario_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id"), index=True)
    token: Mapped[str] = mapped_column(String(64), unique=True)
    expiracion: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    estado: Mapped[str] = mapped_column(String(20), default="activo", server_default="activo")


class Reserva(Base):
    __tablename__ = "reservas"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    usuario_email: Mapped[str] = mapped_column(String(255), index=True)
    vuelo_id: Mapped[int] = mapped_column(Integer)  # no FK: the flight lives in another service
    pasajero: Mapped[str] = mapped_column(String(100))
    estado: Mapped[str] = mapped_column(String(20))
    # Reservas de una misma compra comparten lote_id (el id de la primera). NULL = reserva anterior al lote.
    lote_id: Mapped[int | None] = mapped_column(Integer, nullable=True, index=True)
    # Precio por asiento copiado del vuelo al reservar; la factura se calcula con este valor.
    precio: Mapped[float | None] = mapped_column(Float, nullable=True)
    # Documento de quien viaja en el asiento: "cedula" o "pasaporte" y su número. NULL = reserva anterior.
    tipo_documento: Mapped[str | None] = mapped_column(String(10), nullable=True)
    documento: Mapped[str | None] = mapped_column(String(20), nullable=True)


# Columns added after the first release. Existing databases get them through add_column_if_missing.
RESERVA_LOTE_DDL = "INTEGER NULL"
RESERVA_PRECIO_DDL = "FLOAT NULL"
RESERVA_TIPO_DOCUMENTO_DDL = "VARCHAR(10) NULL"
RESERVA_DOCUMENTO_DDL = "VARCHAR(20) NULL"


class ReservaAsiento(Base):
    """Seat chosen for a reservation, owned by S4/S5 (the reservations database)."""

    __tablename__ = "reserva_asientos"

    reserva_id: Mapped[int] = mapped_column(Integer, primary_key=True)
    vuelo_id: Mapped[int] = mapped_column(Integer)
    asiento: Mapped[str] = mapped_column(String(10))


def reserva_to_dict(reserva: Reserva) -> dict:
    return {
        "id": reserva.id,
        "vueloId": reserva.vuelo_id,
        "pasajero": reserva.pasajero,
        "estado": reserva.estado,
        "loteId": reserva.lote_id,
        "precio": reserva.precio,
        "tipoDocumento": reserva.tipo_documento,
        "documento": reserva.documento,
    }
