import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/roles.dart';
import '../core/services.dart';
import '../core/session.dart';
import '../theme/app_theme.dart';
import '../widgets/alerta.dart';
import '../widgets/hub_estaciones.dart';
import 'acciones_admin_vuelo.dart';
import 'admin_vuelo_dialog.dart';
import 'reserva_dialog.dart';

const _ciudades = {'UIO': 'Quito', 'GYE': 'Guayaquil', 'MAD': 'Madrid'};
const _umbralUltimosCupos = 15; // criterio de la interfaz para resaltar pocos asientos

// Vista de vuelos (vuelos.html / vuelos.js): consulta GET /api/vuelos (S3) y abre el modal de reserva (S4).
class VuelosView extends StatefulWidget {
  const VuelosView({super.key, required this.onIrALogin});

  final VoidCallback onIrALogin;

  @override
  State<VuelosView> createState() => _VuelosViewState();
}

class _VuelosViewState extends State<VuelosView> {
  String _origen = 'UIO';
  String _destino = 'GYE'; // "ALL" = todos los destinos
  DateTime? _fecha;

  List<Vuelo> _vuelos = const [];
  // Solo para administradores: datos de gestión de cada vuelo (ocupación, si puede editarse).
  Map<int, VueloAdmin> _gestion = {};
  String _contador = 'Consultando...';
  ({TipoAlerta tipo, String texto})? _alerta;
  bool _tabla = false;
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    _buscar();
  }

  void _invertir() {
    if (_destino == 'ALL') return; // "Todos los destinos" no tiene par inverso
    setState(() {
      final tmp = _origen;
      _origen = _destino;
      _destino = tmp;
    });
  }

  Future<void> _elegirFecha() async {
    final hoy = DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fecha ?? hoy,
      firstDate: DateTime(hoy.year - 1),
      lastDate: DateTime(hoy.year + 3),
    );
    if (elegida != null) setState(() => _fecha = elegida);
  }

  Future<void> _buscar() async {
    setState(() {
      _cargando = true;
      _contador = 'Consultando el servicio S3...';
    });
    try {
      final vuelos = Permisos(session.rol).puedeGestionarVuelos
          ? await _buscarComoAdmin()
          : await VuelosService.buscar(
              origen: _origen,
              destino: _destino == 'ALL' ? null : _destino,
              fecha: _fecha == null ? null : _formatoFecha(_fecha!),
            );
      if (!mounted) return;
      setState(() {
        _vuelos = vuelos;
        _alerta = null;
        _contador = '${vuelos.length} ${vuelos.length == 1 ? 'vuelo encontrado' : 'vuelos encontrados'}';
      });
    } on ConexionFallida {
      if (!mounted) return;
      setState(() {
        _vuelos = const [];
        _contador = 'Servicio de vuelos no disponible.';
        _alerta = (tipo: TipoAlerta.error, texto: 'No se pudo conectar con el servicio de vuelos. ¿Está levantado en :5003?');
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _vuelos = const [];
        _contador = 'No se pudo consultar los vuelos.';
        _alerta = (tipo: TipoAlerta.error, texto: e.mensaje);
      });
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // El administrador también ve los borradores: consulta el listado de gestión y filtra aquí.
  Future<List<Vuelo>> _buscarComoAdmin() async {
    final todos = await GestionVuelosService.listar(token: session.token ?? '');
    _gestion = {for (final v in todos) v.id: v};
    final fecha = _fecha == null ? null : _formatoFecha(_fecha!);
    return [
      for (final v in todos)
        if (v.origen == _origen && (_destino == 'ALL' || v.destino == _destino) && (fecha == null || v.fecha == fecha))
          Vuelo(
            id: v.id,
            origen: v.origen,
            destino: v.destino,
            fecha: v.fecha,
            precio: v.precio,
            asientosDisponibles: v.asientosDisponibles,
            activo: v.activo,
          ),
    ];
  }

  Widget? _accionesAdmin(Vuelo vuelo) {
    final gestion = _gestion[vuelo.id];
    if (gestion == null) return null;
    return AccionesAdminVuelo(
      gestion: gestion,
      onEditar: () => _editarVuelo(gestion),
      onEstado: () => _cambiarEstado(gestion),
    );
  }

  Future<void> _editarVuelo(VueloAdmin vuelo) async {
    final token = session.token;
    if (token == null) return;
    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) => AdminVueloDialog(token: token, vuelo: vuelo),
    );
    if (guardado != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Vuelo #${vuelo.id} actualizado.')));
    await _buscar();
  }

  Future<void> _cambiarEstado(VueloAdmin vuelo) async {
    final token = session.token;
    if (token == null) return;
    try {
      await GestionVuelosService.cambiarEstado(id: vuelo.id, activo: !vuelo.activo, token: token);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(vuelo.activo ? 'Vuelo #${vuelo.id} despublicado.' : 'Vuelo #${vuelo.id} publicado.')),
      );
      await _buscar();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensaje)));
    }
  }

  // Alta de vuelo: solo visible para administradores (el servidor vuelve a validar el rol).
  Future<void> _crearVuelo() async {
    final token = session.token;
    if (token == null) return;
    final creado = await showDialog<bool>(
      context: context,
      builder: (_) => AdminVueloDialog(token: token),
    );
    if (creado != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vuelo creado con su mapa de asientos.')));
    await _buscar();
  }

  void _reservar(Vuelo vuelo) {
    final token = session.token;
    if (token == null) {
      setState(() => _alerta = (tipo: TipoAlerta.aviso, texto: 'Inicie sesión para reservar un vuelo.'));
      widget.onIrALogin();
      return;
    }
    showDialog<void>(
      context: context,
      builder: (_) => ReservaDialog(vuelo: vuelo, token: token),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final margen = ancho >= 768 ? AppSpacing.margin : AppSpacing.marginMobile;
    final rutas = {for (final v in _vuelos) '${v.origen}-${v.destino}'}.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Telemetria(rutas: rutas, margen: margen),
        Transform.translate(
          offset: const Offset(0, -32),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: margen),
            child: _Buscador(
              origen: _origen,
              destino: _destino,
              fecha: _fecha,
              contador: _contador,
              alerta: _alerta,
              cargando: _cargando,
              onOrigen: (v) => setState(() => _origen = v),
              onDestino: (v) => setState(() => _destino = v),
              onInvertir: _invertir,
              onElegirFecha: _elegirFecha,
              onLimpiarFecha: () => setState(() => _fecha = null),
              onBuscar: _buscar,
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(margen, 0, margen, AppSpacing.xl),
          child: _Resultados(
            vuelos: _vuelos,
            tabla: _tabla,
            onCambiarVista: (t) => setState(() => _tabla = t),
            onReservar: _reservar,
            acciones: Permisos(session.rol).puedeGestionarVuelos ? _accionesAdmin : null,
            onCrear: Permisos(session.rol).puedeCrearVuelos ? _crearVuelo : null,
          ),
        ),
        const HubEstaciones(),
      ],
    );
  }
}

