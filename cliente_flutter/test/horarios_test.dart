import 'package:aerovuelo_app/core/horarios.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Franja.de coincide con las franjas de S3', () {
    expect(['00:00', '05:59', '06:00', '11:59', '12:00', '17:59', '18:00', '23:59'].map(Franja.de).toList(), [
      Franja.madrugada,
      Franja.madrugada,
      Franja.manana,
      Franja.manana,
      Franja.tarde,
      Franja.tarde,
      Franja.noche,
      Franja.noche,
    ]);
  });

  test('duracionTexto', () {
    expect(duracionTexto(55), '55 min');
    expect(duracionTexto(585), '9 h 45 min');
    expect(duracionTexto(120), '2 h 00 min');
  });

  test('EstimacionVuelo lee la respuesta de S3', () {
    final e = EstimacionVuelo.fromJson({
      'duracionHabitual': 55,
      'duracionMinima': 35,
      'duracionMaxima': 75,
      'horaLlegadaSugerida': '09:25',
      'duracionIndicada': null,
      'valida': null,
      'mensaje': null,
    });
    expect(e.horaLlegadaSugerida, '09:25');
    expect(e.valida, isNull);
  });
}
