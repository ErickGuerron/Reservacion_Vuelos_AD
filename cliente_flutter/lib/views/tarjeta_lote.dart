import 'package:flutter/material.dart';

import '../core/aeropuertos.dart';
import '../core/lotes.dart';
import '../core/models.dart';
import '../theme/app_theme.dart';

// Una compra de varios asientos se muestra como una sola reserva: ruta, fecha, quién viaja en cada
// asiento, total con IVA y las acciones (factura en pantalla, PDF y XML). "Ver detalle" abre un renglón
// por pasajero para cambiar su asiento o cancelarlo.
//
// El cuerpo y el pie van separados (spaceBetween) para que, en una cuadrícula de tarjetas del mismo alto,
// el pie quede siempre alineado abajo.
class TarjetaLote extends StatefulWidget {
  const TarjetaLote({
    super.key,
    required this.grupo,
    required this.vuelo,
    required this.onCambiarAsiento,
    required this.onCancelar,
    required this.onVerFactura,
    this.onDescargarPdf,
    this.onDescargarXml,
  });

  final GrupoReserva grupo;
  final Vuelo? vuelo;
  final ValueChanged<Reserva> onCambiarAsiento;
  final ValueChanged<Reserva> onCancelar;
  final VoidCallback onVerFactura;
  // Descarga directa de la factura sin abrirla. Si no se pasan, los botones no se muestran.
  final VoidCallback? onDescargarPdf;
  final VoidCallback? onDescargarXml;

  @override
  State<TarjetaLote> createState() => _TarjetaLoteState();
}

class _TarjetaLoteState extends State<TarjetaLote> {
  bool _detalle = false;

  @override
  Widget build(BuildContext context) {
    final grupo = widget.grupo;
    final vuelo = widget.vuelo;
    final confirmado = grupo.confirmada;
    final pasajeros = grupo.confirmadas;
    final conFactura = confirmado && grupo.loteId != null;

    final tarjeta = Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceVariant),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    Text(
                      'RESERVA #${grupo.loteId ?? grupo.reservas.first.id}',
                      style: AppTheme.telemetry(size: 12, weight: FontWeight.w700, color: AppColors.secondary),
                    ),
                    _Estado(confirmado: confirmado),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _Ruta(vuelo: vuelo, vueloId: grupo.vueloId),
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: BorderRadius.circular(12)),
                  child: Wrap(
                    spacing: AppSpacing.lg,
                    runSpacing: AppSpacing.sm,
                    children: [
                      _Dato(etiqueta: 'Fecha', valor: vuelo?.fecha ?? '—'),
                      _Dato(etiqueta: 'Salida', valor: vuelo == null ? '—' : '${vuelo.hora} h'),
                      _Dato(etiqueta: 'Pasajeros', valor: '${pasajeros.length}'),
                    ],
                  ),
                ),
                if (!_detalle && pasajeros.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text('ASIENTOS', style: AppTheme.labelSm(color: AppColors.onSurfaceVariant)),
                  const SizedBox(height: AppSpacing.xs),
                  for (final r in pasajeros) _FilaAsiento(reserva: r),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.surfaceVariant))),
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            'TOTAL · IVA $ivaPorcentaje % INCLUIDO',
                            style: AppTheme.labelSm(color: AppColors.onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          grupo.total == 0 ? '—' : '\$${grupo.totalConIva.toStringAsFixed(2)}',
                          style: AppTheme.headlineMd(color: confirmado ? AppColors.onSurface : AppColors.onSurfaceVariant).copyWith(
                            fontWeight: FontWeight.w800,
                            decoration: confirmado ? null : TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (conFactura)
                          FilledButton.icon(
                            onPressed: widget.onVerFactura,
                            icon: const Icon(Icons.receipt_long, size: 18),
                            label: const Text('Ver factura'),
                            style: FilledButton.styleFrom(backgroundColor: AppColors.primary, minimumSize: const Size(0, 44)),
                          ),
                        if (conFactura && widget.onDescargarPdf != null)
                          OutlinedButton(
                            onPressed: widget.onDescargarPdf,
                            style: _estiloDescarga,
                            child: const Text('PDF', semanticsLabel: 'Descargar factura en PDF'),
                          ),
                        if (conFactura && widget.onDescargarXml != null)
                          OutlinedButton(
                            onPressed: widget.onDescargarXml,
                            style: _estiloDescarga,
                            child: const Text('XML', semanticsLabel: 'Descargar factura en XML'),
                          ),
                        TextButton.icon(
                          onPressed: () => setState(() => _detalle = !_detalle),
                          icon: Icon(_detalle ? Icons.expand_less : Icons.expand_more, size: 18),
                          label: Text(_detalle ? 'Ocultar detalle' : 'Ver detalle'),
                          style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_detalle) _Pasajeros(reservas: grupo.reservas, onCambiarAsiento: widget.onCambiarAsiento, onCancelar: widget.onCancelar),
            ],
          ),
        ],
      ),
    );

    // Lote cancelado por completo: se muestra apagado, igual que las reservas canceladas de la app web.
    return confirmado ? tarjeta : Opacity(opacity: 0.6, child: tarjeta);
  }

  static final ButtonStyle _estiloDescarga = OutlinedButton.styleFrom(
    foregroundColor: AppColors.primary,
    side: const BorderSide(color: AppColors.primary, width: 1.5),
    minimumSize: const Size(56, 44),
  );
}