String _formatoFecha(DateTime f) => '${f.year.toString().padLeft(4, '0')}-${f.month.toString().padLeft(2, '0')}-${f.day.toString().padLeft(2, '0')}';

class _Telemetria extends StatelessWidget {
  const _Telemetria({required this.rutas, required this.margen});

  final int rutas;
  final double margen;

  @override
  Widget build(BuildContext context) {
    // headline-xl-mobile (32px) en móvil y headline-xl (44px) desde md.
    final tamanioTitulo = MediaQuery.sizeOf(context).width >= 768 ? 44.0 : 32.0;

    return Container(
      width: double.infinity,
      color: AppColors.surfaceContainerLow,
      padding: EdgeInsets.fromLTRB(margen, AppSpacing.xl, margen, AppSpacing.xl + 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: AppColors.secondaryContainer.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(999)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.secondary, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('MICROSERVICIO S3 [:5003] ENLACE ACTIVO', style: AppTheme.telemetry(size: 12, weight: FontWeight.w700, color: AppColors.onSecondaryContainer)),
                  ],
                ),
              ),
              Text('REST/JSON', style: AppTheme.telemetry(size: 12, color: AppColors.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Exploración de Vuelos y Cupos en Tiempo Real', style: AppTheme.headlineXl().copyWith(fontSize: tamanioTitulo)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Consulta sincronizada con el servicio de vuelos. Seleccione su itinerario y asegure su plaza al instante.',
            style: AppTheme.bodyMd(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TELEMETRÍA DE FLOTA', style: AppTheme.labelSm(color: AppColors.onSurfaceVariant).copyWith(letterSpacing: 1)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text('$rutas Rutas', style: AppTheme.headlineSm()),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.surfaceContainerHigh, borderRadius: BorderRadius.circular(999)),
                            child: Text('LIVE SYNC', style: AppTheme.telemetry(size: 11, weight: FontWeight.w700, color: AppColors.secondary)),
                          ),
                        ],
                      ),
                      Text('Conexión con el servicio de vuelos :5003', style: AppTheme.bodySm(color: AppColors.onSurfaceVariant)),
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

class _Buscador extends StatelessWidget {
  const _Buscador({
    required this.origen,
    required this.destino,
    required this.fecha,
    required this.contador,
    required this.alerta,
    required this.cargando,
    required this.onOrigen,
    required this.onDestino,
    required this.onInvertir,
    required this.onElegirFecha,
    required this.onLimpiarFecha,
    required this.onBuscar,
  });

