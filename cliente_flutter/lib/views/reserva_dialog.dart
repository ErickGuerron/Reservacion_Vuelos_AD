import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../core/services.dart';
import '../core/validadores.dart';
import '../theme/app_theme.dart';
import 'mapa_asientos.dart';

enum _Estado { listo, enviando, ok, error }

// Modal de reserva: el pasajero elige asientos del mapa real de S3 y da el nombre de cada uno.
// Cada asiento se envía en POST /api/reservas (S4). Si otro pasajero lo tomó primero (409), se quita y se avisa.
class ReservaDialog extends StatefulWidget {
  const ReservaDialog({super.key, required this.vuelo, required this.token});

  final Vuelo vuelo;
  final String token;

  @override
  State<ReservaDialog> createState() => _ReservaDialogState();
}

class _ReservaDialogState extends State<ReservaDialog> {
  final TransformationController _zoom = TransformationController();
  List<Asiento> _asientos = const [];
  bool _cargandoMapa = true;
  // Nombre de cada asiento que este cliente tiene elegido o ya confirmó.
  final Map<String, String> _nombres = {};
  final Set<String> _creados = {};
  final List<Reserva> _reservas = [];
  _Estado _estado = _Estado.listo;
  String _mensaje = '';

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

  List<Asiento> get _seleccionados => _asientos.where((a) => a.estado == EstadoAsiento.seleccionado).toList();

  // Asientos elegidos que todavía no se confirmaron en el servicio.
  List<Asiento> get _pendientes => _seleccionados.where((a) => !_creados.contains(a.codigo)).toList();

  bool get _bloqueado => _cargandoMapa || _estado == _Estado.enviando || _estado == _Estado.ok;

  // Pide el mapa a S3 y reaplica lo que este cliente ya eligió. Si un asiento elegido ya no está libre, se quita.
  Future<void> _cargarMapa() async {
    setState(() => _cargandoMapa = true);
    try {
      final remotos = await VuelosService.mapa(widget.vuelo.id);
      if (!mounted) return;
      final nuevos = asientosDesde(remotos);
      final perdidos = <String>[];
      for (final a in nuevos) {
        final nombre = _nombres[a.codigo];
        if (nombre == null) continue;
        if (_creados.contains(a.codigo)) {
          a.estado = EstadoAsiento.seleccionado;
          a.nombre = nombre;
        } else if (a.estado == EstadoAsiento.reservado) {
          perdidos.add(a.codigo);
          _nombres.remove(a.codigo);
        } else {
          a.estado = EstadoAsiento.seleccionado;
          a.nombre = nombre;
        }
      }
      setState(() {
        _asientos = nuevos;
        _cargandoMapa = false;
        if (perdidos.isNotEmpty) {
          _mensaje = 'El asiento ${perdidos.join(', ')} ya fue tomado por otro pasajero. Elija otro.';
          _estado = _Estado.error;
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoMapa = false;
        _mensaje = e.mensaje;
        _estado = _Estado.error;
      });
    }
  }

  Future<void> _alTocar(Asiento a) async {
    if (_bloqueado || a.estado == EstadoAsiento.reservado) return;

    if (a.estado == EstadoAsiento.seleccionado) {
      if (_creados.contains(a.codigo)) return; // ya confirmado: se cambia desde Mis Reservas
      setState(() {
        a.estado = EstadoAsiento.disponible;
        a.nombre = null;
        _nombres.remove(a.codigo);
      });
      return;
    }

    final nombre = await showDialog<String>(
      context: context,
      builder: (_) => _DialogoNombre(codigo: a.codigo),
    );
    if (nombre == null || !mounted) return;
    setState(() {
      a.estado = EstadoAsiento.seleccionado;
      a.nombre = nombre;
      _nombres[a.codigo] = nombre;
    });
  }

  // Todo o nada: un solo lote en S4. Si algún asiento ya fue tomado, el servidor no guarda ninguno.
  Future<void> _confirmar() async {
    final pendientes = _pendientes;
    setState(() {
      _estado = _Estado.enviando;
      _mensaje = '';
    });
    try {
      final reservas = await ReservasService.crearLote(
        vueloId: widget.vuelo.id,
        reservas: [for (final a in pendientes) (pasajero: a.nombre!, asiento: a.codigo)],
        token: widget.token,
      );
      if (!mounted) return;
      setState(() {
        _creados.addAll(pendientes.map((a) => a.codigo));
        _reservas.addAll(reservas);
        _estado = _Estado.ok;
      });
      anunciarReservaCreada();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.status == 409) {
        // Algún asiento ya fue tomado: se refresca el mapa para que el cliente elija de nuevo.
        await _cargarMapa();
        _fallar('Ningún asiento se guardó: alguno de los elegidos ya fue tomado por otro pasajero. Revise el mapa y elija otros.');
        return;
      }
      _fallar(e.mensaje);
    }
  }

