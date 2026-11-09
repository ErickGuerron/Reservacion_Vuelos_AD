import 'package:aerovuelo_app/core/models.dart';
import 'package:aerovuelo_app/core/validadores.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Avion', () {
    test('lee nombre y capacidad tal como los entrega S6', () {
      final avion = Avion.fromJson({
        'id': 3,
        'nombre': 'ATR 72',
        'capacidad': 72,
        'activo': true,
      });

      expect(avion.id, 3);
      expect(avion.nombre, 'ATR 72');
      expect(avion.capacidad, 72);
      expect(avion.activo, isTrue);
      expect(avion.filas, 12);
    });
  });

  group('VueloAdmin.avionId', () {
    Map<String, dynamic> vuelo({Object? avionId}) => {
      'id': 1,
      'origen': 'UIO',
      'destino': 'GYE',
      'fecha': '2031-01-10',
      'hora': '08:30',
      'precio': 45,
      'totalAsientos': 18,
      'asientosDisponibles': 18,
      'asientosOcupados': 0,
      'activo': true,
      'editable': true,
      'avionId': avionId,
    };

    test('un vuelo con avión conserva su identificador', () {
      expect(VueloAdmin.fromJson(vuelo(avionId: 7)).avionId, 7);
    });

    test('un vuelo anterior al registro de aviones tiene avionId nulo', () {
      expect(VueloAdmin.fromJson(vuelo()).avionId, isNull);
    });
  });

  group('validarNombreAvion', () {
    test('acepta nombres con letras, números y guion', () {
      expect(validarNombreAvion('Airbus A320-200'), isNull);
      expect(validarNombreAvion('ATR 72'), isNull);
    });

    test('rechaza vacío, demasiado corto o demasiado largo', () {
      expect(validarNombreAvion(''), isNotNull);
      expect(validarNombreAvion('A'), isNotNull);
      expect(validarNombreAvion(List.filled(61, 'A').join()), isNotNull);
    });

    test('rechaza espacios en los bordes, espacios repetidos y símbolos', () {
      expect(validarNombreAvion(' ATR 72'), isNotNull);
      expect(validarNombreAvion('ATR  72'), isNotNull);
      expect(validarNombreAvion('Avion ✈'), isNotNull);
    });

    test('rechaza la letra ñ y las emojis', () {
      expect(validarNombreAvion('Piña Jet'), isNotNull);
      expect(validarNombreAvion('AÑO 2030'), isNotNull);
      expect(validarNombreAvion('Avion 😀'), isNotNull);
    });
  });

  group('NombreAvionFormatter', () {
    String escribir(String texto) => NombreAvionFormatter()
        .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: texto, selection: TextSelection.collapsed(offset: texto.length)))
        .text;

    test('quita la ñ mientras se escribe', () {
      expect(escribir('Piña'), 'Pia');
      expect(escribir('AÑO'), 'AO');
    });

    test('quita emojis y símbolos mientras se escribe', () {
      expect(escribir('Avion 😀'), 'Avion ');
      expect(escribir('ATR ✈ 72'), 'ATR 72');
    });

    test('deja pasar letras sin ñ, números y guion', () {
      expect(escribir('Airbus A320-200'), 'Airbus A320-200');
    });
  });
}
