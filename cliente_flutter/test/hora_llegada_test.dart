import 'package:aerovuelo_app/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> json({String? llegada}) => {
        'id': 1,
        'origen': 'UIO',
        'destino': 'GYE',
        'fecha': '2031-11-10',
        'hora': '08:30',
        'horaLlegada': llegada,
        'precio': 45.0,
        'asientosDisponibles': 30,
        'activo': true,
      };

  test('Vuelo lee horaLlegada y es opcional', () {
    expect(Vuelo.fromJson(json(llegada: '09:25')).horaLlegada, '09:25');
    expect(Vuelo.fromJson(json()).horaLlegada, isNull);
  });

  test('llegaDiaSiguiente solo cuando la llegada es menor que la salida', () {
    expect(Vuelo.fromJson(json(llegada: '09:25')).llegaDiaSiguiente, isFalse);
    expect(Vuelo.fromJson({...json(llegada: '06:40'), 'hora': '22:10'}).llegaDiaSiguiente, isTrue);
    expect(Vuelo.fromJson(json()).llegaDiaSiguiente, isFalse);
  });

  test('VueloAdmin conserva horaLlegada para no borrarla al editar', () {
    final v = VueloAdmin.fromJson({
      ...json(llegada: '09:25'),
      'totalAsientos': 60,
      'asientosOcupados': 0,
      'editable': true,
    });
    expect(v.horaLlegada, '09:25');
  });
}
