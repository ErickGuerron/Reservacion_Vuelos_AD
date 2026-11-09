import 'package:flutter/material.dart';

import '../core/aeropuertos.dart';
import '../core/api_client.dart';
import '../core/horarios.dart';
import '../core/lotes.dart' show calcularIva;
import '../core/models.dart';
import '../core/services.dart';
import '../core/validadores.dart';
import '../theme/app_theme.dart';
import '../widgets/alerta.dart';
import 'mapa_asientos.dart';

// Políticas de cabina (mismas reglas que el servicio S6): 18 a 180 asientos, filas de 3 + 3.
const minimoAsientos = 18;
const maximoAsientos = 180;
const pasoAsientos = 6;

// Alta o edición de vuelo para administradores. Crear: POST /api/admin/vuelos.
// Editar: PUT /api/admin/vuelos/{id}, solo si el vuelo no tiene reservas.
// El avión (S6) pone los asientos del vuelo: se elige de la lista de aviones activos.
class AdminVueloDialog extends StatefulWidget {
  const AdminVueloDialog({super.key, required this.token, this.vuelo});

  final String token;
  // Si viene, el diálogo edita este vuelo; si no, crea uno nuevo.
  final VueloAdmin? vuelo;

  @override
  State<AdminVueloDialog> createState() => _AdminVueloDialogState();
}

class _AdminVueloDialogState extends State<AdminVueloDialog> {
  final _form = GlobalKey<FormState>();
  late String _origen;
  late String _destino;
  late final TextEditingController _fecha;
  late final TextEditingController _hora;
  late final TextEditingController _llegada;
  late final TextEditingController _precio;
  // Avión elegido: su capacidad son los asientos del vuelo. Null hasta elegir uno.
  int? _avionId;
  // Aviones que se pueden asignar: los activos, más el del vuelo que se edita aunque esté desactivado.
  List<Avion>? _aviones;
  String? _errorAviones;
  bool _enviando = false;
  // Duración habitual de la ruta según S3, y número de consulta para ignorar respuestas atrasadas.
  EstimacionVuelo? _estimacion;
  // Vista previa del avión: el mismo plano de la selección de asientos, dibujado con el total elegido.
  final TransformationController _zoom = TransformationController();
  late List<Asiento> _asientosPrevia;
  int _consulta = 0;
  String? _error;
  // Al crear: false deja el vuelo como borrador (valor por defecto).
  bool _publicar = false;
  final DateTime _now = DateTime.now().add(
    const Duration(hours: 2, minutes: 30)
  );
  bool get _editando => widget.vuelo != null;

  @override
  void initState() {
    super.initState();
    final v = widget.vuelo;
    // Solo se pueden elegir aeropuertos de la lista; si el vuelo guardado usa otro, se parte del primero.
    _origen = aeropuertos.containsKey(v?.origen) ? v!.origen : aeropuertos.keys.first;
    _destino = aeropuertos.containsKey(v?.destino) ? v!.destino : aeropuertos.keys.last;
    _fecha = TextEditingController(text: v?.fecha ?? '');
    _hora = TextEditingController(text: v?.hora ?? "${_now.hour.toString().padLeft(2,'0')}:${_now.minute.toString().padLeft(2,'0')}");
    _llegada = TextEditingController(text: v?.horaLlegada ?? '');
    _precio = TextEditingController(text: v == null ? '' : v.precio.toStringAsFixed(2));
    // Un vuelo anterior al registro de aviones no tiene avión: el administrador debe elegir uno.
    _avionId = v?.avionId;
    _asientosPrevia = const <Asiento>[];
    _cargarAviones();
    _actualizarEstimacion();
  }

