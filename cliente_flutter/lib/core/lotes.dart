// Reservas por lote: una compra de varios asientos se muestra como una sola reserva.
// Las reservas de un mismo lote comparten loteId (S4); una reserva anterior al lote va sola.
import 'models.dart';

// IVA que aplica la factura de S5 (shared/factura.py): 15 % del subtotal, redondeado a centavos (media hacia arriba).
const ivaPorcentaje = 15;

double calcularIva(double subtotal) {
  final centavos = (subtotal * 100).round();
  return ((centavos * ivaPorcentaje + 50) ~/ 100) / 100;
}

class GrupoReserva {
  const GrupoReserva({required this.clave, required this.reservas});

  // loteId cuando existe; si no, el id de la reserva (grupo de una sola reserva).
  final int clave;
  final List<Reserva> reservas;

  int? get loteId => reservas.first.loteId;

  int get vueloId => reservas.first.vueloId;

  // Confirmado mientras quede al menos un asiento confirmado.
  bool get confirmada => reservas.any((r) => r.confirmada);

  List<String> get asientos => [
        for (final r in reservas)
          if (r.asiento != null) r.asiento!,
      ]..sort();

  // Suma del precio por asiento de las reservas confirmadas. Sin precio guardado cuenta como 0.
  double get total => reservas.where((r) => r.confirmada).fold(0.0, (suma, r) => suma + (r.precio ?? 0));

  // Lo mismo que la factura: subtotal + IVA 15 %.
  double get iva => calcularIva(total);

  double get totalConIva => total + iva;

  List<Reserva> get confirmadas => reservas.where((r) => r.confirmada).toList();
}

List<GrupoReserva> agruparPorLote(List<Reserva> reservas) {
  final porClave = <int, List<Reserva>>{};
  for (final r in [...reservas]..sort((a, b) => a.id.compareTo(b.id))) {
    porClave.putIfAbsent(r.loteId ?? r.id, () => []).add(r);
  }
  return [for (final e in porClave.entries) GrupoReserva(clave: e.key, reservas: e.value)]
    ..sort((a, b) => a.clave.compareTo(b.clave));
}

// Factura XML que genera S5 (GET /api/reservas/lote/{id}/factura), leída para mostrarla.
class Factura {
  const Factura({
    required this.numero,
    required this.fecha,
    required this.cliente,
    required this.pasajeros,
    required this.subtotal,
    required this.iva,
    required this.total,
  });

  final String numero;
  final String fecha;
  final String cliente;
  final int pasajeros;
  final double subtotal;
  final double iva;
  final double total;

  static Factura? desde(String xml) {
    if (!xml.trimLeft().startsWith('<factura>')) return null;
    String? campo(String nombre) => RegExp('<$nombre[^>]*>([^<]*)</$nombre>').firstMatch(xml)?.group(1);
    final numero = campo('numero');
    final fecha = campo('fecha');
    final cliente = campo('cliente');
    final pasajeros = campo('pasajeros');
    final subtotal = campo('subtotal');
    final iva = campo('iva');
    final total = campo('total');
    if ([numero, fecha, cliente, pasajeros, subtotal, iva, total].contains(null)) return null;
    return Factura(
      numero: numero!,
      fecha: fecha!,
      cliente: cliente!,
      pasajeros: int.parse(pasajeros!),
      subtotal: double.parse(subtotal!),
      iva: double.parse(iva!),
      total: double.parse(total!),
    );
  }
}

// Un boleto de la factura: una fila por pasajero con su asiento y su tarifa.
class BoletoFactura {
  const BoletoFactura({required this.pasajero, required this.asiento, required this.precio, this.documento});

  final String pasajero;
  final String? asiento;
  final double precio;
  // "Cédula 1710034065"; null si la reserva no guardó documento.
  final String? documento;
}

// Todo lo que muestra la factura (pantalla y PDF): los totales vienen del XML de S5; los boletos y el vuelo,
// de las reservas del lote y del vuelo que ya conoce la vista.
class DatosFactura {
  const DatosFactura({
    required this.numero,
    required this.fecha,
    required this.cliente,
    required this.correo,
    required this.reserva,
    required this.vuelo,
    required this.boletos,
    required this.subtotal,
    required this.iva,
    required this.total,
  });

  final String numero;
  final String fecha;
  final String cliente;
  final String? correo;
  final int reserva;
  final Vuelo? vuelo;
  final List<BoletoFactura> boletos;
  final double subtotal;
  final double iva;
  final double total;

  factory DatosFactura.desde({
    required Factura factura,
    required GrupoReserva grupo,
    required Vuelo? vuelo,
    required String? correo,
  }) {
    final boletos = [
      for (final r in grupo.confirmadas)
        BoletoFactura(pasajero: r.pasajero, asiento: r.asiento, precio: r.precio ?? 0, documento: r.documentoEtiqueta),
    ]..sort((a, b) => (a.asiento ?? '').compareTo(b.asiento ?? ''));
    return DatosFactura(
      numero: factura.numero,
      fecha: factura.fecha,
      cliente: factura.cliente,
      correo: correo,
      reserva: grupo.loteId ?? grupo.reservas.first.id,
      vuelo: vuelo,
      boletos: boletos,
      subtotal: factura.subtotal,
      iva: factura.iva,
      total: factura.total,
    );
  }
}
