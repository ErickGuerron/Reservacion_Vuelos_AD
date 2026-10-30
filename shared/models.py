"""ORM models. Each service creates only the tables it owns."""

from datetime import date

from sqlalchemy import Boolean, CheckConstraint, Date, Float, Integer, String, UniqueConstraint
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
    precio: Mapped[float] = mapped_column(Float)
    asientos_disponibles: Mapped[int] = mapped_column(Integer)
    # Un vuelo inactivo (borrador) no se muestra a los clientes ni acepta reservas; el administrador sí lo ve.
    # Por defecto un vuelo nuevo queda como borrador: el administrador decide al crearlo si lo publica.
    activo: Mapped[bool] = mapped_column(Boolean, default=False, server_default="0")


# Column added after the first release. Existing databases get it through add_column_if_missing.
VUELO_ACTIVO_DDL = "BIT NOT NULL DEFAULT 1"


class AsientoVuelo(Base):
    """Seat of a flight, owned by S3. reserva_id is set while the seat is taken (NULL = free)."""

    __tablename__ = "asientos_vuelo"
    __table_args__ = (
        UniqueConstraint("vuelo_id", "codigo", name="uq_asiento_vuelo_codigo"),
        CheckConstraint("columna IN ('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H')", name="ck_asiento_columna"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    vuelo_id: Mapped[int] = mapped_column(Integer, index=True)
    codigo: Mapped[str] = mapped_column(String(10))  # e.g. "12C"
    fila: Mapped[int] = mapped_column(Integer)
    columna: Mapped[str] = mapped_column(String(1))
    reserva_id: Mapped[int | None] = mapped_column(Integer, nullable=True, index=True)


class Reserva(Base):
    __tablename__ = "reservas"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    usuario_email: Mapped[str] = mapped_column(String(255), index=True)
    vuelo_id: Mapped[int] = mapped_column(Integer)  # no FK: the flight lives in another service
    pasajero: Mapped[str] = mapped_column(String(100))
    estado: Mapped[str] = mapped_column(String(20))


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
    }