  Future<void> _cargarAviones() async {
    try {
      final todos = await AvionesService.listar(token: widget.token);
      if (!mounted) return;
      setState(() {
        _aviones = [for (final a in todos) if (a.activo || a.id == _avionId) a];
        final elegido = _avionElegido;
        if (elegido != null) _asientosPrevia = _construirPrevia(elegido.capacidad);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errorAviones = e.mensaje);
    }
  }

  Avion? get _avionElegido {
    final id = _avionId;
    final lista = _aviones;
    if (id == null || lista == null) return null;
    for (final a in lista) {
      if (a.id == id) return a;
    }
    return null;
  }

  @override
  void dispose() {
    _fecha.dispose();
    _hora.dispose();
    _llegada.dispose();
    _zoom.dispose();
    _precio.dispose();
    super.dispose();
  }

  static const _columnas = ['F', 'E', 'D', 'C', 'B', 'A'];

  // Todos los asientos libres de un avión de [total] asientos: filas de 3 + 3.
  static List<Asiento> _construirPrevia(int total) => asientosDesde([
        for (var fila = 1; fila <= total ~/ pasoAsientos; fila++)
          for (final c in _columnas) AsientoRemoto(codigo: '$fila$c', fila: fila, columna: c, ocupado: false),
      ]);

  // Elegir avión: el plano de la vista previa muestra su capacidad.
  void _cambiarAvion(int id) {
    setState(() {
      _avionId = id;
      _asientosPrevia = _construirPrevia(_avionElegido?.capacidad ?? minimoAsientos);
    });
  }

  void _invertirRuta() {
    setState(() {
      final tmp = _origen;
      _origen = _destino;
      _destino = tmp;
    });
    _actualizarEstimacion();
  }

  // Primer día en que se puede programar un vuelo: mañana.
  DateTime get _primerDiaPermitido {
    final hoy = DateTime.now();
    return DateTime(hoy.year, hoy.month, hoy.day + 1);
  }

  static String _formatoFecha(DateTime f) =>
      '${f.year.toString().padLeft(4, '0')}-${f.month.toString().padLeft(2, '0')}-${f.day.toString().padLeft(2, '0')}';

  Future<void> _elegirFecha() async {
    final primero = _primerDiaPermitido;
    // Un vuelo ya guardado con fecha anterior a mañana no puede ser la fecha inicial del calendario.
    final actual = DateTime.tryParse(_fecha.text.trim());
    final inicial = actual != null && !actual.isBefore(primero) ? actual : primero;
    final elegida = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: primero,
      lastDate: DateTime(primero.year + 3, primero.month, primero.day),
    );
    if (elegida != null) {
      setState(() => _fecha.text = _formatoFecha(elegida));
      _actualizarEstimacion();
    }
  }

  Future<void> _elegirHora() async {
    final partes = _hora.text.trim().split(':');
    final actual = validarHora(_hora.text) == null
        ? TimeOfDay(hour: int.parse(partes[0]), minute: int.parse(partes[1]))
        : const TimeOfDay(hour: 8, minute: 0);
    final elegida = await showTimePicker(
      context: context,
      initialTime: actual,
      // Formato de 24 horas: la hora se guarda como HH:MM, sin AM/PM.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (elegida != null) {
      setState(() => _hora.text = '${elegida.hour.toString().padLeft(2, '0')}:${elegida.minute.toString().padLeft(2, '0')}');
      _actualizarEstimacion();
    }
  }

