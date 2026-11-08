import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../core/api_config.dart';
import '../theme/app_theme.dart';

// Consola de auditoría (consola-api.html / consola-api.js): muestra los intercambios HTTP reales
// del cliente y el estado de cada servicio con un sondeo a GET /openapi.json.
class _Servicio {
  const _Servicio(this.clave, this.nombre, this.codigo, this.url);
  final String clave;
  final String nombre;
  final String codigo;
  final String url;
}

const _servicios = [
  _Servicio('5001', 'Registro de usuarios', 'S1', ApiConfig.usuarios),
  _Servicio('5002', 'Autenticación', 'S2', ApiConfig.autenticacion),
  _Servicio('5003', 'Consulta de vuelos', 'S3', ApiConfig.vuelos),
  _Servicio('5004', 'Reserva de vuelos', 'S4', ApiConfig.reservas),
  _Servicio('5005', 'Gestión de reservas', 'S5', ApiConfig.gestion),
];

// Estado del sondeo de un servicio.
class _EstadoServicio {
  const _EstadoServicio({this.texto = 'Sin verificar', this.activo, this.ms});
  final String texto;
  final bool? activo; // null = sin verificar
  final int? ms;
}

class ConsolaView extends StatefulWidget {
  const ConsolaView({super.key});

  @override
  State<ConsolaView> createState() => _ConsolaViewState();
}

class _ConsolaViewState extends State<ConsolaView> {
  String _filtro = 'todos';
  bool _enPausa = false;
  final Map<String, _EstadoServicio> _estados = {for (final s in _servicios) s.clave: const _EstadoServicio()};
  final Set<String> _abiertos = {};

  @override
  void initState() {
    super.initState();
    ApiClient.cambios.addListener(_alCambiarRegistro);
    _verificar();
  }

  @override
  void dispose() {
    ApiClient.cambios.removeListener(_alCambiarRegistro);
    super.dispose();
  }

  // Igual que el evento "http:intercambio": en pausa no se repinta el terminal.
  void _alCambiarRegistro() {
    if (!_enPausa && mounted) setState(() {});
  }

  Future<void> _verificar() async {
    for (final s in _servicios) {
      final inicio = DateTime.now();
      try {
        final respuesta = await ApiClient.enviar('GET', Uri.parse('${s.url}/openapi.json'));
        final ms = DateTime.now().difference(inicio).inMilliseconds;
        if (!mounted) return;
        setState(() => _estados[s.clave] = respuesta.ok
            ? _EstadoServicio(texto: 'ACTIVO', activo: true, ms: ms)
            : _EstadoServicio(texto: 'HTTP ${respuesta.status}', activo: false, ms: ms));
      } on ApiException {
        if (!mounted) return;
        setState(() => _estados[s.clave] = const _EstadoServicio(texto: 'SIN RESPUESTA', activo: false));
      }
    }
  }

