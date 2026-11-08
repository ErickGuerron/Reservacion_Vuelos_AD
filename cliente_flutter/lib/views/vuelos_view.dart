import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/horarios.dart';
import '../core/lotes.dart';
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
const _dias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
const _meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

enum _Orden { salida, precio, cupos }

// "2026-11-10" -> "Mar 10 nov".
String _etiquetaFecha(String iso) {
  final f = DateTime.tryParse(iso);
  if (f == null) return iso;
  return '${_dias[f.weekday - 1]} ${f.day} ${_meses[f.month - 1]}';
}

// Vista de vuelos (vuelos.html / vuelos.js): consulta GET /api/vuelos (S3) y abre el modal de reserva (S4).
// Se trae la ruta completa y la fecha, el orden y los últimos cupos se filtran aquí, para poder mostrar
// la franja de fechas con vuelos y su precio más bajo.
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
  _Orden _orden = _Orden.salida;
  bool _soloUltimos = false;
  Franja? _franja;

  List<Vuelo> _todos = const [];
  // Solo para administradores: datos de gestión de cada vuelo (ocupación, si puede editarse).
  Map<int, VueloAdmin> _gestion = {};
  ({TipoAlerta tipo, String texto})? _alerta;
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
      _fecha = null;
    });
    _buscar();
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
    setState(() => _cargando = true);
    try {
      final vuelos = Permisos(session.rol).puedeGestionarVuelos
          ? await _buscarComoAdmin()
          : await VuelosService.buscar(origen: _origen, destino: _destino == 'ALL' ? null : _destino);
      if (!mounted) return;
      setState(() {
        _todos = vuelos;
        _alerta = null;
      });
    } on ConexionFallida {
      if (!mounted) return;
      setState(() {
        _todos = const [];
        _alerta = (tipo: TipoAlerta.error, texto: 'No se pudo conectar con el servicio de vuelos. ¿Está levantado en :5003?');
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _todos = const [];
        _alerta = (tipo: TipoAlerta.error, texto: e.mensaje);
      });
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // El administrador también ve los borradores: consulta el listado de gestión y filtra la ruta aquí.
  Future<List<Vuelo>> _buscarComoAdmin() async {
    final todos = await GestionVuelosService.listar(token: session.token ?? '');
    _gestion = {for (final v in todos) v.id: v};
    return [
      for (final v in todos)
        if (v.origen == _origen && (_destino == 'ALL' || v.destino == _destino))
          Vuelo(
            id: v.id,
            origen: v.origen,
            destino: v.destino,
            fecha: v.fecha,
            hora: v.hora,
            horaLlegada: v.horaLlegada,
            precio: v.precio,
            asientosDisponibles: v.asientosDisponibles,
            activo: v.activo,
          ),
    ];
  }

  // Vuelos que se muestran: filtro de fecha y de últimos cupos, y el orden elegido.
  List<Vuelo> get _visibles {
    final fecha = _fecha == null ? null : _formatoFecha(_fecha!);
    final lista = [
      for (final v in _todos)
        if ((fecha == null || v.fecha == fecha) &&
            (_franja == null || Franja.de(v.hora) == _franja) &&
            (!_soloUltimos || (v.asientosDisponibles > 0 && v.asientosDisponibles <= _umbralUltimosCupos)))
          v,
    ];
    int porSalida(Vuelo a, Vuelo b) {
      final c = a.fecha.compareTo(b.fecha);
      return c != 0 ? c : a.hora.compareTo(b.hora);
    }

    if (_orden == _Orden.precio) {
      lista.sort((a, b) {
        final c = a.precio.compareTo(b.precio);
        return c != 0 ? c : porSalida(a, b);
      });
    } else if (_orden == _Orden.cupos) {
      lista.sort((a, b) => b.asientosDisponibles.compareTo(a.asientosDisponibles));
    } else {
      lista.sort(porSalida);
    }
    return lista;
  }

  // Fechas con vuelos en la ruta elegida y el precio más bajo de cada una.
  List<({String fecha, double desde})> get _fechasConVuelos {
    final desde = <String, double>{};
    for (final v in _todos) {
      final actual = desde[v.fecha];
      if (actual == null || v.precio < actual) desde[v.fecha] = v.precio;
    }
    final fechas = desde.keys.toList()..sort();
    return [for (final f in fechas) (fecha: f, desde: desde[f]!)];
  }

  void _limpiarFiltros() => setState(() {
        _fecha = null;
        _soloUltimos = false;
        _franja = null;
      });

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
    final lista = _visibles;
    final esAdmin = Permisos(session.rol).puedeGestionarVuelos;
    final destinoTexto = _destino == 'ALL' ? 'todos los destinos' : (_ciudades[_destino] ?? _destino);
    final cuenta = _cargando && _todos.isEmpty
        ? 'Consultando vuelos...'
        : '${lista.length} ${lista.length == 1 ? 'vuelo encontrado' : 'vuelos encontrados'}';
    final subtitulo = '$cuenta · ${_ciudades[_origen] ?? _origen} → $destinoTexto'
        '${_fecha == null ? ' · todas las fechas' : ' · ${_etiquetaFecha(_formatoFecha(_fecha!))}'}';
    final fechas = _fechasConVuelos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Cabecera(margen: margen),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: margen),
          child: _Buscador(
            origen: _origen,
            destino: _destino,
            fecha: _fecha,
            alerta: _alerta,
            cargando: _cargando,
            onOrigen: (v) {
              setState(() {
                _origen = v;
                _fecha = null;
              });
              _buscar();
            },
            onDestino: (v) {
              setState(() {
                _destino = v;
                _fecha = null;
              });
              _buscar();
            },
            onInvertir: _invertir,
            onElegirFecha: _elegirFecha,
            onLimpiarFecha: () => setState(() => _fecha = null),
            onBuscar: _buscar,
            franja: fechas.isEmpty
                ? null
                : _FranjaFechas(
                    fechas: fechas,
                    total: _todos.length,
                    seleccionada: _fecha == null ? null : _formatoFecha(_fecha!),
                    onElegir: (f) => setState(() => _fecha = f == null ? null : DateTime.tryParse(f)),
                  ),
          ),
        ),
        if (_cargando) const Padding(padding: EdgeInsets.only(top: AppSpacing.sm), child: LinearProgressIndicator(minHeight: 3)),
        Padding(
          padding: EdgeInsets.fromLTRB(margen, AppSpacing.lg, margen, AppSpacing.xl),
          child: ResultadosVuelos(
            vuelos: lista,
            onReservar: _reservar,
            acciones: esAdmin ? _accionesAdmin : null,
            onCrear: Permisos(session.rol).puedeCrearVuelos ? _crearVuelo : null,
            gestion: _gestion,
            subtitulo: subtitulo,
            onLimpiarFiltros: _fecha == null && !_soloUltimos && _franja == null ? null : _limpiarFiltros,
            controles: _Controles(
              orden: _orden,
              soloUltimos: _soloUltimos,
              franja: _franja,
              onFranja: (f) => setState(() => _franja = f),
              onOrden: (o) => setState(() => _orden = o),
              onUltimos: (v) => setState(() => _soloUltimos = v),
            ),
          ),
        ),
        const HubEstaciones(),
      ],
    );
  }
}

