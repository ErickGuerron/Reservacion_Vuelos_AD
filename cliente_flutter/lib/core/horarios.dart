// Horarios de vuelo: franjas de la hora de salida y estimación de duración que calcula S3
// (GET /api/vuelos/estimacion). Las franjas coinciden con shared/horarios.py.

enum Franja {
  madrugada('Madrugada', '00:00 a 05:59'),
  manana('Mañana', '06:00 a 11:59'),
  tarde('Tarde', '12:00 a 17:59'),
  noche('Noche', '18:00 a 23:59');

  const Franja(this.etiqueta, this.rango);

  final String etiqueta;
  final String rango;

  // Franja de una hora "HH:MM".
  static Franja de(String hora) {
    final h = int.tryParse(hora.split(':').first) ?? 0;
    if (h < 6) return Franja.madrugada;
    if (h < 12) return Franja.manana;
    if (h < 18) return Franja.tarde;
    return Franja.noche;
  }
}

// Minutos como "55 min" o "9 h 45 min".
String duracionTexto(int minutos) {
  final h = minutos ~/ 60;
  final m = minutos % 60;
  if (h == 0) return '$m min';
  return '$h h ${m.toString().padLeft(2, '0')} min';
}

// Duración habitual de una ruta, llegada sugerida y, si se envió una llegada, si es coherente.
class EstimacionVuelo {
  const EstimacionVuelo({
    required this.duracionHabitual,
    required this.duracionMinima,
    required this.duracionMaxima,
    required this.horaLlegadaSugerida,
    this.duracionIndicada,
    this.valida,
    this.mensaje,
  });

  final int duracionHabitual;
  final int duracionMinima;
  final int duracionMaxima;
  // HH:MM en la hora local del destino.
  final String horaLlegadaSugerida;
  final int? duracionIndicada;
  // null si no se envió hora de llegada.
  final bool? valida;
  final String? mensaje;

  factory EstimacionVuelo.fromJson(Map<String, dynamic> json) => EstimacionVuelo(
        duracionHabitual: (json['duracionHabitual'] as num).toInt(),
        duracionMinima: (json['duracionMinima'] as num).toInt(),
        duracionMaxima: (json['duracionMaxima'] as num).toInt(),
        horaLlegadaSugerida: json['horaLlegadaSugerida'] as String,
        duracionIndicada: (json['duracionIndicada'] as num?)?.toInt(),
        valida: json['valida'] as bool?,
        mensaje: json['mensaje'] as String?,
      );
}
