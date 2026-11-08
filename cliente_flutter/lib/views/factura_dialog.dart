import 'package:flutter/material.dart';

import '../core/aeropuertos.dart';
import '../core/api_client.dart';
import '../core/lotes.dart';
import '../core/models.dart';
import '../core/services.dart';
import '../theme/app_theme.dart';
import 'factura_archivos.dart';

// Factura de un lote: GET /api/reservas/lote/{id}/factura (S5). Los totales salen del XML del servicio;
// los boletos (pasajero, documento, asiento y tarifa) y el vuelo, de las reservas del lote.
// Se puede descargar en XML (tal cual lo entregó S5) o en PDF.
class FacturaDialog extends StatefulWidget {
  const FacturaDialog({
    super.key,
    required this.loteId,
    required this.token,
    required this.grupo,
    required this.vuelo,
    required this.correo,
  });

  final int loteId;
  final String token;
  final GrupoReserva grupo;
  final Vuelo? vuelo;
  final String? correo;

  @override
  State<FacturaDialog> createState() => _FacturaDialogState();
}

class _FacturaDialogState extends State<FacturaDialog> {
  String? _xml;
  DatosFactura? _datos;
  String? _error;
  String? _aviso;
  bool _descargando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final xml = await FacturasService.obtener(loteId: widget.loteId, token: widget.token);
      final factura = Factura.desde(xml);
      if (!mounted) return;
      setState(() {
        _xml = xml;
        if (factura == null) {
          _error = 'La factura recibida no tiene el formato esperado.';
        } else {
          _datos = DatosFactura.desde(factura: factura, grupo: widget.grupo, vuelo: widget.vuelo, correo: widget.correo);
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.mensaje);
    }
  }

  Future<void> _descargar({required bool pdf}) async {
    final datos = _datos;
    final xml = _xml;
    if (datos == null || xml == null) return;
    setState(() {
      _descargando = true;
      _aviso = null;
      _error = null;
    });
    try {
      if (pdf) {
        await guardarFacturaPdf(datos);
      } else {
        await guardarFacturaXml(xml: xml, numero: datos.numero);
      }
      if (!mounted) return;
      setState(() => _aviso = 'Factura ${datos.numero} descargada en ${pdf ? 'PDF' : 'XML'}.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo descargar el archivo.');
    } finally {
      if (mounted) setState(() => _descargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final datos = _datos;
    return Dialog(
      backgroundColor: AppColors.surfaceContainerLowest,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Barra(onCerrar: () => Navigator.of(context).pop()),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: datos == null
                    ? (_error != null
                        ? Text(_error!, style: AppTheme.bodyMd(color: AppColors.error))
                        : const Center(child: Padding(padding: EdgeInsets.all(AppSpacing.lg), child: CircularProgressIndicator())))
                    : _Cuerpo(datos: datos),
              ),
            ),
            _Descargas(
              habilitado: datos != null && !_descargando,
              error: datos == null ? null : _error,
              aviso: _aviso,
              onPdf: () => _descargar(pdf: true),
              onXml: () => _descargar(pdf: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _Barra extends StatelessWidget {
  const _Barra({required this.onCerrar});

  final VoidCallback onCerrar;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('FACTURA ELECTRÓNICA', style: AppTheme.telemetry(size: 12, weight: FontWeight.w700, color: AppColors.slate700)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.successBg, borderRadius: BorderRadius.circular(999)),
                  child: Text('EMITIDA', style: AppTheme.telemetry(size: 11, weight: FontWeight.w700, color: AppColors.successText)),
                ),
              ],
            ),
          ),
          IconButton(tooltip: 'Cerrar', onPressed: onCerrar, icon: const Icon(Icons.close)),
        ],
      ),
    );
  }
}

class _Cuerpo extends StatelessWidget {
  const _Cuerpo({required this.datos});

  final DatosFactura datos;