String _formatoFecha(DateTime f) => '${f.year.toString().padLeft(4, '0')}-${f.month.toString().padLeft(2, '0')}-${f.day.toString().padLeft(2, '0')}';

class _Cabecera extends StatelessWidget {
  const _Cabecera({required this.margen});

  final double margen;

  @override
  Widget build(BuildContext context) {
    // headline-xl-mobile (32px) en móvil y headline-xl (44px) desde md.
    final tamanioTitulo = MediaQuery.sizeOf(context).width >= 768 ? 44.0 : 32.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(margen, AppSpacing.xl, margen, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Explorar vuelos', style: AppTheme.headlineXl().copyWith(fontSize: tamanioTitulo)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Elige tu ruta y tu fecha, compara horarios de salida y llegada, y reserva con cupos en tiempo real.',
            style: AppTheme.bodyMd(color: AppColors.onSurfaceVariant),
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
    required this.alerta,
    required this.cargando,
    required this.onOrigen,
    required this.onDestino,
    required this.onInvertir,
    required this.onElegirFecha,
    required this.onLimpiarFecha,
    required this.onBuscar,
    this.franja,
  });

  final String origen;
  final String destino;
  final DateTime? fecha;
  final ({TipoAlerta tipo, String texto})? alerta;
  final bool cargando;
  final ValueChanged<String> onOrigen;
  final ValueChanged<String> onDestino;
  final VoidCallback onInvertir;
  final VoidCallback onElegirFecha;
  final VoidCallback onLimpiarFecha;
  final VoidCallback onBuscar;
  // Fechas con vuelos de la ruta elegida.
  final Widget? franja;

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
      etiqueta: 'Fecha',
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
    final botonBuscar = SizedBox(
      height: 44,
      child: FilledButton.icon(
        onPressed: cargando ? null : onBuscar,
        icon: const Icon(Icons.search, size: 18),
        label: Text('Buscar', style: AppTheme.labelLg(color: AppColors.onPrimary).copyWith(fontWeight: FontWeight.w600)),
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
              Expanded(flex: 1, child: botonBuscar),
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
              botonBuscar,
            ],
          );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceVariant),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          formulario,
          if (franja != null) ...[
            const SizedBox(height: AppSpacing.md),
            franja!,
          ],
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