  void _fallar(String mensaje) {
    if (!mounted) return;
    setState(() {
      _mensaje = mensaje;
      _estado = _Estado.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final vuelo = widget.vuelo;
    final seleccion = _seleccionados;
    final total = seleccion.length * vuelo.precio;
    final enviando = _estado == _Estado.enviando;
    final ok = _estado == _Estado.ok;

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
            _Cabecera(onCerrar: () => Navigator.of(context).pop()),
            // Cuerpo desplazable: el mapa más los mensajes de estado no deben desbordar la ventana.
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${vuelo.origen} → ${vuelo.destino} · ${vuelo.fecha} · \$${vuelo.precio.toStringAsFixed(2)} USD por pasajero',
                        style: AppTheme.bodySm(color: AppColors.onSurfaceVariant).copyWith(fontWeight: FontWeight.w600),
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
                          child: _cargandoMapa
                              ? const Center(child: CircularProgressIndicator())
                              : MapaAsientos(asientos: _asientos, controlador: _zoom, onToque: _alTocar),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const Wrap(
                        spacing: 16,
                        runSpacing: 6,
                        children: [
                          _Leyenda(color: Color(0xFF111111), texto: 'Disponible'),
                          _Leyenda(color: Colors.white, borde: Color(0xFF9AA3C7), texto: 'Reservado'),
                          _Leyenda(color: Color(0xFF1FA35B), texto: 'Seleccionado / comprado'),
                          _Leyenda(color: Color(0xFF2FB47A), texto: 'Salida de emergencia'),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        seleccion.isEmpty
                            ? 'Toca un asiento disponible (negro) para registrar al pasajero.'
                            : 'Seleccionados: ${seleccion.map((a) => '${a.codigo} · ${a.nombre}').join(', ')}',
                        style: AppTheme.bodySm(color: AppColors.onSurface),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Total (${seleccion.length} pasajero(s))', style: AppTheme.bodyMd().copyWith(fontWeight: FontWeight.w600)),
                          Text('\$${total.toStringAsFixed(2)} USD', style: AppTheme.headlineMd().copyWith(fontWeight: FontWeight.w800)),
                        ],
                      ),
                      if (enviando) ...[
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          children: [
                            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            const SizedBox(width: AppSpacing.sm),
                            Text('Enviando reservas al servicio S4...', style: AppTheme.telemetry(color: AppColors.onSurface)),
                          ],
                        ),
                      ],
                      if (ok) ...[
                        const SizedBox(height: AppSpacing.md),
                        _Caja(
                          color: AppColors.surfaceContainer,
                          child: Text(
                            '¡Reserva confirmada! Números de reserva: ${_reservas.map((r) => '#${r.id}').join(', ')} · estado ${_reservas.first.estado}.',
                            style: AppTheme.bodySm(color: AppColors.onSurface),
                          ),
                        ),
                      ],
                      if (_estado == _Estado.error) ...[
                        const SizedBox(height: AppSpacing.md),
                        _Caja(
                          color: AppColors.errorBg,
                          borderColor: AppColors.errorBorder,
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
                    style: TextButton.styleFrom(
                      backgroundColor: AppColors.surfaceContainerHighest,
                      foregroundColor: AppColors.onSurface,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
                    ),
                    child: Text('Cerrar', style: AppTheme.labelLg()),
                  ),
                  if (!ok) ...[
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton.icon(
                      onPressed: (enviando || _cargandoMapa || _pendientes.isEmpty) ? null : _confirmar,
                      icon: const Icon(Icons.check_circle, size: 18),
                      label: Text('Confirmar reserva', style: AppTheme.labelLg(color: AppColors.onPrimary).copyWith(fontWeight: FontWeight.w700)),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 10),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Pide el nombre del propietario o reservante de un asiento.
class _DialogoNombre extends StatefulWidget {
  const _DialogoNombre({required this.codigo});

  final String codigo;

  @override
  State<_DialogoNombre> createState() => _DialogoNombreState();
}

class _DialogoNombreState extends State<_DialogoNombre> {
  final _nombre = TextEditingController();
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  void _aceptar() {
    if (!_form.currentState!.validate()) return;
    Navigator.of(context).pop(_nombre.text.trim().replaceAll(RegExp(r'\s+'), ' '));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Asiento ${widget.codigo}', style: AppTheme.headlineSm()),
      content: Form(
        key: _form,
        child: TextFormField(
          controller: _nombre,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: 'Nombre y apellido del pasajero', hintText: 'Ej. María Gómez'),
          inputFormatters: [NombrePersonaFormatter()],
          validator: validarNombrePasajero,
          onFieldSubmitted: (_) => _aceptar(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _aceptar, child: const Text('Confirmar')),
      ],
    );
  }
}

class _Leyenda extends StatelessWidget {
  const _Leyenda({required this.color, required this.texto, this.borde});

  final Color color;
  final Color? borde;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            border: borde == null ? null : Border.all(color: borde!),
          ),
        ),
        const SizedBox(width: 6),
        Text(texto, style: AppTheme.labelSm(color: AppColors.onSurfaceVariant)),
      ],
    );
  }
}

class _Cabecera extends StatelessWidget {
  const _Cabecera({required this.onCerrar});
  final VoidCallback onCerrar;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primaryContainer,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(color: AppColors.secondary, shape: BoxShape.circle),
            child: const Icon(Icons.airplane_ticket, color: AppColors.onSecondary, size: 20),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Selecciona tus asientos', style: AppTheme.headlineSm(color: Colors.white).copyWith(fontWeight: FontWeight.w700, height: 1.2)),
                Text('POST /api/reservas · S4 :5004', style: AppTheme.telemetry(color: AppColors.secondaryContainer)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: onCerrar,
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _Caja extends StatelessWidget {
  const _Caja({required this.child, required this.color, this.borderColor});

  final Widget child;
  final Color color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: borderColor == null ? null : Border.all(color: borderColor!),
      ),
      child: child,
    );
  }
}