  Future<void> _elegirLlegada() async {
    final partes = _llegada.text.trim().split(':');
    final actual = validarHora(_llegada.text) == null
        ? TimeOfDay(hour: int.parse(partes[0]), minute: int.parse(partes[1]))
        : const TimeOfDay(hour: 9, minute: 0);
    final elegida = await showTimePicker(
      context: context,
      initialTime: actual,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (elegida != null) {
      setState(() => _llegada.text = '${elegida.hour.toString().padLeft(2, '0')}:${elegida.minute.toString().padLeft(2, '0')}');
      _actualizarEstimacion();
    }
  }

  // La llegada es opcional: vacía se guarda como null; si se escribe, debe ser HH:MM.
  String? _validarLlegada(String? valor) => (valor ?? '').trim().isEmpty ? null : validarHora(valor);

  // Pide a S3 la duración habitual de la ruta con la salida actual (y valida la llegada si ya hay una).
  Future<void> _actualizarEstimacion() async {
    final fecha = _fecha.text.trim();
    final hora = _hora.text.trim();
    final llegada = _llegada.text.trim();
    final completo = validarFecha(fecha) == null &&
        validarHora(hora) == null &&
        _origen != _destino &&
        (llegada.isEmpty || validarHora(llegada) == null);
    if (!completo) {
      if (_estimacion != null) setState(() => _estimacion = null);
      return;
    }
    final consulta = ++_consulta;
    final e = await VuelosService.estimacion(
      origen: _origen,
      destino: _destino,
      fecha: fecha,
      hora: hora,
      horaLlegada: llegada.isEmpty ? null : llegada,
    );
    if (!mounted || consulta != _consulta) return;
    setState(() => _estimacion = e);
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    final fecha = _fecha.text.trim();
    final hora = _hora.text.trim();
    final llegada = _llegada.text.trim().isEmpty ? null : _llegada.text.trim();
    final precio = double.parse(_precio.text.trim());
    try {
      if (_editando) {
        await GestionVuelosService.editar(
          id: widget.vuelo!.id,
          origen: _origen,
          destino: _destino,
          fecha: fecha,
          hora: hora,
          horaLlegada: llegada,
          precio: precio,
          avionId: _avionId!,
          token: widget.token,
        );
      } else {
        await AdminService.crearVuelo(
          activo: _publicar,
          origen: _origen,
          destino: _destino,
          fecha: fecha,
          hora: hora,
          horaLlegada: llegada,
          precio: precio,
          avionId: _avionId!,
          token: widget.token,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _error = e.mensaje;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final precio = double.tryParse(_precio.text.trim());
    final avion = _avionElegido;
    final total = avion?.capacidad ?? 0;
    final filas = total ~/ pasoAsientos;
    final aviones = _aviones ?? const <Avion>[];

    final formulario = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Seccion(
          titulo: 'RUTA',
          hijo: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _selectorAeropuerto('Origen', _origen, (v) {
                setState(() => _origen = v);
                _actualizarEstimacion();
              })),
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
                child: IconButton.outlined(
                  tooltip: 'Invertir origen y destino',
                  onPressed: _invertirRuta,
                  icon: const Icon(Icons.swap_horiz),
                ),
              ),
              Expanded(
                child: _selectorAeropuerto('Destino', _destino, (v) {
                  setState(() => _destino = v);
                  _actualizarEstimacion();
                }, validator: (v) => v == _origen ? 'Distinto del origen' : null),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _Seccion(
          titulo: 'HORARIO',
          hijo: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _fecha,
                readOnly: true,
                onTap: _elegirFecha,
                decoration: InputDecoration(
                  labelText: 'Fecha de salida',
                  hintText: 'AAAA-MM-DD',
                  suffixIcon: IconButton(
                    tooltip: 'Elegir fecha',
                    icon: const Icon(Icons.calendar_today_outlined),
                    onPressed: _elegirFecha,
                  ),
                ),
                validator: validarFechaVuelo,
              ),
              const SizedBox(height: AppSpacing.sm + 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _hora,
                      readOnly: true,
                      onTap: _elegirHora,
                      decoration: InputDecoration(
                        labelText: 'Hora de salida',
                        hintText: 'HH:MM',
                        suffixIcon: IconButton(
                          tooltip: 'Elegir hora de salida',
                          icon: const Icon(Icons.flight_takeoff_outlined),
                          onPressed: _elegirHora,
                        ),
                      ),
                      validator: validarHora,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm + 4),
                  Expanded(
                    child: TextFormField(
                      controller: _llegada,
                      readOnly: true,
                      onTap: _elegirLlegada,
                      decoration: InputDecoration(
                        labelText: 'Hora de llegada',
                        hintText: 'Opcional',
                        // Vacía: icono de aterrizaje para elegirla. Con hora: la X la quita.
                        suffixIcon: _llegada.text.isEmpty
                            ? IconButton(
                                tooltip: 'Elegir hora de llegada',
                                icon: const Icon(Icons.flight_land_outlined),
                                onPressed: _elegirLlegada,
                              )
                            : IconButton(
                                tooltip: 'Quitar hora de llegada',
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  setState(() => _llegada.clear());
                                  _actualizarEstimacion();
                                },
                              ),
                      ),
                      validator: _validarLlegada,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'La llegada es opcional y en hora local del destino. Si es menor que la salida se muestra como +1 día.',
                style: AppTheme.bodySm(color: AppColors.onSurfaceVariant).copyWith(fontSize: 12),
              ),
              if (_estimacion != null) ...[
                const SizedBox(height: AppSpacing.sm + 4),
                _PanelDuracion(
                  ruta: '$_origen → $_destino',
                  estimacion: _estimacion!,
                  hayLlegada: _llegada.text.trim().isNotEmpty,
                  onUsarSugerida: () {
                    setState(() => _llegada.text = _estimacion!.horaLlegadaSugerida);
                    _actualizarEstimacion();
                  },
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _Seccion(
          titulo: 'TARIFA Y AVIÓN',
          hijo: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _precio,
                  inputFormatters: [PrecioFormatter()],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Precio por pasajero',
                    prefixText: '\$ ',
                    suffixText: 'USD',
                    helperText: precio == null || precio <= 0 ? 'Sin IVA' : 'Con IVA 15 %: \$${(precio + calcularIva(precio)).toStringAsFixed(2)}',
                  ),
                  validator: validarPrecio,
                ),
              ),
              const SizedBox(width: AppSpacing.sm + 4),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _avionId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Avión',
                    helperText: avion == null ? null : '${avion.capacidad} asientos · $filas filas de 3 + 3',
                  ),
                  items: [
                    for (final a in aviones)
                      DropdownMenuItem(
                        value: a.id,
                        child: Text(
                          a.activo ? '${a.nombre} · ${a.capacidad} asientos' : '${a.nombre} · ${a.capacidad} asientos (desactivado)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  validator: (v) => v == null ? 'Elija un avión.' : null,
                  onChanged: (v) {
                    if (v != null) _cambiarAvion(v);
                  },
                ),
              ),
            ],
          ),
        ),
        if (_errorAviones != null) ...[
          const SizedBox(height: AppSpacing.md),
          Alerta(tipo: TipoAlerta.error, texto: 'No se pudieron cargar los aviones: $_errorAviones'),
        ] else if (_aviones != null && aviones.isEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          const Alerta(tipo: TipoAlerta.aviso, texto: 'No hay aviones activos. Registre uno con el botón Aviones antes de crear el vuelo.'),
        ],
        if (!_editando) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.surfaceVariant),
            ),
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              value: _publicar,
              onChanged: (v) => setState(() => _publicar = v),
              title: const Text('Publicar al crear'),
              subtitle: Text(_publicar ? 'Visible para los clientes desde que se crea.' : 'Apagado: queda como borrador y nadie lo verá hasta publicarlo.'),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Alerta(tipo: TipoAlerta.error, texto: _error!),
        ],
      ],
    );

    final previa = avion == null
        ? Container(
            height: 280,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text('Elija un avión para ver su plano de asientos.', textAlign: TextAlign.center, style: AppTheme.bodySm(color: AppColors.onSurfaceVariant)),
          )
        : _VistaPreviaAvion(
            key: const ValueKey('vista-previa-avion'),
            total: total,
            asientos: _asientosPrevia,
            controlador: _zoom,
          );

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.lg),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CabeceraFormulario(
                titulo: _editando ? 'Editar vuelo #${widget.vuelo!.id}' : 'Crear vuelo',
                endpoint: _editando ? 'PUT /api/admin/vuelos/${widget.vuelo!.id} · S3 :5003' : 'POST /api/admin/vuelos · S3 :5003',
                onCerrar: _enviando ? null : () => Navigator.of(context).pop(false),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: LayoutBuilder(builder: (context, restricciones) {
                    if (restricciones.maxWidth >= 720) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 11, child: formulario),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(flex: 9, child: previa),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [formulario, const SizedBox(height: AppSpacing.lg), previa],
                    );
                  }),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                color: AppColors.surfaceContainerLow,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    TextButton(
                      onPressed: _enviando ? null : () => Navigator.of(context).pop(false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed: _enviando ? null : _guardar,
                      child: Text(_enviando ? 'Guardando...' : (_editando ? 'Guardar cambios' : 'Crear vuelo')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Selector de aeropuerto: muestra "UIO · Quito" y lista el nombre completo.
  Widget _selectorAeropuerto(String etiqueta, String valor, ValueChanged<String> alCambiar, {FormFieldValidator<String>? validator}) {
    return DropdownButtonFormField<String>(
      key: ValueKey('$etiqueta-$valor'),
      initialValue: valor,
      isExpanded: true,
      decoration: InputDecoration(labelText: etiqueta),
      selectedItemBuilder: (context) => [
        for (final e in aeropuertos.entries) Text('${e.key} · ${ciudadDe(e.key)}', overflow: TextOverflow.ellipsis),
      ],
      items: [for (final e in aeropuertos.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
      validator: validator,
      onChanged: (v) {
        if (v != null) alCambiar(v);
      },
    );
  }
}

class _CabeceraFormulario extends StatelessWidget {
  const _CabeceraFormulario({required this.titulo, required this.endpoint, required this.onCerrar});

  final String titulo;
  final String endpoint;
  final VoidCallback? onCerrar;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.brandNavy,
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.sm, AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(color: Color(0xFF0F6A97), shape: BoxShape.circle),
            child: const Icon(Icons.flight, color: Colors.white),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: AppTheme.headlineSm(color: Colors.white)),
                Text(endpoint, style: AppTheme.telemetry(size: 12, weight: FontWeight.w600, color: const Color(0xFF5CB8F5)), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(tooltip: 'Cerrar', onPressed: onCerrar, icon: const Icon(Icons.close, color: Colors.white)),
        ],
      ),
    );
  }
}