// Franja "Fechas con vuelos": un botón por día con el precio más bajo. "Todas" quita el filtro de fecha.
class _FranjaFechas extends StatelessWidget {
  const _FranjaFechas({required this.fechas, required this.total, required this.seleccionada, required this.onElegir});

  final List<({String fecha, double desde})> fechas;
  final int total;
  final String? seleccionada;
  final ValueChanged<String?> onElegir;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('FECHAS CON VUELOS', style: AppTheme.telemetry(size: 11, weight: FontWeight.w700, color: AppColors.onSurfaceVariant)),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _ChipFecha(
              titulo: 'Todas',
              subtitulo: '$total ${total == 1 ? 'vuelo' : 'vuelos'}',
              activo: seleccionada == null,
              onTap: () => onElegir(null),
            ),
            for (final f in fechas)
              _ChipFecha(
                titulo: _etiquetaFecha(f.fecha),
                subtitulo: 'desde \$${f.desde.toStringAsFixed(f.desde == f.desde.roundToDouble() ? 0 : 2)}',
                activo: seleccionada == f.fecha,
                onTap: () => onElegir(f.fecha),
              ),
          ],
        ),
      ],
    );
  }
}

class _ChipFecha extends StatelessWidget {
  const _ChipFecha({required this.titulo, required this.subtitulo, required this.activo, required this.onTap});

  final String titulo;
  final String subtitulo;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: activo,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52, minWidth: 116),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
          decoration: BoxDecoration(
            color: activo ? AppColors.slate900 : AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: activo ? AppColors.slate900 : AppColors.slate300, width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: AppTheme.labelLg(color: activo ? Colors.white : AppColors.onSurface).copyWith(fontWeight: FontWeight.w700)),
              Text(subtitulo, style: AppTheme.bodySm(color: activo ? AppColors.slate300 : AppColors.slate600).copyWith(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

// Barra de filtros: tres grupos con la misma altura y segmentos del mismo ancho (4 + 3 + 2 segmentos, con
// proporción 4:3:2). En pantallas angostas los grupos se apilan a todo el ancho.
class _Controles extends StatelessWidget {
  const _Controles({
    required this.orden,
    required this.soloUltimos,
    required this.franja,
    required this.onFranja,
    required this.onOrden,
    required this.onUltimos,
  });

  final _Orden orden;
  final bool soloUltimos;
  final Franja? franja;
  // null quita el filtro (se vuelve a tocar la franja elegida).
  final ValueChanged<Franja?> onFranja;
  final ValueChanged<_Orden> onOrden;
  final ValueChanged<bool> onUltimos;

  @override
  Widget build(BuildContext context) {
    final salida = _GrupoFiltro(
      etiqueta: 'HORA DE SALIDA',
      child: _Segmentos<Franja>(
        opciones: [for (final f in Franja.values) _Opcion(f, f.etiqueta, ayuda: f.rango)],
        valor: franja,
        onElegir: (f) => onFranja(f == franja ? null : f),
      ),
    );
    final ordenar = _GrupoFiltro(
      etiqueta: 'ORDENAR POR',
      child: _Segmentos<_Orden>(
        opciones: const [
          _Opcion(_Orden.salida, 'Más temprano'),
          _Opcion(_Orden.precio, 'Más barato'),
          _Opcion(_Orden.cupos, 'Más cupos'),
        ],
        valor: orden,
        onElegir: onOrden,
      ),
    );
    final cupos = _GrupoFiltro(
      etiqueta: 'DISPONIBILIDAD',
      child: _Segmentos<bool>(
        opciones: const [_Opcion(false, 'Todos'), _Opcion(true, 'Últimos cupos')],
        valor: soloUltimos,
        onElegir: onUltimos,
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceVariant),
      ),
      child: LayoutBuilder(builder: (context, restricciones) {
        if (restricciones.maxWidth >= 900) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 4, child: salida),
              const SizedBox(width: AppSpacing.lg),
              Expanded(flex: 3, child: ordenar),
              const SizedBox(width: AppSpacing.lg),
              Expanded(flex: 2, child: cupos),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [salida, const SizedBox(height: AppSpacing.md), ordenar, const SizedBox(height: AppSpacing.md), cupos],
        );
      }),
    );
  }
}

