import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../core/services.dart';
import '../core/session.dart';
import '../theme/app_theme.dart';
import 'cambiar_asiento_dialog.dart';

// Vista de Mis Reservas (mis-reservas.html / mis-reservas.js): GET /api/reservas (S5),
// completa cada reserva con GET /api/vuelos/{id} (S3) y permite cancelar con DELETE (S5).
class MisReservasView extends StatefulWidget {
  const MisReservasView({super.key, required this.onIrALogin});

  final VoidCallback onIrALogin;

  @override
  State<MisReservasView> createState() => _MisReservasViewState();
}

class _MisReservasViewState extends State<MisReservasView> {
  List<Reserva> _reservas = const [];
  final Map<int, Vuelo?> _vuelos = {};
  String _filtro = 'todas';
  String? _sincronizado;
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    session.addListener(_alCambiarSesion);
    reservaCreadaVersion.addListener(_cargar);
    _cargar();
  }

  @override
  void dispose() {
    session.removeListener(_alCambiarSesion);
    reservaCreadaVersion.removeListener(_cargar);
    super.dispose();
  }

  void _alCambiarSesion() {
    if (!session.activa) {
      setState(() => _reservas = const []);
    } else {
      _cargar();
    }
    if (mounted) setState(() {});
  }

  Future<void> _cargar() async {
    final token = session.token;
    if (token == null) {
      setState(() => _reservas = const []);
      return;
    }
    setState(() => _cargando = true);
    try {
      final reservas = await ReservasService.listar(token: token);
      await _cargarVuelos(reservas);
      if (!mounted) return;
      setState(() {
        _reservas = reservas;
        _sincronizado = _horaActual();
      });
    } on SesionExpirada catch (e) {
      session.cerrar();
      if (!mounted) return;
      setState(() => _reservas = const []);
      _toast(e.mensaje, error: true);
    } on ApiException catch (e) {
      _toast(e.mensaje, error: true);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cargarVuelos(List<Reserva> reservas) async {
    final ids = {for (final r in reservas) r.vueloId}.where((id) => !_vuelos.containsKey(id));
    await Future.wait(ids.map((id) async => _vuelos[id] = await VuelosService.obtener(id)));
  }

  String _horaActual() {
    final ahora = DateTime.now();
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(ahora.hour)}:${dos(ahora.minute)}:${dos(ahora.second)}';
  }

  void _toast(String texto, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.inverseSurface,
          content: Row(
            children: [
              Icon(error ? Icons.error_outline : Icons.check_circle_outline, color: AppColors.inverseOnSurface, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(texto, style: AppTheme.bodySm(color: AppColors.inverseOnSurface))),
            ],
          ),
          duration: const Duration(milliseconds: 3500),
        ),
      );
  }

  Future<void> _cambiarAsiento(Reserva reserva) async {
    final token = session.token;
    if (token == null) return;
    final nuevo = await showDialog<String>(
      context: context,
      builder: (_) => CambiarAsientoDialog(reserva: reserva, token: token),
    );
    if (nuevo == null) return;
    _toast('Asiento de la reserva #${reserva.id} cambiado a $nuevo.');
    await _cargar();
  }

  Future<void> _cancelar(Reserva reserva) async {
    final confirmada = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogoCancelar(reserva: reserva, vuelo: _vuelos[reserva.vueloId]),
    );
    if (confirmada != true) return;
    final token = session.token;
    if (token == null) return;
    try {
      await ReservasService.cancelar(id: reserva.id, token: token);
      _toast('Reserva #${reserva.id} cancelada.');
      await _cargar();
    } on ApiException catch (e) {
      _toast(e.mensaje, error: true);
    }
  }

  void _verJson(Reserva reserva) {
    final payload = {
      'reserva': {'id': reserva.id, 'vueloId': reserva.vueloId, 'pasajero': reserva.pasajero, 'estado': reserva.estado},
      'vuelo': _vuelos[reserva.vueloId] == null ? null : _vueloJson(_vuelos[reserva.vueloId]!),
    };
    showDialog<void>(
      context: context,
      builder: (_) => _DialogoJson(titulo: 'Reserva #${reserva.id} · GET /api/reservas', contenido: const JsonEncoder.withIndent('  ').convert(payload)),
    );
  }

  Map<String, dynamic> _vueloJson(Vuelo v) => {
        'id': v.id,
        'origen': v.origen,
        'destino': v.destino,
        'fecha': v.fecha,
        'hora': v.hora,
        'precio': v.precio,
        'asientosDisponibles': v.asientosDisponibles,
      };

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final margen = ancho >= 768 ? AppSpacing.margin : AppSpacing.marginMobile;
    final visibles = _reservas.where((r) => _filtro == 'todas' || r.estado == _filtro).toList();
    final confirmadas = _reservas.where((r) => r.confirmada).toList();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: margen, vertical: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Encabezado(sincronizado: _sincronizado, cargando: _cargando, onActualizar: _cargar),
          const SizedBox(height: AppSpacing.lg),
          session.activa ? _BannerSesion(email: session.email ?? '') : _BannerInvitado(onIrALogin: widget.onIrALogin),
          const SizedBox(height: AppSpacing.lg),
          _Filtros(
            filtro: _filtro,
            total: _reservas.length,
            confirmadas: confirmadas.length,
            canceladas: _reservas.where((r) => r.estado == 'cancelada').length,
            onCambiar: (f) => setState(() => _filtro = f),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (!session.activa)
            _Mensaje('Inicie sesión para ver sus reservas.')
          else if (_reservas.isEmpty)
            _Mensaje('Todavía no tiene reservas.')
          else if (visibles.isEmpty)
            _Mensaje('No hay reservas con ese filtro.')
          else
            for (final r in visibles) ...[
              _TarjetaReserva(
                reserva: r,
                vuelo: _vuelos[r.vueloId],
                onVerJson: () => _verJson(r),
                onCancelar: () => _cancelar(r),
                onCambiarAsiento: () => _cambiarAsiento(r),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          const SizedBox(height: AppSpacing.md),
          _Resumen(confirmadas: confirmadas, vuelos: _vuelos),
        ],
      ),
    );
  }
}

