import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/services.dart';
import '../theme/app_theme.dart';
import '../widgets/alerta.dart';
import 'mapa_asientos.dart';

// Cambia el asiento de una reserva propia: PUT /api/reservas/{id}/asiento (S4).
// El servidor libera el asiento anterior y toma el nuevo en una sola operación; si el nuevo está ocupado responde 409.
class CambiarAsientoDialog extends StatefulWidget {
  const CambiarAsientoDialog({super.key, required this.reserva, required this.token});

  final Reserva reserva;
  final String token;

  @override
  State<CambiarAsientoDialog> createState() => _CambiarAsientoDialogState();
}

class _CambiarAsientoDialogState extends State<CambiarAsientoDialog> {
  final TransformationController _zoom = TransformationController();
  List<Asiento> _asientos = const [];
  bool _cargando = true;
  bool _guardando = false;
  String? _nuevo; // asiento libre elegido para la reserva
  // Versión del mapa que muestra este formulario: se envía al confirmar para detectar cambios.
  int _version = 0;
  String _mensaje = '';
  bool _avisoMapa = false; // true cuando el mapa cambió: se muestra como aviso, no como error

  String? get _actual => widget.reserva.asiento;

  @override
  void initState() {
    super.initState();
    _cargarMapa();
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  Future<void> _cargarMapa() async {
    setState(() => _cargando = true);
    try {
      final mapa = await VuelosService.mapaConVersion(widget.reserva.vueloId);
      if (!mounted) return;
      final nuevos = asientosDesde(mapa.asientos);
      for (final a in nuevos) {
        // Solo el asiento de esta reserva lleva nombre: es del propio cliente.
        if (a.codigo == _actual) {
          a.estado = EstadoAsiento.seleccionado;
          a.nombre = widget.reserva.pasajero;
        }
      }
      setState(() {
        _asientos = nuevos;
        _version = mapa.version;
        _cargando = false;
        // Si el elegido ya no está libre, se descarta. Si sigue libre, se conserva.
        if (_nuevo != null && nuevos.any((a) => a.codigo == _nuevo && a.estado == EstadoAsiento.reservado)) {
          _nuevo = null;
          _mensaje = 'El asiento elegido ya fue tomado por otro pasajero. Elija otro.';
          _avisoMapa = false;
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _mensaje = e.mensaje;
      });
    }
  }

  void _alTocar(Asiento a) {
    if (_cargando || _guardando) return;
    if (a.estado == EstadoAsiento.reservado || a.codigo == _actual) return;
    setState(() {
      _nuevo = a.codigo;
      _mensaje = '';
      for (final x in _asientos) {
        if (x.codigo == _nuevo) {
          x.estado = EstadoAsiento.seleccionado;
          x.nombre = widget.reserva.pasajero;
        } else if (x.codigo != _actual && x.estado == EstadoAsiento.seleccionado) {
          x.estado = EstadoAsiento.disponible;
          x.nombre = null;
        }
      }
    });
  }

  Future<void> _confirmar() async {
    final nuevo = _nuevo;
    if (nuevo == null) return;
    setState(() {
      _guardando = true;
      _mensaje = '';
    });
    try {
      final asiento = await ReservasService.cambiarAsiento(
        id: widget.reserva.id,
        asiento: nuevo,
        token: widget.token,
        versionMapa: _version,
      );
      if (!mounted) return;
      Navigator.of(context).pop(asiento);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.codigo == 'MAPA_DESACTUALIZADO') {
        // Otro pasajero cambió el vuelo: se recarga el mapa y se conserva el asiento elegido si sigue libre.
        setState(() => _guardando = false);
        await _cargarMapa();
        if (!mounted) return;
        setState(() {
          _avisoMapa = true;
          _mensaje =
              'El mapa de asientos cambió: otro pasajero reservó asientos de este vuelo. Revise el mapa y confirme de nuevo.';
        });
        return;
      }
      setState(() {
        _guardando = false;
        _avisoMapa = false;
        _mensaje = e.status == 409 ? 'El asiento $nuevo ya fue tomado por otro pasajero. Elija otro.' : e.mensaje;
      });
      if (e.status == 409) await _cargarMapa();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceContainerLowest,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: AppColors.primaryContainer,
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Cambiar asiento · Reserva #${widget.reserva.id}',
                      style: AppTheme.headlineSm(color: Colors.white).copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Asiento actual: ${_actual ?? 'sin asiento'}. Toca un asiento disponible (negro) para moverte.',
                        style: AppTheme.bodySm(color: AppColors.onSurfaceVariant),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          height: 420,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F9FD),
                            border: Border.all(color: AppColors.surfaceContainerHigh),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: _cargando
                              ? const Center(child: CircularProgressIndicator())
                              : MapaAsientos(asientos: _asientos, controlador: _zoom, onToque: _alTocar),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        _nuevo == null ? 'Ningún asiento nuevo seleccionado.' : 'Nuevo asiento: $_nuevo',
                        style: AppTheme.bodyMd().copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (_mensaje.isNotEmpty && _avisoMapa) ...[
                        const SizedBox(height: AppSpacing.md),
                        Alerta(tipo: TipoAlerta.aviso, texto: _mensaje),
                      ],
                      if (_mensaje.isNotEmpty && !_avisoMapa) ...[
                        const SizedBox(height: AppSpacing.md),
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: AppColors.errorBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.errorBorder),
                          ),
                          child: Text(_mensaje, style: AppTheme.bodySm(color: AppColors.errorText)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Container(
              color: AppColors.surfaceContainerLow,
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cerrar', style: AppTheme.labelLg()),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton.icon(
                    onPressed: (_guardando || _cargando || _nuevo == null) ? null : _confirmar,
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: Text(_guardando ? 'Cambiando...' : 'Confirmar cambio', style: AppTheme.labelLg(color: AppColors.onPrimary)),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