class _GrupoFiltro extends StatelessWidget {
  const _GrupoFiltro({required this.etiqueta, required this.child});

  final String etiqueta;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(etiqueta, style: AppTheme.telemetry(size: 11, weight: FontWeight.w700, color: AppColors.onSurfaceVariant)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _Opcion<T> {
  const _Opcion(this.valor, this.etiqueta, {this.ayuda});

  final T valor;
  final String etiqueta;
  final String? ayuda;
}

// Control segmentado: segmentos del mismo ancho en un riel de 44 px; el elegido se rellena de oscuro.
class _Segmentos<T> extends StatelessWidget {
  const _Segmentos({required this.opciones, required this.valor, required this.onElegir});

  final List<_Opcion<T>> opciones;
  final T? valor;
  final ValueChanged<T> onElegir;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.slate300),
      ),
      child: Row(
        children: [
          for (final o in opciones)
            Expanded(
              child: Tooltip(
                message: o.ayuda ?? o.etiqueta,
                child: Semantics(
                  button: true,
                  selected: o.valor == valor,
                  label: o.etiqueta,
                  child: InkWell(
                    onTap: () => onElegir(o.valor),
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: o.valor == valor ? AppColors.slate900 : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          o.etiqueta,
                          maxLines: 1,
                          style: AppTheme.labelLg(color: o.valor == valor ? Colors.white : AppColors.onSurface),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ResultadosVuelos extends StatelessWidget {
  const ResultadosVuelos({
    super.key,
    required this.vuelos,
    required this.onReservar,
    this.acciones,
    this.onCrear,
    this.gestion = const {},
    this.subtitulo,
    this.controles,
    this.onLimpiarFiltros,
  });

  final List<Vuelo> vuelos;
  final ValueChanged<Vuelo> onReservar;
  // Botones extra por vuelo (solo administrador).
  final Widget? Function(Vuelo vuelo)? acciones;
  // Solo administradores: crear un vuelo desde la cabecera de resultados.
  final VoidCallback? onCrear;
  // Datos de ocupación por vuelo (solo administrador).
  final Map<int, VueloAdmin> gestion;
  final String? subtitulo;
  // Orden y filtros, bajo el título.
  final Widget? controles;
  // Si hay filtros activos, el estado vacío ofrece quitarlos.
  final VoidCallback? onLimpiarFiltros;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Vuelos disponibles', style: AppTheme.headlineMd()),
                if (subtitulo != null) Text(subtitulo!, style: AppTheme.bodySm(color: AppColors.onSurfaceVariant)),
              ],
            ),
            if (onCrear != null)
              FilledButton.icon(
                onPressed: onCrear,
                icon: const Icon(Icons.add, size: 18),
                label: Text('Crear vuelo', style: AppTheme.labelLg(color: AppColors.onPrimary).copyWith(fontWeight: FontWeight.w700)),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
                ),
              ),
          ],
        ),
        if (controles != null) ...[
          const SizedBox(height: AppSpacing.md),
          controles!,
        ],
        const SizedBox(height: AppSpacing.md),
        if (vuelos.isEmpty)
          _SinVuelos(onLimpiar: onLimpiarFiltros)
        else
          Column(
            children: [
              for (final vuelo in vuelos) ...[
                _FilaVuelo(
                  vuelo: vuelo,
                  onReservar: () => onReservar(vuelo),
                  acciones: acciones?.call(vuelo),
                  gestion: gestion[vuelo.id],
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ],
          ),
      ],
    );
  }
}

class _SinVuelos extends StatelessWidget {
  const _SinVuelos({this.onLimpiar});