  final String origen;
  final String destino;
  final DateTime? fecha;
  final String contador;
  final ({TipoAlerta tipo, String texto})? alerta;
  final bool cargando;
  final ValueChanged<String> onOrigen;
  final ValueChanged<String> onDestino;
  final VoidCallback onInvertir;
  final VoidCallback onElegirFecha;
  final VoidCallback onLimpiarFecha;
  final VoidCallback onBuscar;

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final enFila = ancho >= 1024;

    final origenCampo = _Select(
      etiqueta: 'Origen',
      valor: origen,
      opciones: const {
        'UIO': 'UIO • Quito, Mariscal Sucre',
        'GYE': 'GYE • Guayaquil, José Joaquín de Olmedo',
        'MAD': 'MAD • Madrid-Barajas Adolfo Suárez',
      },
      onChanged: onOrigen,
    );
    final destinoCampo = _Select(
      etiqueta: 'Destino',
      valor: destino,
      opciones: const {
        'ALL': 'Todos los destinos',
        'GYE': 'GYE • Guayaquil, Ecuador',
        'UIO': 'UIO • Quito, Ecuador',
        'MAD': 'MAD • Madrid, España',
      },
      onChanged: onDestino,
    );
    final fechaCampo = _CampoConEtiqueta(
      etiqueta: 'Fecha del itinerario',
      child: InkWell(
        onTap: onElegirFecha,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  fecha == null ? 'AAAA-MM-DD' : _formatoFecha(fecha!),
                  style: AppTheme.telemetry(size: 13, color: fecha == null ? AppColors.outline : AppColors.onSurface),
                ),
              ),
              if (fecha != null)
                InkWell(onTap: onLimpiarFecha, child: const Icon(Icons.close, size: 16, color: AppColors.outline)),
              const SizedBox(width: 4),
              const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.outline),
            ],
          ),
        ),
      ),
    );
    final botonFiltrar = SizedBox(
      height: 44,
      child: FilledButton.icon(
        onPressed: cargando ? null : onBuscar,
        icon: const Icon(Icons.search, size: 18),
        label: Text('Filtrar', style: AppTheme.labelLg(color: AppColors.onPrimary).copyWith(fontWeight: FontWeight.w600)),
        style: FilledButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      ),
    );
    final boton = Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(color: AppColors.surfaceContainer, shape: BoxShape.circle),
      child: IconButton(
        tooltip: 'Invertir trayecto',
        onPressed: onInvertir,
        icon: const Icon(Icons.swap_horiz, size: 20),
      ),
    );

    final formulario = enFila
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(flex: 3, child: origenCampo),
              Padding(padding: const EdgeInsets.only(bottom: 2), child: boton),
              Expanded(flex: 3, child: destinoCampo),
              const SizedBox(width: AppSpacing.sm),
              Expanded(flex: 2, child: fechaCampo),
              const SizedBox(width: AppSpacing.sm),
              Expanded(flex: 1, child: botonFiltrar),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              origenCampo,
              Align(alignment: Alignment.center, child: boton),
              destinoCampo,
              const SizedBox(height: AppSpacing.sm),
              fechaCampo,
              const SizedBox(height: AppSpacing.sm),
              botonFiltrar,
            ],
          );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 30, offset: const Offset(0, 12))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.surfaceContainer, borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.flight_takeoff, size: 16, color: AppColors.secondary),
                        const SizedBox(width: 4),
                        Text('Búsqueda Directa', style: AppTheme.labelMd()),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text('GET /api/vuelos', style: AppTheme.telemetry(size: 12, color: AppColors.onSurfaceVariant)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: AppColors.surfaceContainerHigh, borderRadius: BorderRadius.circular(999)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.secondary, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(contador, style: AppTheme.labelMd()),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          formulario,
          if (alerta != null) ...[
            const SizedBox(height: AppSpacing.md),
            Alerta(tipo: alerta!.tipo, texto: alerta!.texto),
          ],
        ],
      ),
    );
  }
}