class _Mensaje extends StatelessWidget {
  const _Mensaje(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Text(texto, style: AppTheme.bodyMd(color: AppColors.onSurfaceVariant));
}

class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.sincronizado, required this.cargando, required this.onActualizar});

  final String? sincronizado;
  final bool cargando;
  final VoidCallback onActualizar;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.surfaceContainerHigh, borderRadius: BorderRadius.circular(999)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.secondary, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text('CLUSTER ACTIVO', style: AppTheme.telemetry(size: 12, color: AppColors.onSurfaceVariant)),
                    ],
                  ),
                ),
                Text(
                  'GET /api/reservas · S5 :5005 · vuelos S3 :5003',
                  style: AppTheme.telemetry(size: 12, weight: FontWeight.w700, color: AppColors.secondary),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text('Mis Reservas y Pasajes de Abordo', style: AppTheme.headlineLg()),
            const SizedBox(height: 4),
            SizedBox(
              width: 560,
              child: Text(
                'Consulta y cancelación de tus reservas, sincronizadas con el servicio de gestión.',
                style: AppTheme.bodyMd(color: AppColors.onSurfaceVariant),
              ),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Última sincronización: ', style: AppTheme.telemetry(size: 11, color: AppColors.onSurfaceVariant)),
            Text(sincronizado ?? '—', style: AppTheme.telemetry(size: 11, weight: FontWeight.w700, color: AppColors.onSurface)),
            const SizedBox(width: AppSpacing.md),
            FilledButton.icon(
              onPressed: cargando ? null : onActualizar,
              icon: cargando
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.sync, size: 18),
              label: Text('Actualizar mis reservas', style: AppTheme.labelLg(color: AppColors.onPrimary)),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
            ),
          ],
        ),
      ],
    );
  }
}

class _BannerSesion extends StatelessWidget {
  const _BannerSesion({required this.email});
  final String email;

