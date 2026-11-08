import 'package:aerovuelo_app/core/lotes.dart';
import 'package:aerovuelo_app/core/models.dart';
import 'package:aerovuelo_app/core/validadores.dart';
import 'package:flutter_test/flutter_test.dart';

Reserva _r(int id, {String estado = 'confirmada', String? asiento, double? precio, String? tipo, String? documento}) => Reserva(
      id: id,
      vueloId: 1,
      pasajero: 'Ana Torres',
      estado: estado,
      asiento: asiento,
      loteId: 1,
      precio: precio,
      tipoDocumento: tipo,
      documento: documento,
    );

void main() {
  group('cédula ecuatoriana', () {
    test('acepta cédulas con dígito verificador correcto', () {
      expect(validarCedula('1710034065'), isNull);
      expect(validarCedula('1713175071'), isNull);
    });

    test('rechaza longitud, caracteres, provincia y verificador incorrectos', () {
      expect(validarCedula(''), isNotNull);
      expect(validarCedula('171003'), 'Faltan 4 dígitos.');
      expect(validarCedula('17100340ab'), isNotNull);
      expect(validarCedula('9910034065'), isNotNull);
      expect(validarCedula('1710034066'), isNotNull);
    });
  });

  group('pasaporte', () {
    test('entre 6 y 12 letras o dígitos', () {
      expect(validarPasaporte('ab123456'), isNull);
      expect(validarPasaporte('123'), isNotNull);
      expect(validarPasaporte('AB 12345'), isNotNull);
    });

    test('validarDocumento elige la regla según el tipo', () {
      expect(validarDocumento('cedula', '1710034065'), isNull);
      expect(validarDocumento('pasaporte', '1710034065'), isNull);
      expect(validarDocumento('cedula', 'AB123456'), isNotNull);
    });
  });

  group('IVA 15 %', () {
    test('coincide con la factura de S5 (media hacia arriba, a centavos)', () {
      expect(calcularIva(178), 26.7);
      expect(calcularIva(90), 13.5);
      expect(calcularIva(45), 6.75);
      expect(calcularIva(0.10), 0.02);
    });

    test('el total del lote suma el IVA solo de las reservas confirmadas', () {
      final grupo = agruparPorLote([_r(1, precio: 45), _r(2, precio: 45), _r(3, precio: 45, estado: 'cancelada')]).single;
      expect(grupo.total, 90);
      expect(grupo.iva, 13.5);
      expect(grupo.totalConIva, 103.5);
    });
  });

  group('DatosFactura', () {
    test('arma un boleto por pasajero confirmado, ordenado por asiento, con su documento', () {
      final grupo = agruparPorLote([
        _r(1, asiento: '3A', precio: 45, tipo: 'cedula', documento: '1710034065'),
        _r(2, asiento: '1C', precio: 45, tipo: 'pasaporte', documento: 'AB123456'),
        _r(3, asiento: '2B', precio: 45, estado: 'cancelada'),
      ]).single;
      const factura = Factura(numero: 'P001-000001', fecha: '2026-11-08', cliente: 'Roberto Pérez', pasajeros: 2, subtotal: 90, iva: 13.5, total: 103.5);
      final datos = DatosFactura.desde(factura: factura, grupo: grupo, vuelo: null, correo: 'r@correo.com');
      expect(datos.boletos.map((b) => b.asiento), ['1C', '3A']);
      expect(datos.boletos.map((b) => b.documento), ['Pasaporte AB123456', 'Cédula 1710034065']);
      expect(datos.total, 103.5);
      expect(datos.reserva, 1);
    });
  });
}