class _CampoConEtiqueta extends StatelessWidget {
  const _CampoConEtiqueta({required this.etiqueta, required this.child});

  final String etiqueta;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(etiqueta, style: AppTheme.labelMd(color: AppColors.onSurfaceVariant)),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _Select extends StatelessWidget {
  const _Select({required this.etiqueta, required this.valor, required this.opciones, required this.onChanged});

  final String etiqueta;
  final String valor;
  final Map<String, String> opciones;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return _CampoConEtiqueta(
      etiqueta: etiqueta,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: valor,
            isExpanded: true,
            icon: const Icon(Icons.expand_more, size: 18),
            style: AppTheme.bodyMd(),
            items: [for (final e in opciones.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ),
    );
  }
}

class _Resultados extends StatelessWidget {
  const _Resultados({
    required this.vuelos,
    required this.tabla,
    required this.onCambiarVista,
    required this.onReservar,
    this.acciones,
    this.onCrear,
  });

  final List<Vuelo> vuelos;
  final bool tabla;
  final ValueChanged<bool> onCambiarVista;
  final ValueChanged<Vuelo> onReservar;
  // Botones extra por vuelo (solo administrador).
  final Widget? Function(Vuelo vuelo)? acciones;
  // Solo administradores: crear un vuelo desde la cabecera de resultados.
  final VoidCallback? onCrear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Vuelos Disponibles en Red AeroVuelo', style: AppTheme.headlineMd()),
                Text('Datos sincronizados directamente desde el servicio S3 (:5003).', style: AppTheme.bodySm(color: AppColors.onSurfaceVariant)),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onCrear != null) ...[
                  FilledButton.icon(
                    onPressed: onCrear,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text('Crear vuelo', style: AppTheme.labelLg(color: AppColors.onPrimary).copyWith(fontWeight: FontWeight.w700)),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                ],
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: AppColors.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _BotonVista(texto: 'Boletos de Abordaje', icono: Icons.style, activo: !tabla, onTap: () => onCambiarVista(false)),
                      _BotonVista(texto: 'Consola Matricial', icono: Icons.table_rows, activo: tabla, onTap: () => onCambiarVista(true)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (tabla)
          _TablaVuelos(vuelos: vuelos, onReservar: onReservar, acciones: acciones)
        else
          _ListaBoletos(vuelos: vuelos, onReservar: onReservar, acciones: acciones),
      ],
    );
  }
}

class _BotonVista extends StatelessWidget {
  const _BotonVista({required this.texto, required this.icono, required this.activo, required this.onTap});

