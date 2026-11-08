import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/aeropuertos.dart';
import '../core/lotes.dart';

// Descarga de la factura: el XML se guarda tal cual lo entregó S5 y el PDF se arma con los mismos datos.

Future<void> guardarFacturaXml({required String xml, required String numero}) {
  return FileSaver.instance.saveFile(
    name: 'factura-$numero',
    bytes: Uint8List.fromList(utf8.encode(xml)),
    fileExtension: 'xml',
    mimeType: MimeType.custom,
    customMimeType: 'application/xml',
  );
}

Future<void> guardarFacturaPdf(DatosFactura datos) async {
  final bytes = await construirFacturaPdf(datos);
  await FileSaver.instance.saveFile(
    name: 'factura-${datos.numero}',
    bytes: bytes,
    fileExtension: 'pdf',
    mimeType: MimeType.pdf,
  );
}

String _usd(double valor) => '\$${valor.toStringAsFixed(2)}';

// Solo caracteres de la fuente estándar del PDF (Latin-1): por eso no se usan flechas ni viñetas.
Future<Uint8List> construirFacturaPdf(DatosFactura d) async {
  final oscuro = PdfColor.fromHex('#0F172A');
  final gris = PdfColor.fromHex('#475569');
  final linea = PdfColor.fromHex('#E2E6EB');
  final claro = PdfColor.fromHex('#F8FAFC');
  final azul = PdfColor.fromHex('#0A5C8A');

  pw.Widget etiqueta(String texto) =>
      pw.Text(texto, style: pw.TextStyle(fontSize: 8, color: gris, fontWeight: pw.FontWeight.bold, letterSpacing: 1));

  pw.Widget dato(String titulo, String valor) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [etiqueta(titulo), pw.SizedBox(height: 2), pw.Text(valor, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold))],
      );

  pw.Widget celda(String texto, {bool negrita = false, pw.TextAlign alinear = pw.TextAlign.left, PdfColor? color}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: pw.Text(
          texto,
          textAlign: alinear,
          style: pw.TextStyle(fontSize: 10, fontWeight: negrita ? pw.FontWeight.bold : pw.FontWeight.normal, color: color),
        ),
      );

  final vuelo = d.vuelo;
  final doc = pw.Document(title: 'Factura ${d.numero}', author: 'AeroVuelo');
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (context) => [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('AeroVuelo', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                pw.Text('Sky Booking System', style: pw.TextStyle(fontSize: 10, color: gris)),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('FACTURA ELECTRONICA', style: pw.TextStyle(fontSize: 9, color: azul, fontWeight: pw.FontWeight.bold, letterSpacing: 1)),
                pw.Text(d.numero, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.Text('Emitida el ${d.fecha}', style: pw.TextStyle(fontSize: 10, color: gris)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 18),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: linea), borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: dato('FACTURADO A', d.cliente)),
              pw.Expanded(child: dato('CORREO', d.correo ?? '-')),
              pw.Expanded(child: dato('RESERVA', '#${d.reserva}')),
            ],
          ),
        ),
        if (vuelo != null) ...[
          pw.SizedBox(height: 14),
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(color: oscuro, borderRadius: pw.BorderRadius.circular(10)),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('DETALLE DEL VUELO', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey300, fontWeight: pw.FontWeight.bold, letterSpacing: 1)),
                pw.SizedBox(height: 6),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('${vuelo.origen}  -  ${vuelo.destino}', style: pw.TextStyle(fontSize: 24, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(width: 12),
                    pw.Text(
                      [ciudadDe(vuelo.origen), ciudadDe(vuelo.destino)].where((c) => c.isNotEmpty).join(' a '),
                      style: pw.TextStyle(fontSize: 10, color: PdfColors.grey300),
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Text('Fecha ${vuelo.fecha}   Salida ${vuelo.hora} h   Vuelo #${vuelo.id}', style: pw.TextStyle(fontSize: 11, color: PdfColors.white)),
              ],
            ),
          ),
        ],
        pw.SizedBox(height: 16),
        etiqueta('BOLETOS Y PASAJEROS'),
        pw.SizedBox(height: 6),
        pw.Table(
          columnWidths: {
            0: pw.FlexColumnWidth(3),
            1: pw.FlexColumnWidth(2.4),
            2: pw.FlexColumnWidth(1),
            3: pw.FlexColumnWidth(1.2),
          },
          border: pw.TableBorder(horizontalInside: pw.BorderSide(color: linea, width: 0.5), bottom: pw.BorderSide(color: linea, width: 0.5)),
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: claro),
              children: [
                celda('PASAJERO', negrita: true, color: gris),
                celda('DOCUMENTO', negrita: true, color: gris),
                celda('ASIENTO', negrita: true, color: gris),
                celda('TARIFA', negrita: true, color: gris, alinear: pw.TextAlign.right),
              ],
            ),
            for (final b in d.boletos)
              pw.TableRow(
                children: [
                  celda(b.pasajero, negrita: true),
                  celda(b.documento ?? '-'),
                  celda(b.asiento ?? '-', negrita: true),
                  celda(_usd(b.precio), alinear: pw.TextAlign.right),
                ],
              ),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.SizedBox(
            width: 220,
            child: pw.Column(
              children: [
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Subtotal', style: pw.TextStyle(color: gris)), pw.Text(_usd(d.subtotal))]),
                pw.SizedBox(height: 4),
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('IVA $ivaPorcentaje %', style: pw.TextStyle(color: gris)), pw.Text(_usd(d.iva))]),
                pw.Divider(color: oscuro, thickness: 1.5),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Total pagado', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text(_usd(d.total), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
  return doc.save();
}
