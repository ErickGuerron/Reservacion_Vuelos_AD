class Vuelo {
  const Vuelo({
    required this.id,
    required this.origen,
    required this.destino,
    required this.fecha,
    this.hora = '08:00',
    required this.precio,
    required this.asientosDisponibles,
    this.activo = true,
  });

  final int id;
  final String origen;
  final String destino;
  final String fecha;
  // Hora de salida HH:MM (24 horas).
  final String hora;
  final double precio;
  final int asientosDisponibles;
  // Un vuelo inactivo solo lo ve el administrador.
  final bool activo;

  bool get agotado => asientosDisponibles == 0;

  // Corte de venta: no se reserva con menos de 3 horas para la salida. La hora es de Ecuador (UTC-5).
  // El servidor es quien aplica la regla; esto solo evita ofrecer una reserva que sería rechazada.
  bool get ventaCerrada {
    final f = fecha.split('-').map(int.parse).toList();
    final h = hora.split(':').map(int.parse).toList();
    final salidaUtc = DateTime.utc(f[0], f[1], f[2], h[0], h[1]).add(const Duration(hours: 5));
    return salidaUtc.difference(DateTime.now().toUtc()) < const Duration(hours: 3);
  }

  factory Vuelo.fromJson(Map<String, dynamic> json) => Vuelo(
        id: (json['id'] as num).toInt(),
        origen: json['origen'] as String,
        destino: json['destino'] as String,
        fecha: json['fecha'] as String,
        hora: json['hora'] as String? ?? '08:00',
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
    this.hora = '08:00',
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
  final String hora;
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
        hora: json['hora'] as String? ?? '08:00',
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