  final String texto;
  final IconData icono;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: activo ? AppColors.surfaceContainerLowest : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: activo ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 2)] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 18, color: activo ? AppColors.onSurface : AppColors.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              texto,
              style: AppTheme.labelMd(color: activo ? AppColors.onSurface : AppColors.onSurfaceVariant).copyWith(fontWeight: activo ? FontWeight.w700 : FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListaBoletos extends StatelessWidget {
  const _ListaBoletos({required this.vuelos, required this.onReservar, this.acciones});

  final List<Vuelo> vuelos;
  final ValueChanged<Vuelo> onReservar;
  final Widget? Function(Vuelo vuelo)? acciones;

  @override
  Widget build(BuildContext context) {
    if (vuelos.isEmpty) {
      return Text('No hay vuelos con esos filtros.', style: AppTheme.bodyMd(color: AppColors.onSurfaceVariant));
    }
    return Column(
      children: [
        for (final vuelo in vuelos) ...[
          _TarjetaBoleto(vuelo: vuelo, onReservar: () => onReservar(vuelo), acciones: acciones?.call(vuelo)),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

class _TarjetaBoleto extends StatelessWidget {
  const _TarjetaBoleto({required this.vuelo, required this.onReservar, this.acciones});

  final Vuelo vuelo;
  final VoidCallback onReservar;
  final Widget? acciones;

  @override
  Widget build(BuildContext context) {
    final agotado = vuelo.agotado;
    final ancho = MediaQuery.sizeOf(context).width;
    final lateral = ancho >= 1024;

    final cuerpo = Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: AppColors.surfaceContainerHigh, borderRadius: BorderRadius.circular(999)),
                child: Text('VUELO #${vuelo.id}', style: AppTheme.telemetry(size: 11, weight: FontWeight.w700, color: AppColors.onSurface)),
              ),
              const SizedBox(width: AppSpacing.sm),
              _InsigniaEstado(vuelo: vuelo),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: _Ciudad(codigo: vuelo.origen, alineacion: CrossAxisAlignment.start)),
              Expanded(child: _Trayecto(fecha: vuelo.fecha)),
              Expanded(child: _Ciudad(codigo: vuelo.destino, alineacion: CrossAxisAlignment.end)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
            child: Text(
              agotado ? 'Sin asientos disponibles' : '${vuelo.asientosDisponibles} asientos disponibles',
              style: AppTheme.bodySm(color: AppColors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );

    final precio = Container(
      width: lateral ? 288 : double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      color: AppColors.surfaceContainerLow,
      child: Column(
        children: [
          Text('TARIFA POR PASAJERO', style: AppTheme.labelSm(color: AppColors.onSurfaceVariant).copyWith(letterSpacing: 1)),
          Text('\$${vuelo.precio.toStringAsFixed(2)}', style: AppTheme.headlineXl().copyWith(fontSize: 40)),
          Text('USD', style: AppTheme.telemetry(size: 11, color: AppColors.onSurfaceVariant)),
          if (acciones != null) ...[
            const SizedBox(height: AppSpacing.md),
            acciones!,
          ],
          const SizedBox(height: AppSpacing.md),
          if (Permisos(session.rol).puedeReservar)
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton(
                onPressed: agotado || !vuelo.activo ? null : onReservar,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.surfaceContainerHighest,
                disabledForegroundColor: AppColors.onSurfaceVariant.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(agotado ? 'Agotado' : 'Reservar vuelo', style: AppTheme.labelLg(color: AppColors.onPrimary).copyWith(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );

    return Opacity(
      opacity: agotado ? 0.85 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        clipBehavior: Clip.antiAlias,
        child: lateral
            ? IntrinsicHeight(
                child: Row(children: [Expanded(child: cuerpo), precio]),
              )
            : Column(children: [cuerpo, precio]),
      ),
    );
  }
}

class _InsigniaEstado extends StatelessWidget {
  const _InsigniaEstado({required this.vuelo});
  final Vuelo vuelo;

  @override
  Widget build(BuildContext context) {
    final (texto, fondo, color) = !vuelo.activo
        ? ('BORRADOR', AppColors.surfaceContainerHigh, AppColors.onSurfaceVariant)
        : vuelo.asientosDisponibles == 0
        ? ('AGOTADO', AppColors.errorContainer, AppColors.onErrorContainer)
        : vuelo.asientosDisponibles <= _umbralUltimosCupos
            ? ('ÚLTIMOS CUPOS', AppColors.tertiaryFixed, AppColors.onTertiaryFixed)
            : ('DISPONIBLE', AppColors.surfaceContainerLow, AppColors.secondary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(999)),
      child: Text(texto, style: AppTheme.telemetry(size: 11, weight: FontWeight.w700, color: color)),
    );
  }
}

class _Ciudad extends StatelessWidget {
  const _Ciudad({required this.codigo, required this.alineacion});

  final String codigo;
  final CrossAxisAlignment alineacion;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alineacion,
      children: [
        Text(codigo, style: AppTheme.headlineLg().copyWith(fontWeight: FontWeight.w800, height: 1)),
        Text(_ciudades[codigo] ?? codigo, style: AppTheme.bodySm().copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// Trayecto directo: línea punteada con dos extremos y un avión centrado.
class _Trayecto extends StatelessWidget {
  const _Trayecto({required this.fecha});
  final String fecha;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              LayoutBuilder(
                builder: (_, c) {
                  final puntos = (c.maxWidth / 12).floor();
                  return Row(
                    children: [
                      for (var i = 0; i < puntos; i++)
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            height: 2,
                            color: i.isEven ? AppColors.secondary.withValues(alpha: 0.5) : Colors.transparent,
                          ),
                        ),
                    ],
                  );
                },
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: AppColors.secondary, width: 1.5)),
                child: const Icon(Icons.flight, size: 18, color: AppColors.secondary),
              ),
            ],
          ),
        ),
        Text('Salida $fecha', style: AppTheme.bodyMd(color: AppColors.onSurfaceVariant).copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _TablaVuelos extends StatelessWidget {
  const _TablaVuelos({required this.vuelos, required this.onReservar, this.acciones});

  final List<Vuelo> vuelos;
  final ValueChanged<Vuelo> onReservar;
  final Widget? Function(Vuelo vuelo)? acciones;

  @override
  Widget build(BuildContext context) {
    final encabezado = AppTheme.labelMd(color: AppColors.onSurfaceVariant);
    return Container(
      decoration: BoxDecoration(color: AppColors.surfaceContainerLowest, borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(AppColors.surfaceContainer),
          columns: [
            DataColumn(label: Text('ID', style: encabezado)),
            DataColumn(label: Text('Ruta', style: encabezado)),
            DataColumn(label: Text('Fecha', style: encabezado)),
            DataColumn(label: Text('Precio (USD)', style: encabezado)),
            DataColumn(label: Text('Asientos', style: encabezado)),
            DataColumn(label: Text('Acción', style: encabezado)),
          ],
          rows: vuelos.isEmpty
              ? [
                  DataRow(cells: [
                    DataCell(Text('No hay vuelos con esos filtros.', style: AppTheme.bodySm(color: AppColors.onSurfaceVariant))),
                    for (var i = 0; i < 5; i++) const DataCell(SizedBox.shrink()),
                  ]),
                ]
              : [
                  for (final v in vuelos)
                    DataRow(cells: [
                      DataCell(Text('#${v.id}', style: AppTheme.telemetry(color: AppColors.onSurface, weight: FontWeight.w700))),
                      DataCell(Text('${v.origen} → ${v.destino}', style: AppTheme.bodySm().copyWith(fontWeight: FontWeight.w700))),
                      DataCell(Text(v.fecha, style: AppTheme.telemetry(color: AppColors.onSurface))),
                      DataCell(Text('\$${v.precio.toStringAsFixed(2)}', style: AppTheme.bodySm().copyWith(fontWeight: FontWeight.w700))),
                      DataCell(Text('${v.asientosDisponibles} libres', style: AppTheme.bodySm())),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (Permisos(session.rol).puedeReservar)
                              FilledButton(
                                onPressed: v.agotado || !v.activo ? null : () => onReservar(v),
                              style: FilledButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                              child: Text(v.agotado ? 'Sin cupo' : 'Reservar', style: AppTheme.labelMd(color: AppColors.onPrimary)),
                            ),
                            if (acciones?.call(v) case final accion?) ...[const SizedBox(width: 8), accion],
                          ],
                        ),
                      ),
                    ]),
                ],
        ),
      ),
    );
  }
}