  void _notificar(String texto) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primary,
        content: Text(texto, style: AppTheme.labelMd(color: Colors.white)),
        duration: const Duration(milliseconds: 2500),
      ));
  }

  List<ApiExchangeView> get _registrosFiltrados {
    final todos = ApiClient.registro.reversed;
    return [
      for (final e in todos)
        if (_filtro == 'todos' || e.puertoServicio == _filtro) ApiExchangeView(e),
    ];
  }

  int? get _latenciaPromedio {
    final validos = ApiClient.registro.where((e) => e.status != 0).toList();
    if (validos.isEmpty) return null;
    return (validos.fold<int>(0, (s, e) => s + e.ms) / validos.length).round();
  }

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final margen = ancho >= 768 ? AppSpacing.margin : AppSpacing.marginMobile;
    final latencia = _latenciaPromedio;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: margen, vertical: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _Chip(texto: 'Consola de auditoría', fondo: AppColors.primary, color: AppColors.onPrimary, negrita: true),
                        const SizedBox(width: AppSpacing.sm),
                        _Chip(
                          texto: _enPausa ? 'Captura en pausa' : 'Captura activa',
                          fondo: AppColors.secondaryContainer.withValues(alpha: 0.9),
                          color: AppColors.onSecondaryContainer,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text('Intercambio HTTP / JSON entre servicios', style: AppTheme.headlineLg()),
                    const SizedBox(height: 4),
                    Text(
                      'Cada llamada que hace el cliente a los servicios S1 (:5001), S2 (:5002), S3 (:5003), S4 (:5004) y S5 (:5005) aparece aquí con su petición, su respuesta y su tiempo.',
                      style: AppTheme.bodyMd(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Latencia promedio: ', style: AppTheme.telemetry(size: 12, color: AppColors.onSurface)),
                        Text(latencia == null ? '—' : '$latencia ms', style: AppTheme.telemetry(size: 12, weight: FontWeight.w700, color: AppColors.secondary)),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(ApiClient.registro.map((e) => e.toJson()).toList())));
                      _notificar('Registro completo copiado');
                    },
                    icon: const Icon(Icons.content_copy, size: 18),
                    label: const Text('Copiar JSON'),
                    style: OutlinedButton.styleFrom(backgroundColor: AppColors.surfaceContainerHigh, foregroundColor: AppColors.onSurface, side: BorderSide.none),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      ApiClient.registro.clear();
                      setState(() => _abiertos.clear());
                      _notificar('Consola vaciada');
                    },
                    icon: const Icon(Icons.cleaning_services, size: 18),
                    label: const Text('Limpiar consola'),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),

          // Malla de servicios: sondeo real GET /openapi.json.
          Row(
            children: [
              const Icon(Icons.hub, size: 16, color: AppColors.secondary),
              const SizedBox(width: 4),
              Expanded(child: Text('SERVICIOS (:5001 - :5005)', style: AppTheme.labelMd(color: AppColors.onSurfaceVariant).copyWith(letterSpacing: 1))),
              TextButton(
                onPressed: _verificar,
                child: Text('Verificar ahora', style: AppTheme.telemetry(size: 12, weight: FontWeight.w600, color: AppColors.secondary)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _Malla(estados: _estados),
          const SizedBox(height: AppSpacing.lg),

          // Filtros y pausa.
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppColors.surfaceContainerLowest, borderRadius: BorderRadius.circular(12)),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _FiltroChip(texto: 'Todos', activo: _filtro == 'todos', onTap: () => setState(() => _filtro = 'todos')),
                for (final s in _servicios)
                  _FiltroChip(
                    texto: '${s.codigo} ${s.nombre} (:${s.clave})',
                    activo: _filtro == s.clave,
                    onTap: () => setState(() => _filtro = s.clave),
                  ),
                TextButton.icon(
                  onPressed: () {
                    setState(() => _enPausa = !_enPausa);
                    _notificar(_enPausa ? 'Captura en pausa' : 'Captura reanudada');
                  },
                  icon: Container(width: 8, height: 8, decoration: BoxDecoration(color: _enPausa ? AppColors.outline : AppColors.secondary, shape: BoxShape.circle)),
                  label: Text(_enPausa ? 'En pausa' : 'En vivo', style: AppTheme.telemetry(size: 11, weight: FontWeight.w600, color: AppColors.secondary)),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Terminal de intercambios.
          _Terminal(
            registros: _registrosFiltrados,
            abiertos: _abiertos,
            totalEventos: ApiClient.registro.length,
            onAlternar: (clave, abierto) => setState(() => abierto ? _abiertos.add(clave) : _abiertos.remove(clave)),
            onCopiar: (e) {
              Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(e.toJson())));
              _notificar('Intercambio copiado');
            },
          ),
        ],
      ),
    );
  }
}

// Envoltorio ligero para una entrada del registro con su clave estable.
class ApiExchangeView {
  ApiExchangeView(this.exchange);
  final HttpExchange exchange;
  String get clave => '${exchange.fecha.toIso8601String()}|${exchange.metodo}|${exchange.url}';
}

class _Malla extends StatelessWidget {
  const _Malla({required this.estados});
  final Map<String, _EstadoServicio> estados;

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final columnas = ancho >= 1024 ? 5 : (ancho >= 640 ? 2 : 1);
    const espacio = AppSpacing.md;
    return LayoutBuilder(
      builder: (_, c) {
        final ancho = (c.maxWidth - espacio * (columnas - 1)) / columnas;
        return Wrap(
          spacing: espacio,
          runSpacing: espacio,
          children: [
            for (final s in _servicios)
              SizedBox(width: ancho, child: _TarjetaServicio(servicio: s, estado: estados[s.clave] ?? const _EstadoServicio())),
          ],
        );
      },
    );
  }
}

class _TarjetaServicio extends StatelessWidget {
  const _TarjetaServicio({required this.servicio, required this.estado});

  final _Servicio servicio;
  final _EstadoServicio estado;