  static String _usd(double v) => '\$${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final vuelo = datos.vuelo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.md,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AeroVuelo', style: AppTheme.headlineMd()),
                Text('Sky Booking System', style: AppTheme.bodySm(color: AppColors.onSurfaceVariant)),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Par('Factura N.º', datos.numero, mono: true),
                _Par('Reserva', '#${datos.reserva}', mono: true),
                _Par('Fecha de emisión', datos.fecha),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(border: Border.all(color: AppColors.surfaceVariant), borderRadius: BorderRadius.circular(14)),
          child: Wrap(
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.md,
            children: [
              _Campo('Facturado a', datos.cliente),
              if (datos.correo != null) _Campo('Correo', datos.correo!),
            ],
          ),
        ),
        if (vuelo != null) ...[
          const SizedBox(height: AppSpacing.lg),
          const _Titulo('Detalle del vuelo'),
          const SizedBox(height: AppSpacing.sm),
          _TarjetaVuelo(vuelo: vuelo),
        ],
        const SizedBox(height: AppSpacing.lg),
        const _Titulo('Boletos y pasajeros'),
        const SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(border: Border.all(color: AppColors.surfaceVariant), borderRadius: BorderRadius.circular(14)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < datos.boletos.length; i++)
                _Boleto(boleto: datos.boletos[i], numero: i + 1, primero: i == 0),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Column(
              children: [
                _Linea('Subtotal (${datos.boletos.length} boleto${datos.boletos.length == 1 ? '' : 's'})', _usd(datos.subtotal)),
                _Linea('IVA $ivaPorcentaje %', _usd(datos.iva)),
                const Divider(height: AppSpacing.md, thickness: 2, color: AppColors.primary),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(child: Text('Total pagado', style: AppTheme.bodyMd().copyWith(fontWeight: FontWeight.w700))),
                    Text(_usd(datos.total), style: AppTheme.headlineMd().copyWith(fontWeight: FontWeight.w800)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) =>
      Text(texto.toUpperCase(), style: AppTheme.telemetry(size: 12, weight: FontWeight.w700, color: AppColors.slate700));
}

class _Par extends StatelessWidget {
  const _Par(this.etiqueta, this.valor, {this.mono = false});

  final String etiqueta;
  final String valor;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Wrap(
        spacing: AppSpacing.sm,
        children: [
          Text(etiqueta, style: AppTheme.bodySm(color: AppColors.onSurfaceVariant)),
          Text(valor, style: mono ? AppTheme.telemetry(size: 13, weight: FontWeight.w700, color: AppColors.onSurface) : AppTheme.bodySm().copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _Campo extends StatelessWidget {
  const _Campo(this.etiqueta, this.valor);

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(etiqueta.toUpperCase(), style: AppTheme.labelSm(color: AppColors.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(valor, style: AppTheme.bodyMd().copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _Linea extends StatelessWidget {
  const _Linea(this.etiqueta, this.valor);

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(etiqueta, style: AppTheme.bodyMd(color: AppColors.onSurfaceVariant))),
          Text(valor, style: AppTheme.bodyMd().copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _TarjetaVuelo extends StatelessWidget {
  const _TarjetaVuelo({required this.vuelo});

  final Vuelo vuelo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(color: AppColors.slate900, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Aeropuerto(codigo: vuelo.origen, alineacion: CrossAxisAlignment.start),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  child: Row(
                    children: [
                      const Expanded(child: Divider(color: AppColors.slate500, thickness: 2)),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                        child: Icon(Icons.flight, color: Colors.white, size: 22),
                      ),
                      const Expanded(child: Divider(color: AppColors.slate500, thickness: 2)),
                    ],
                  ),
                ),
              ),
              _Aeropuerto(codigo: vuelo.destino, alineacion: CrossAxisAlignment.end),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(color: AppColors.slate700, height: 1),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.md,
            children: [
              _DatoVuelo('Fecha', vuelo.fecha),
              _DatoVuelo('Salida', '${vuelo.hora} h'),
              if (vuelo.horaLlegada != null) _DatoVuelo('Llegada', '${vuelo.horaLlegada} h${vuelo.llegaDiaSiguiente ? ' (+1)' : ''}'),
              _DatoVuelo('Vuelo', '#${vuelo.id}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Aeropuerto extends StatelessWidget {
  const _Aeropuerto({required this.codigo, required this.alineacion});

  final String codigo;
  final CrossAxisAlignment alineacion;

  @override
  Widget build(BuildContext context) {
    final ciudad = ciudadDe(codigo);
    return Column(
      crossAxisAlignment: alineacion,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(codigo, style: AppTheme.headlineLg(color: Colors.white).copyWith(fontWeight: FontWeight.w800)),
        if (ciudad.isNotEmpty) Text(ciudad, style: AppTheme.bodySm(color: AppColors.slate300)),
      ],
    );
  }
}

class _DatoVuelo extends StatelessWidget {
  const _DatoVuelo(this.etiqueta, this.valor);

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(etiqueta.toUpperCase(), style: AppTheme.labelSm(color: AppColors.slate300)),
        const SizedBox(height: 2),
        Text(valor, style: AppTheme.bodyMd(color: Colors.white).copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

// Un boleto: asiento, nombre de quien viaja, su documento y la tarifa.
class _Boleto extends StatelessWidget {
  const _Boleto({required this.boleto, required this.numero, required this.primero});

  final BoletoFactura boleto;
  final int numero;
  final bool primero;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
      decoration: BoxDecoration(border: primero ? null : const Border(top: BorderSide(color: AppColors.surfaceVariant))),
      child: Row(
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 56),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: AppColors.secondaryFixed, borderRadius: BorderRadius.circular(10)),
            child: Text(
              boleto.asiento ?? '—',
              textAlign: TextAlign.center,
              style: AppTheme.telemetry(size: 16, weight: FontWeight.w700, color: AppColors.onSecondaryFixed),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(boleto.pasajero, style: AppTheme.bodyMd().copyWith(fontWeight: FontWeight.w700)),
                Text(
                  [if (boleto.documento != null) boleto.documento!, 'Pasajero $numero'].join(' · '),
                  style: AppTheme.bodySm(color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text('\$${boleto.precio.toStringAsFixed(2)}', style: AppTheme.bodyMd().copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _Descargas extends StatelessWidget {
  const _Descargas({required this.habilitado, required this.error, required this.aviso, required this.onPdf, required this.onXml});

  final bool habilitado;
  final String? error;
  final String? aviso;
  final VoidCallback onPdf;
  final VoidCallback onXml;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceContainerLow,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Titulo('Descargar factura'),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton.icon(
                onPressed: habilitado ? onPdf : null,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                label: const Text('Descargar PDF'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary, minimumSize: const Size(0, 48)),
              ),
              OutlinedButton.icon(
                onPressed: habilitado ? onXml : null,
                icon: const Icon(Icons.code, size: 20),
                label: const Text('Descargar XML'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary, width: 1.5),
                  minimumSize: const Size(0, 48),
                ),
              ),
            ],
          ),
          if (aviso != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(aviso!, style: AppTheme.bodySm(color: AppColors.successText)),
          ],
          if (error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(error!, style: AppTheme.bodySm(color: AppColors.error)),
          ],
        ],
      ),
    );
  }
}