  @override
  Widget build(BuildContext context) {
    return _Caja(
      color: AppColors.surfaceContainerLowest,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: AppColors.secondary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.verified_user, color: AppColors.secondary, size: 26),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Sesión verificada', style: AppTheme.headlineSm()),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.surfaceContainerHigh, borderRadius: BorderRadius.circular(999)),
                      child: Text(email, style: AppTheme.telemetry(size: 12, color: AppColors.onSurfaceVariant)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text('Mostrando solo las reservas de esta cuenta.', style: AppTheme.bodySm(color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BannerInvitado extends StatelessWidget {
  const _BannerInvitado({required this.onIrALogin});
  final VoidCallback onIrALogin;

  @override
  Widget build(BuildContext context) {
    return _Caja(
      color: const Color(0xFFFFF4D6),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(color: AppColors.tertiaryFixed, shape: BoxShape.circle),
            child: const Icon(Icons.lock, color: AppColors.onTertiaryFixed, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sesión requerida', style: AppTheme.headlineSm()),
                Text('Inicie sesión para ver y administrar sus reservas.', style: AppTheme.bodySm(color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),
          FilledButton(
            onPressed: onIrALogin,
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text('Iniciar sesión ahora', style: AppTheme.labelLg(color: AppColors.onPrimary)),
          ),
        ],
      ),
    );
  }
}

class _Caja extends StatelessWidget {
  const _Caja({required this.child, required this.color});
  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: child,
    );
  }
}

class _Filtros extends StatelessWidget {
  const _Filtros({required this.filtro, required this.total, required this.confirmadas, required this.canceladas, required this.onCambiar});

  final String filtro;
  final int total;
  final int confirmadas;
  final int canceladas;
  final ValueChanged<String> onCambiar;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: BorderRadius.circular(12)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Filtro(texto: 'Todas las reservas', contador: total, activo: filtro == 'todas', onTap: () => onCambiar('todas')),
              _Filtro(texto: 'Confirmadas', contador: confirmadas, activo: filtro == 'confirmada', onTap: () => onCambiar('confirmada')),
              _Filtro(texto: 'Canceladas', contador: canceladas, activo: filtro == 'cancelada', onTap: () => onCambiar('cancelada')),
            ],
          ),
        ),
        Text('Total de registros: $total', style: AppTheme.telemetry(size: 12, color: AppColors.onSurfaceVariant)),
      ],
    );
  }
}

class _Filtro extends StatelessWidget {
  const _Filtro({required this.texto, required this.contador, required this.activo, required this.onTap});

  final String texto;
  final int contador;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: activo ? AppColors.surfaceContainerLowest : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: activo ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 2)] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(texto, style: AppTheme.labelLg(color: activo ? AppColors.onSurface : AppColors.onSurfaceVariant).copyWith(fontWeight: activo ? FontWeight.w700 : FontWeight.w600)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(color: AppColors.surfaceContainerHigh, borderRadius: BorderRadius.circular(999)),
              child: Text('$contador', style: AppTheme.telemetry(size: 11, color: AppColors.onSurfaceVariant)),
            ),
          ],
        ),
      ),
    );
  }
}

class _TarjetaReserva extends StatelessWidget {
  const _TarjetaReserva({
    required this.reserva,
    required this.vuelo,
    required this.onVerJson,
    required this.onCancelar,
    required this.onCambiarAsiento,
  });

  final Reserva reserva;
  final Vuelo? vuelo;
  final VoidCallback onVerJson;
  final VoidCallback onCancelar;
  final VoidCallback onCambiarAsiento;