  final VoidCallback? onLimpiar;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        children: [
          const Icon(Icons.search_off, size: 36, color: AppColors.secondary),
          const SizedBox(height: AppSpacing.sm),
          Text('No hay vuelos con esos filtros.', style: AppTheme.headlineSm(), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text('Prueba con otra fecha o mira todos los destinos desde tu origen.',
              style: AppTheme.bodyMd(color: AppColors.onSurfaceVariant), textAlign: TextAlign.center),
          if (onLimpiar != null) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: onLimpiar, child: const Text('Quitar filtros')),
          ],
        ],
      ),
    );
  }
}

// Fila de vuelo: salida → llegada, ruta, cupos, precio con IVA y reserva.
// En pantallas angostas las partes se apilan; la franja de administración queda al pie.
class _FilaVuelo extends StatelessWidget {
  const _FilaVuelo({required this.vuelo, required this.onReservar, this.acciones, this.gestion});

  final Vuelo vuelo;
  final VoidCallback onReservar;
  final Widget? acciones;
  final VueloAdmin? gestion;

  @override
  Widget build(BuildContext context) {
    final agotado = vuelo.agotado;
    final boton = Permisos(session.rol).puedeReservar
        ? SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: agotado || !vuelo.activo || vuelo.ventaCerrada ? null : onReservar,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.surfaceContainerHighest,
                disabledForegroundColor: AppColors.onSurfaceVariant.withValues(alpha: 0.6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                agotado ? 'Agotado' : (vuelo.ventaCerrada ? 'Venta cerrada' : 'Reservar'),
                style: AppTheme.labelLg(color: AppColors.onPrimary).copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          )
        : null;

    final contenido = LayoutBuilder(builder: (context, restricciones) {
      final ancha = restricciones.maxWidth >= 860;
      if (ancha) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: 210, child: _Horario(vuelo: vuelo)),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: _Ruta(origen: vuelo.origen, destino: vuelo.destino)),
            const SizedBox(width: AppSpacing.lg),
            SizedBox(width: 190, child: _Cupos(vuelo: vuelo)),
            const SizedBox(width: AppSpacing.lg),
            SizedBox(width: 150, child: _Precio(vuelo: vuelo)),
            if (boton != null) ...[
              const SizedBox(width: AppSpacing.lg),
              SizedBox(width: 150, child: boton),
            ],
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Horario(vuelo: vuelo),
          const SizedBox(height: AppSpacing.md),
          _Ruta(origen: vuelo.origen, destino: vuelo.destino),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: _Cupos(vuelo: vuelo)),
              const SizedBox(width: AppSpacing.md),
              _Precio(vuelo: vuelo),
            ],
          ),
          if (boton != null) ...[
            const SizedBox(height: AppSpacing.md),
            boton,
          ],
        ],
      );
    });

    final admin = acciones != null || gestion != null;

    return Opacity(
      opacity: agotado ? 0.85 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.surfaceVariant),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(padding: const EdgeInsets.all(AppSpacing.lg), child: contenido),
            if (admin)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                decoration: const BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  border: Border(top: BorderSide(color: AppColors.surfaceVariant)),
                ),
                child: Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.sm,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('VUELO #${vuelo.id}', style: AppTheme.telemetry(size: 11, weight: FontWeight.w700, color: AppColors.onSurfaceVariant)),
                        if (gestion != null)
                          Text('${gestion!.asientosOcupados} de ${gestion!.totalAsientos} asientos ocupados',
                              style: AppTheme.bodySm(color: AppColors.onSurfaceVariant)),
                      ],
                    ),
                    if (acciones != null) acciones!,
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Salida → llegada. La llegada es opcional: sin ella se avisa que está por confirmar.
class _Horario extends StatelessWidget {
  const _Horario({required this.vuelo});