class _Ruta extends StatelessWidget {
  const _Ruta({required this.vuelo, required this.vueloId});

  final Vuelo? vuelo;
  final int vueloId;

  @override
  Widget build(BuildContext context) {
    final v = vuelo;
    if (v == null) return Text('Vuelo #$vueloId', style: AppTheme.headlineSm());
    return Row(
      children: [
        _Aeropuerto(codigo: v.origen, alineacion: CrossAxisAlignment.start),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
              children: [
                const Expanded(child: Divider(color: AppColors.outlineVariant, thickness: 2)),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Icon(Icons.flight, size: 20)),
                const Expanded(child: Divider(color: AppColors.outlineVariant, thickness: 2)),
              ],
            ),
          ),
        ),
        _Aeropuerto(codigo: v.destino, alineacion: CrossAxisAlignment.end),
      ],
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
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 110),
      child: Column(
        crossAxisAlignment: alineacion,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(codigo, style: AppTheme.headlineLg().copyWith(fontWeight: FontWeight.w800)),
          if (ciudad.isNotEmpty)
            Text(ciudad, style: AppTheme.bodySm(color: AppColors.onSurfaceVariant), overflow: TextOverflow.ellipsis, maxLines: 1),
        ],
      ),
    );
  }
}

class _Estado extends StatelessWidget {
  const _Estado({required this.confirmado});

  final bool confirmado;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: confirmado ? AppColors.secondaryFixed : AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        confirmado ? 'CONFIRMADA' : 'CANCELADA',
        style: AppTheme.telemetry(
          size: 12,
          weight: FontWeight.w700,
          color: confirmado ? AppColors.onSecondaryFixed : AppColors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.etiqueta, required this.valor});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 72, maxWidth: 160),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(etiqueta.toUpperCase(), style: AppTheme.labelSm(color: AppColors.onSurfaceVariant)),
          Text(valor, style: AppTheme.bodyMd().copyWith(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// Resumen de un pasajero: asiento y nombre.
class _FilaAsiento extends StatelessWidget {
  const _FilaAsiento({required this.reserva});

  final Reserva reserva;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
            child: Text(
              reserva.asiento ?? '—',
              textAlign: TextAlign.center,
              style: AppTheme.telemetry(size: 13, weight: FontWeight.w700, color: AppColors.onPrimary),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(reserva.pasajero, style: AppTheme.bodyMd().copyWith(fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

// Detalle del lote: un renglón por pasajero, con su asiento, su documento y sus acciones.
class _Pasajeros extends StatelessWidget {
  const _Pasajeros({required this.reservas, required this.onCambiarAsiento, required this.onCancelar});

  final List<Reserva> reservas;
  final ValueChanged<Reserva> onCambiarAsiento;
  final ValueChanged<Reserva> onCancelar;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final r in reservas)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            decoration: const BoxDecoration(
              color: AppColors.surfaceContainerLow,
              border: Border(top: BorderSide(color: AppColors.surfaceVariant)),
            ),
            child: Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 140, maxWidth: 260),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.pasajero, style: AppTheme.bodyMd().copyWith(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                      Text(
                        r.asiento == null ? 'Sin asiento' : 'Asiento ${r.asiento}',
                        style: AppTheme.telemetry(size: 12, color: AppColors.onSurfaceVariant),
                      ),
                      if (r.documentoEtiqueta != null)
                        Text(r.documentoEtiqueta!, style: AppTheme.telemetry(size: 12, color: AppColors.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (!r.confirmada)
                  Text('Cancelado', style: AppTheme.labelMd(color: AppColors.onSurfaceVariant))
                else
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      OutlinedButton(
                        onPressed: () => onCambiarAsiento(r),
                        child: Text('Cambiar asiento', style: AppTheme.labelMd(color: AppColors.onSurface)),
                      ),
                      TextButton(
                        onPressed: () => onCancelar(r),
                        style: TextButton.styleFrom(foregroundColor: AppColors.error),
                        child: Text('Cancelar', style: AppTheme.labelMd(color: AppColors.error)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
