"""ORM models. Each service creates only the tables it owns."""

from datetime import date

from sqlalchemy import Date, Float, Integer, String
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class Usuario(Base):
    __tablename__ = "usuarios"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    nombre: Mapped[str] = mapped_column(String(100))
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))


class Vuelo(Base):
    __tablename__ = "vuelos"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    origen: Mapped[str] = mapped_column(String(100))
    destino: Mapped[str] = mapped_column(String(100))
    fecha: Mapped[date] = mapped_column(Date)
    precio: Mapped[float] = mapped_column(Float)
    asientos_disponibles: Mapped[int] = mapped_column(Integer)


class Reserva(Base):
    __tablename__ = "reservas"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    usuario_email: Mapped[str] = mapped_column(String(255), index=True)
    vuelo_id: Mapped[int] = mapped_column(Integer)  # no FK: the flight lives in another service
    pasajero: Mapped[str] = mapped_column(String(100))
    estado: Mapped[str] = mapped_column(String(20))


def reserva_to_dict(reserva: Reserva) -> dict:
    return {
        "id": reserva.id,
        "vueloId": reserva.vuelo_id,
        "pasajero": reserva.pasajero,
        "estado": reserva.estado,
    }
