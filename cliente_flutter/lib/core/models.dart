class Vuelo {
  const Vuelo({
    required this.id,
    required this.origen,
    required this.destino,
    required this.fecha,
    required this.precio,
    required this.asientosDisponibles,
    this.activo = true,
  });

  final int id;
  final String origen;
  final String destino;
  final String fecha;
  final double precio;
  final int asientosDisponibles;
  // Un vuelo inactivo solo lo ve el administrador.
  final bool activo;

  bool get agotado => asientosDisponibles == 0;

  factory Vuelo.fromJson(Map<String, dynamic> json) => Vuelo(
        id: (json['id'] as num).toInt(),
        origen: json['origen'] as String,
        destino: json['destino'] as String,
        fecha: json['fecha'] as String,
        precio: (json['precio'] as num).toDouble(),
        asientosDisponibles: (json['asientosDisponibles'] as num).toInt(),
        activo: json['activo'] as bool? ?? true,
      );
}

// Vuelo visto por el administrador: incluye ocupación y si todavía puede editarse (sin reservas).
class VueloAdmin {
  const VueloAdmin({
    required this.id,
    required this.origen,
    required this.destino,
    required this.fecha,
    required this.precio,
    required this.totalAsientos,
    required this.asientosDisponibles,
    required this.asientosOcupados,
    required this.activo,
    required this.editable,
  });

  final int id;
  final String origen;
  final String destino;
  final String fecha;
  final double precio;
  final int totalAsientos;
  final int asientosDisponibles;
  final int asientosOcupados;
  final bool activo;
  final bool editable;

  factory VueloAdmin.fromJson(Map<String, dynamic> json) => VueloAdmin(
        id: (json['id'] as num).toInt(),
        origen: json['origen'] as String,
        destino: json['destino'] as String,
        fecha: json['fecha'] as String,
        precio: (json['precio'] as num).toDouble(),
        totalAsientos: (json['totalAsientos'] as num).toInt(),
        asientosDisponibles: (json['asientosDisponibles'] as num).toInt(),
        asientosOcupados: (json['asientosOcupados'] as num).toInt(),
        activo: json['activo'] as bool,
        editable: json['editable'] as bool,
      );
}

class Reserva {
  const Reserva({required this.id, required this.vueloId, required this.pasajero, required this.estado, this.asiento});

  final int id;
  final int vueloId;
  final String pasajero;
  final String estado;
  final String? asiento;

  bool get confirmada => estado == 'confirmada';

  factory Reserva.fromJson(Map<String, dynamic> json) => Reserva(
        id: (json['id'] as num).toInt(),
        vueloId: (json['vueloId'] as num).toInt(),
        pasajero: json['pasajero'] as String? ?? '',
        estado: json['estado'] as String? ?? '',
        asiento: json['asiento'] as String?,
      );
}
