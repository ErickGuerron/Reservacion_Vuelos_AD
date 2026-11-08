import 'package:flutter_test/flutter_test.dart';
import 'package:aerovuelo_app/core/lotes.dart';
import 'package:aerovuelo_app/core/models.dart';

Reserva _r(int id, {int? lote, String estado = 'confirmada', String? asiento, double? precio, String pasajero = 'Ana'}) =>
    Reserva(id: id, vueloId: 7, pasajero: pasajero, estado: estado, asiento: asiento, loteId: lote, precio: precio);

void main() {
  group('agruparPorLote', () {
    test('reservas del mismo lote forman un solo grupo, en orden de id', () {
      final grupos = agruparPorLote([_r(12, lote: 10, asiento: '2B'), _r(10, lote: 10, asiento: '1A'), _r(11, lote: 10, asiento: '1B')]);
      expect(grupos, hasLength(1));
      expect(grupos.single.loteId, 10);
      expect(grupos.single.reservas.map((r) => r.id), [10, 11, 12]);
      expect(grupos.single.asientos, ['1A', '1B', '2B']);
    });

    test('lotes distintos forman grupos distintos', () {
      final grupos = agruparPorLote([_r(1, lote: 1), _r(5, lote: 5), _r(6, lote: 5)]);
      expect(grupos.map((g) => g.loteId), [1, 5]);
      expect(grupos[1].reservas, hasLength(2));
    });

    test('una reserva anterior al lote (sin loteId) queda como grupo propio', () {
      final grupos = agruparPorLote([_r(3)]);
      expect(grupos, hasLength(1));
      expect(grupos.single.reservas.single.id, 3);
    });
  });

  group('GrupoReserva', () {
    test('total suma solo las reservas confirmadas', () {
      final grupo = agruparPorLote([
        _r(1, lote: 1, precio: 89),
        _r(2, lote: 1, precio: 89, estado: 'cancelada'),
        _r(3, lote: 1, precio: 89),
      ]).single;
      expect(grupo.total, 178);
    });

    test('está confirmado si alguna reserva del lote sigue confirmada', () {
      final parcial = agruparPorLote([_r(1, lote: 1), _r(2, lote: 1, estado: 'cancelada')]).single;
      final cancelado = agruparPorLote([_r(3, lote: 3, estado: 'cancelada')]).single;
      expect(parcial.confirmada, isTrue);
      expect(cancelado.confirmada, isFalse);
    });
  });

  group('Factura.desde', () {
    const xml = '<factura><numero>P001-000015</numero><fecha>2026-06-21</fecha><cliente>Juan Pérez</cliente>'
        '<pasajeros>2</pasajeros><subtotal>178.00</subtotal><iva porcentaje="15">26.70</iva><total>204.70</total></factura>';

    test('lee cada campo del XML que genera S5', () {
      final factura = Factura.desde(xml);
      expect(factura, isNotNull);
      expect(factura!.numero, 'P001-000015');
      expect(factura.fecha, '2026-06-21');
      expect(factura.cliente, 'Juan Pérez');
      expect(factura.pasajeros, 2);
      expect(factura.subtotal, 178.0);
      expect(factura.iva, 26.7);
      expect(factura.total, 204.7);
    });

    test('devuelve null si el contenido no es una factura', () {
      expect(Factura.desde('<html>error</html>'), isNull);
      expect(Factura.desde('{"mensaje": "x"}'), isNull);
    });
  });
}