// Sección del formulario: título en mayúsculas y sus campos.
class _Seccion extends StatelessWidget {
  const _Seccion({required this.titulo, required this.hijo});

  final String titulo;
  final Widget hijo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(titulo, style: AppTheme.telemetry(size: 11, weight: FontWeight.w700, color: AppColors.onSurfaceVariant)),
        const SizedBox(height: AppSpacing.sm),
        hijo,
      ],
    );
  }
}

// Plano del avión con el mismo dibujo del mapa de asientos, todos los asientos libres.
class _VistaPreviaAvion extends StatelessWidget {
  const _VistaPreviaAvion({super.key, required this.total, required this.asientos, required this.controlador});

  final int total;
  final List<Asiento> asientos;
  final TransformationController controlador;

  @override
  Widget build(BuildContext context) {
    final filas = total ~/ pasoAsientos;
    final nota = filas >= 14
        ? 'Salidas de emergencia en las filas 13 y 14.'
        : filas == 13
            ? 'Salida de emergencia en la fila 13.'
            : 'Con menos de 78 asientos no hay filas de salida (13 y 14).';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('VISTA PREVIA DEL AVIÓN', style: AppTheme.telemetry(size: 11, weight: FontWeight.w700, color: AppColors.onSurfaceVariant)),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _Dato('$total asientos'),
            _Dato('$filas filas'),
            const _Dato('3 + 3'),
          ],
        ),
        const SizedBox(height: AppSpacing.sm + 4),
        Container(
          height: 280,
          decoration: BoxDecoration(
            color: const Color(0xFFE6EAF6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFC7CFEA)),
          ),
          clipBehavior: Clip.antiAlias,
          // La llave por total vuelve a encuadrar el avión cada vez que cambia el número de filas.
          child: MapaAsientos(key: ValueKey(total), asientos: asientos, controlador: controlador, onToque: (_) {}),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text('Así verán el mapa los pasajeros al reservar. $nota', style: AppTheme.bodySm(color: AppColors.onSurfaceVariant).copyWith(fontSize: 12)),
      ],
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: BorderRadius.circular(999), border: Border.all(color: AppColors.surfaceVariant)),
      child: Text(texto, style: AppTheme.labelMd()),
    );
  }
}

