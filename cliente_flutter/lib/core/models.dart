class Vuelo {
  const Vuelo({
    required this.id,
    required this.origen,
    required this.destino,
    required this.fecha,
    this.hora = '08:00',
    this.horaLlegada,
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
  // Hora estimada de llegada HH:MM, opcional (hora local del aeropuerto de destino).
  final String? horaLlegada;
  final double precio;
  final int asientosDisponibles;
  // Un vuelo inactivo solo lo ve el administrador.
  final bool activo;

  bool get agotado => asientosDisponibles == 0;

  // Si la llegada es anterior a la salida, el vuelo aterriza al día siguiente (el servidor no lo valida).
  // "08:30" o "08:30 → 09:25" (con "+1" si llega al día siguiente).
  String get horario => horaLlegada == null ? hora : '$hora → $horaLlegada${llegaDiaSiguiente ? ' (+1)' : ''}';

  bool get llegaDiaSiguiente => horaLlegada != null && horaLlegada!.compareTo(hora) < 0;

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
        horaLlegada: json['horaLlegada'] as String?,
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
    this.horaLlegada,
    required this.precio,
    required this.totalAsientos,
    required this.asientosDisponibles,
    required this.asientosOcupados,
    required this.activo,
    required this.editable,
    this.avionId,
  });

  final int id;
  final String origen;
  final String destino;
  final String fecha;
  final String hora;
  final String? horaLlegada;
  final double precio;
  final int totalAsientos;
  final int asientosDisponibles;
  final int asientosOcupados;
  final bool activo;
  final bool editable;
  // Avión del vuelo (S6). Null en vuelos anteriores al registro de aviones.
  final int? avionId;

  factory VueloAdmin.fromJson(Map<String, dynamic> json) => VueloAdmin(
        id: (json['id'] as num).toInt(),
        origen: json['origen'] as String,
        destino: json['destino'] as String,
        fecha: json['fecha'] as String,
        hora: json['hora'] as String? ?? '08:00',
        horaLlegada: json['horaLlegada'] as String?,
        precio: (json['precio'] as num).toDouble(),
        totalAsientos: (json['totalAsientos'] as num).toInt(),
        asientosDisponibles: (json['asientosDisponibles'] as num).toInt(),
        asientosOcupados: (json['asientosOcupados'] as num).toInt(),
        activo: json['activo'] as bool,
        editable: json['editable'] as bool,
        avionId: (json['avionId'] as num?)?.toInt(),
      );
}

// Avión registrado (S6). Su capacidad es el número de asientos de los vuelos que lo usan.
class Avion {
  const Avion({required this.id, required this.nombre, required this.capacidad, required this.activo});

  final int id;
  final String nombre;
  final int capacidad;
  // Un avión inactivo no se asigna a vuelos nuevos; los vuelos que ya lo usan conservan su mapa.
  final bool activo;

  // Filas de 3 + 3 que forma la capacidad.
  int get filas => capacidad ~/ 6;

  factory Avion.fromJson(Map<String, dynamic> json) => Avion(
        id: (json['id'] as num).toInt(),
        nombre: json['nombre'] as String,
        capacidad: (json['capacidad'] as num).toInt(),
        activo: json['activo'] as bool,
      );
}

class Reserva {
  const Reserva({
    required this.id,
    required this.vueloId,
    required this.pasajero,
    required this.estado,
    this.asiento,
    this.loteId,
    this.precio,
    this.tipoDocumento,
    this.documento,
  });

  final int id;
  final int vueloId;
  final String pasajero;
  final String estado;
  final String? asiento;
  // Reservas de una misma compra comparten loteId. Null = reserva anterior al lote.
  final int? loteId;
  // Precio por asiento al momento de reservar. Null = reserva anterior al lote.
  final double? precio;
  // Documento de quien viaja: 'cedula' o 'pasaporte'. Null = reserva anterior a este dato.
  final String? tipoDocumento;
  final String? documento;

  bool get confirmada => estado == 'confirmada';

  // "Cédula 1710034065" o "Pasaporte AB123456". Null si la reserva no guardó documento.
  String? get documentoEtiqueta {
    final numero = documento;
    if (numero == null || numero.isEmpty) return null;
    return '${tipoDocumento == 'pasaporte' ? 'Pasaporte' : 'Cédula'} $numero';
  }

  factory Reserva.fromJson(Map<String, dynamic> json) => Reserva(
        id: (json['id'] as num).toInt(),
        vueloId: (json['vueloId'] as num).toInt(),
        pasajero: json['pasajero'] as String? ?? '',
        estado: json['estado'] as String? ?? '',
        asiento: json['asiento'] as String?,
        loteId: (json['loteId'] as num?)?.toInt(),
        precio: (json['precio'] as num?)?.toDouble(),
        tipoDocumento: json['tipoDocumento'] as String?,
        documento: json['documento'] as String?,
      );
}