  @override
  Widget build(BuildContext context) {
    final color = estado.activo == null
        ? AppColors.outlineVariant
        : (estado.activo! ? AppColors.secondary : AppColors.error);
    return Container(
      decoration: BoxDecoration(color: AppColors.surfaceContainerLowest, borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 4, color: color),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(servicio.codigo, style: AppTheme.telemetry(size: 18, weight: FontWeight.w700, color: AppColors.onSurface)),
                          Text(servicio.nombre, style: AppTheme.labelMd(color: AppColors.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.surfaceContainerHigh, borderRadius: BorderRadius.circular(999)),
                      child: Text(':${servicio.clave}', style: AppTheme.telemetry(size: 11, weight: FontWeight.w700, color: AppColors.onSurface)),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          estado.texto,
                          style: AppTheme.telemetry(size: 11, weight: FontWeight.w600, color: estado.activo == false ? AppColors.error : (estado.activo == true ? AppColors.secondary : AppColors.onSurfaceVariant)),
                        ),
                      ),
                      Text(estado.ms == null ? '' : '${estado.ms} ms', style: AppTheme.telemetry(size: 10, color: AppColors.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Terminal extends StatelessWidget {
  const _Terminal({
    required this.registros,
    required this.abiertos,
    required this.totalEventos,
    required this.onAlternar,
    required this.onCopiar,
  });

  final List<ApiExchangeView> registros;
  final Set<String> abiertos;
  final int totalEventos;
  final void Function(String clave, bool abierto) onAlternar;
  final ValueChanged<HttpExchange> onCopiar;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppColors.primaryContainer, borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.tertiaryContainer.withValues(alpha: 0.9),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
            child: Row(
              children: [
                Expanded(child: Text('registro de intercambios HTTP', style: AppTheme.telemetry(size: 12, color: AppColors.onPrimaryContainer))),
                Text('$totalEventos eventos', style: AppTheme.telemetry(size: 12, color: AppColors.onPrimaryContainer)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: registros.isEmpty
                ? Text(
                    'Sin intercambios todavía. Use la vista de vuelos, reservas o el login para verlos aquí.',
                    style: AppTheme.bodyMd(color: AppColors.onPrimaryContainer),
                  )
                : Column(
                    children: [
                      for (final r in registros)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: _Intercambio(
                            exchange: r.exchange,
                            abierto: abiertos.contains(r.clave),
                            onAlternar: (a) => onAlternar(r.clave, a),
                            onCopiar: () => onCopiar(r.exchange),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Intercambio extends StatelessWidget {
  const _Intercambio({required this.exchange, required this.abierto, required this.onAlternar, required this.onCopiar});

  final HttpExchange exchange;
  final bool abierto;
  final ValueChanged<bool> onAlternar;
  final VoidCallback onCopiar;

  @override
  Widget build(BuildContext context) {
    final conError = exchange.conError;
    final insignia = exchange.status == 0
        ? 'SIN CONEXIÓN'
        : '${exchange.status} ${exchange.status < 300 ? 'OK' : exchange.status < 400 ? 'REDIRECCIÓN' : 'ERROR'}';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: conError ? Border.all(color: AppColors.error.withValues(alpha: 0.6)) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => onAlternar(!abierto),
            child: Container(
              color: AppColors.primaryContainer.withValues(alpha: 0.8),
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _Chip(
                          texto: insignia,
                          fondo: conError ? AppColors.errorContainer : AppColors.secondary,
                          color: conError ? AppColors.onErrorContainer : AppColors.onSecondary,
                          negrita: true,
                          pequeno: true,
                        ),
                        _Chip(texto: exchange.metodo, fondo: AppColors.tertiaryFixedDim, color: AppColors.onTertiaryFixed, negrita: true, pequeno: true),
                        Text(exchange.url, style: AppTheme.telemetry(size: 13, weight: FontWeight.w600, color: AppColors.surfaceBright)),
                      ],
                    ),
                  ),
                  Text('${exchange.ms} ms', style: AppTheme.telemetry(size: 12, color: AppColors.onPrimaryContainer)),
                  const SizedBox(width: 12),
                  Text(
                    TimeOfDay.fromDateTime(exchange.fecha).format(context),
                    style: AppTheme.telemetry(size: 12, color: AppColors.onPrimaryContainer),
                  ),
                  IconButton(
                    tooltip: 'Copiar este intercambio',
                    onPressed: onCopiar,
                    icon: const Icon(Icons.copy_all, size: 16, color: AppColors.onPrimaryContainer),
                  ),
                  Icon(abierto ? Icons.expand_less : Icons.expand_more, size: 18, color: AppColors.onPrimaryContainer),
                ],
              ),
            ),
          ),
          if (abierto)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Bloque(
                    titulo: 'Petición',
                    contenido: exchange.autorizacion != null
                        ? {'Authorization': exchange.autorizacion, 'cuerpo': exchange.peticion}
                        : exchange.peticion,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _Bloque(titulo: 'Respuesta', contenido: exchange.error != null ? {'error': exchange.error} : exchange.respuesta),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Bloque extends StatelessWidget {
  const _Bloque({required this.titulo, required this.contenido});

  final String titulo;
  final Object? contenido;

  @override
  Widget build(BuildContext context) {
    final texto = contenido == null ? '(sin cuerpo)' : const JsonEncoder.withIndent('  ').convert(contenido);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo.toUpperCase(), style: AppTheme.telemetry(size: 11, color: AppColors.onPrimaryContainer).copyWith(letterSpacing: 1)),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(8)),
          child: SelectableText(texto, style: AppTheme.telemetry(size: 12, color: AppColors.primaryFixed).copyWith(height: 1.5)),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.texto, required this.fondo, required this.color, this.negrita = false, this.pequeno = false});

  final String texto;
  final Color fondo;
  final Color color;
  final bool negrita;
  final bool pequeno;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: pequeno ? 8 : 10, vertical: pequeno ? 3 : 4),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(6)),
      child: Text(
        texto,
        style: AppTheme.telemetry(size: pequeno ? 11 : 12, weight: negrita ? FontWeight.w700 : FontWeight.w600, color: color),
      ),
    );
  }
}

class _FiltroChip extends StatelessWidget {
  const _FiltroChip({required this.texto, required this.activo, required this.onTap});

  final String texto;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: activo ? AppColors.primary : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        child: Text(
          texto,
          style: AppTheme.labelMd(color: activo ? Colors.white : AppColors.onSurfaceVariant),
        ),
      ),
    );
  }
}