// Duración habitual de la ruta: sugiere la llegada o avisa si la indicada no corresponde. El servidor
// vuelve a validar al guardar.
class _PanelDuracion extends StatelessWidget {
  const _PanelDuracion({required this.ruta, required this.estimacion, required this.hayLlegada, required this.onUsarSugerida});

  final String ruta;
  final EstimacionVuelo estimacion;
  final bool hayLlegada;
  final VoidCallback onUsarSugerida;

  @override
  Widget build(BuildContext context) {
    final invalida = estimacion.valida == false;
    final fondo = invalida ? AppColors.errorBg : AppColors.surfaceContainerLow;
    final borde = invalida ? AppColors.errorBorder : AppColors.surfaceVariant;
    final texto = invalida ? AppColors.errorText : AppColors.onSurfaceVariant;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm + 4),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(8), border: Border.all(color: borde)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(invalida ? Icons.error_outline : Icons.schedule, size: 18, color: texto),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  invalida
                      ? (estimacion.mensaje ?? 'La llegada no corresponde a la duración habitual de la ruta.')
                      : 'Duración habitual $ruta: ${duracionTexto(estimacion.duracionHabitual)} '
                          '(entre ${duracionTexto(estimacion.duracionMinima)} y ${duracionTexto(estimacion.duracionMaxima)}).',
                  style: AppTheme.bodySm(color: texto).copyWith(fontSize: 12),
                ),
              ),
            ],
          ),
          if (!hayLlegada || invalida)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onUsarSugerida,
                child: Text('Usar llegada sugerida ${estimacion.horaLlegadaSugerida}'),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 26),
              child: Text('La llegada es coherente con la ruta.', style: AppTheme.bodySm(color: AppColors.successText).copyWith(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