  @override
  Widget build(BuildContext context) {
    final confirmada = reserva.confirmada;
    final contenido = Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceVariant),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Cabecera(reserva: reserva, vuelo: vuelo),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (vuelo != null) ...[_Ruta(vuelo: vuelo!), const SizedBox(height: AppSpacing.lg)],
                _DatosGrid(reserva: reserva, vuelo: vuelo),
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.surfaceVariant.withValues(alpha: 0.6)))),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      Text('ID reserva: ${reserva.id} · ID vuelo: ${reserva.vueloId}', style: AppTheme.telemetry(size: 12, color: AppColors.onSurfaceVariant)),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OutlinedButton(
                            onPressed: onVerJson,
                            style: OutlinedButton.styleFrom(
                              backgroundColor: AppColors.surfaceContainerHighest,
                              foregroundColor: AppColors.onSurface,
                              side: BorderSide.none,
                            ),
                            child: Text('Ver JSON', style: AppTheme.labelMd(color: AppColors.onSurface)),
                          ),
                          if (confirmada) ...[
                            const SizedBox(width: AppSpacing.sm),
                            OutlinedButton(
                              onPressed: onCambiarAsiento,
                              child: Text('Cambiar asiento', style: AppTheme.labelMd(color: AppColors.onSurface)),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            FilledButton(
                              onPressed: onCancelar,
                              style: FilledButton.styleFrom(backgroundColor: AppColors.errorContainer, foregroundColor: AppColors.onErrorContainer),
                              child: Text('Cancelar reserva', style: AppTheme.labelMd(color: AppColors.onErrorContainer)),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (confirmada) return contenido;
    // Canceladas: opacidad 0.45 y escala de grises, como .reserva[data-estado="cancelada"].
    return Opacity(
      opacity: 0.45,
      child: ColorFiltered(colorFilter: const ColorFilter.matrix(_matrizGris), child: contenido),
    );
  }
}

const List<double> _matrizGris = [
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, 1, 0,
];

class _Cabecera extends StatelessWidget {
  const _Cabecera({required this.reserva, required this.vuelo});

  final Reserva reserva;
  final Vuelo? vuelo;

  @override
  Widget build(BuildContext context) {
    final confirmada = reserva.confirmada;
    return Container(
      color: AppColors.surfaceContainerLow.withValues(alpha: 0.6),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Reserva #${reserva.id}', style: AppTheme.headlineSm().copyWith(fontWeight: FontWeight.w700)),
                Text(
                  vuelo != null ? 'Vuelo #${vuelo!.id}' : 'Vuelo #${reserva.vueloId} (no disponible)',
                  style: AppTheme.telemetry(size: 12, weight: FontWeight.w600, color: AppColors.secondary),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: confirmada ? AppColors.secondaryFixed : AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              confirmada ? 'CONFIRMADA' : 'CANCELADA',
              style: AppTheme.telemetry(size: 12, weight: FontWeight.w700, color: confirmada ? AppColors.onSecondaryFixed : AppColors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _Ruta extends StatelessWidget {
  const _Ruta({required this.vuelo});
  final Vuelo vuelo;

  @override
  Widget build(BuildContext context) {
    Widget extremo(String etiqueta, String codigo, CrossAxisAlignment alineacion) {
      return Column(
        crossAxisAlignment: alineacion,
        children: [
          Text(etiqueta.toUpperCase(), style: AppTheme.telemetry(size: 12, color: AppColors.onSurfaceVariant)),
          Text(codigo, style: AppTheme.headlineXl().copyWith(fontSize: 40, height: 1)),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: extremo('Origen', vuelo.origen, CrossAxisAlignment.start)),
        Text('→', style: AppTheme.telemetry(size: 20, color: AppColors.secondary)),
        Expanded(child: extremo('Destino', vuelo.destino, CrossAxisAlignment.end)),
      ],
    );
  }
}

class _DatosGrid extends StatelessWidget {
  const _DatosGrid({required this.reserva, required this.vuelo});

  final Reserva reserva;
  final Vuelo? vuelo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: BorderRadius.circular(12)),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [
          _Dato('Pasajero', reserva.pasajero),
          _Dato('Asiento', reserva.asiento ?? 'Sin asiento'),
          _Dato('Fecha', vuelo?.fecha ?? '—'),
          _Dato('Hora de salida', vuelo?.hora ?? '—'),
          _Dato('Precio', vuelo == null ? '—' : '\$${vuelo!.precio.toStringAsFixed(2)} USD'),
          _Dato('Asientos disponibles', vuelo == null ? '—' : '${vuelo!.asientosDisponibles}'),
        ],
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.etiqueta, this.valor);

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 140, maxWidth: 240),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta.toUpperCase(), style: AppTheme.labelSm(color: AppColors.onSurfaceVariant)),
          Text(valor, style: AppTheme.headlineSm().copyWith(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _Resumen extends StatelessWidget {
  const _Resumen({required this.confirmadas, required this.vuelos});

  final List<Reserva> confirmadas;
  final Map<int, Vuelo?> vuelos;

  @override
  Widget build(BuildContext context) {
    final monto = confirmadas.fold<double>(0, (suma, r) => suma + (vuelos[r.vueloId]?.precio ?? 0));
    final proximos = confirmadas.map((r) => vuelos[r.vueloId]).whereType<Vuelo>().toList()..sort((a, b) => '${a.fecha} ${a.hora}'.compareTo('${b.fecha} ${b.hora}'));
    final proximo = proximos.isEmpty ? null : proximos.first;

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        _TarjetaResumen(
          titulo: 'Reservas confirmadas',
          valor: '${confirmadas.length}',
        ),
        _TarjetaResumen(
          titulo: 'Monto de reservas confirmadas',
          valor: '\$${monto.toStringAsFixed(2)}',
          pie: 'USD, según el precio del vuelo',
        ),
        _TarjetaResumen(
          titulo: 'Próxima salida',
          valor: proximo == null ? '—' : '${proximo.fecha} · ${proximo.hora}',
          pie: proximo == null ? '' : 'Vuelo #${proximo.id}: ${proximo.origen} → ${proximo.destino}',
        ),
      ],
    );
  }
}

class _TarjetaResumen extends StatelessWidget {
  const _TarjetaResumen({required this.titulo, required this.valor, this.pie});

  final String titulo;
  final String valor;
  final String? pie;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 360),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.surfaceVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo.toUpperCase(), style: AppTheme.telemetry(size: 11, weight: FontWeight.w600, color: AppColors.onSurfaceVariant)),
            Text(valor, style: AppTheme.headlineLg().copyWith(fontWeight: FontWeight.w800, height: 1.2)),
            if (pie != null && pie!.isNotEmpty) Text(pie!, style: AppTheme.bodySm(color: AppColors.onSurfaceVariant).copyWith(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _DialogoCancelar extends StatelessWidget {
  const _DialogoCancelar({required this.reserva, required this.vuelo});

  final Reserva reserva;
  final Vuelo? vuelo;

  @override
  Widget build(BuildContext context) {
    final ruta = vuelo == null ? 'vuelo #${reserva.vueloId}' : '${vuelo!.origen} → ${vuelo!.destino}';
    return Dialog(
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(color: AppColors.errorContainer, shape: BoxShape.circle),
                  child: const Icon(Icons.warning, color: AppColors.error, size: 22),
                ),
                const SizedBox(width: AppSpacing.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Confirmar cancelación', style: AppTheme.headlineSm()),
                    Text('DELETE /api/reservas/{id}', style: AppTheme.telemetry(color: AppColors.error)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text.rich(
              TextSpan(
                style: AppTheme.bodyMd(color: AppColors.onSurfaceVariant),
                children: [
                  const TextSpan(text: '¿Desea cancelar la reserva '),
                  TextSpan(text: '#${reserva.id} ($ruta)', style: AppTheme.bodyMd().copyWith(fontWeight: FontWeight.w700)),
                  const TextSpan(text: '?'),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: TextButton.styleFrom(backgroundColor: AppColors.surfaceContainer, foregroundColor: AppColors.onSurface),
                  child: Text('Mantener reserva', style: AppTheme.labelMd(color: AppColors.onSurface)),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.delete_forever, size: 16),
                  label: Text('Sí, cancelar reserva', style: AppTheme.labelMd(color: AppColors.onError)),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogoJson extends StatelessWidget {
  const _DialogoJson({required this.titulo, required this.contenido});

  final String titulo;
  final String contenido;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 672, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(titulo, style: AppTheme.headlineSm(color: Colors.white))),
                  IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close, color: Colors.white)),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(8)),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      contenido,
                      style: AppTheme.telemetry(size: 12, color: AppColors.secondaryFixed).copyWith(height: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => Clipboard.setData(ClipboardData(text: contenido)),
                  icon: const Icon(Icons.content_copy, size: 14),
                  label: Text('Copiar JSON', style: AppTheme.labelSm(color: Colors.white)),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.secondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