  final Vuelo vuelo;

  @override
  Widget build(BuildContext context) {
    final estilo = AppTheme.telemetry(size: 22, weight: FontWeight.w700, color: AppColors.onSurface);
    final llegada = vuelo.horaLlegada;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(vuelo.hora, style: estilo),
            if (llegada != null) ...[
              const Icon(Icons.arrow_forward, size: 16, color: AppColors.outline),
              Text(llegada, style: estilo),
              if (vuelo.llegaDiaSiguiente) Text('+1', style: AppTheme.telemetry(size: 12, weight: FontWeight.w700, color: AppColors.secondary)),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          llegada == null ? '${_etiquetaFecha(vuelo.fecha)} · llegada por confirmar' : _etiquetaFecha(vuelo.fecha),
          style: AppTheme.bodySm(color: AppColors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Ruta extends StatelessWidget {
  const _Ruta({required this.origen, required this.destino});

  final String origen;
  final String destino;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Ciudad(codigo: origen, alineacion: CrossAxisAlignment.start),
        const Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(child: _LineaCorte(vertical: false)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.flight, size: 18, color: AppColors.secondary),
                ),
                Expanded(child: _LineaCorte(vertical: false)),
              ],
            ),
          ),
        ),
        _Ciudad(codigo: destino, alineacion: CrossAxisAlignment.end),
      ],
    );
  }
}

class _Cupos extends StatelessWidget {
  const _Cupos({required this.vuelo});

  final Vuelo vuelo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InsigniaEstado(vuelo: vuelo),
        const SizedBox(height: 6),
        Text(
          vuelo.agotado ? 'Sin asientos disponibles' : '${vuelo.asientosDisponibles} asientos libres',
          style: AppTheme.labelMd(color: AppColors.onSurfaceVariant),
        ),
      ],
    );
  }
}

// Tarifa por pasajero y su total con IVA 15 % (el mismo cálculo de la factura).
class _Precio extends StatelessWidget {
  const _Precio({required this.vuelo});

  final Vuelo vuelo;

  @override
  Widget build(BuildContext context) {
    final conIva = vuelo.precio + calcularIva(vuelo.precio);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('\$${vuelo.precio.toStringAsFixed(2)}', style: AppTheme.headlineMd().copyWith(fontWeight: FontWeight.w800)),
        Text('\$${conIva.toStringAsFixed(2)} con IVA 15 %', style: AppTheme.bodySm(color: AppColors.onSurfaceVariant).copyWith(fontSize: 12)),
      ],
    );
  }
}

// Línea punteada (horizontal o vertical) del trayecto.
class _LineaCorte extends StatelessWidget {
  const _LineaCorte({required this.vertical});

  final bool vertical;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: vertical ? 1 : double.infinity,
      height: vertical ? double.infinity : 1,
      child: CustomPaint(painter: _PintorCorte(vertical: vertical)),
    );
  }
}

class _PintorCorte extends CustomPainter {
  _PintorCorte({required this.vertical});

  final bool vertical;

  @override
  void paint(Canvas canvas, Size size) {
    final pincel = Paint()
      ..color = AppColors.outline
      ..strokeWidth = 1;
    final largo = vertical ? size.height : size.width;
    const trazo = 6.0;
    const hueco = 4.0;
    for (var pos = 0.0; pos < largo; pos += trazo + hueco) {
      final fin = (pos + trazo).clamp(0.0, largo);
      canvas.drawLine(
        vertical ? Offset(0, pos) : Offset(pos, 0),
        vertical ? Offset(0, fin) : Offset(fin, 0),
        pincel,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PintorCorte antiguo) => antiguo.vertical != vertical;
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
                : ('DISPONIBLE', AppColors.secondaryFixed, AppColors.onSecondaryFixed);
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
        Text(codigo, style: AppTheme.headlineMd().copyWith(fontWeight: FontWeight.w800, height: 1.1)),
        Text(_ciudades[codigo] ?? codigo, style: AppTheme.bodySm().copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
