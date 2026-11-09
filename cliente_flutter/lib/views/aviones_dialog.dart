import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/services.dart';
import '../core/validadores.dart';
import '../theme/app_theme.dart';
import '../widgets/alerta.dart';
import '../widgets/plano_formulario.dart';

// Registro de aviones (solo administradores). Cada avión tiene nombre y capacidad: su número de asientos.
// Lista: GET /api/admin/aviones. Alta: POST. Edición: PUT. Activar o desactivar: PATCH .../estado (S6).
class AvionesDialog extends StatefulWidget {
  const AvionesDialog({super.key, required this.token});

  final String token;

  @override
  State<AvionesDialog> createState() => _AvionesDialogState();
}

class _AvionesDialogState extends State<AvionesDialog> {
  List<Avion>? _aviones;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final lista = await AvionesService.listar(token: widget.token);
      if (!mounted) return;
      setState(() {
        _aviones = lista;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.mensaje);
    }
  }

  Future<void> _formulario({Avion? avion}) async {
    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) => _FormularioAvion(token: widget.token, avion: avion),
    );
    if (guardado == true) await _cargar();
  }

  Future<void> _cambiarEstado(Avion avion) async {
    try {
      await AvionesService.cambiarEstado(id: avion.id, activo: !avion.activo, token: widget.token);
      await _cargar();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.lg),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: AppColors.brandNavy,
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.sm, AppSpacing.md),
              child: Row(
                children: [
                  Expanded(child: Text('Aviones', style: AppTheme.headlineSm(color: Colors.white))),
                  FilledButton.icon(
                    onPressed: _aviones == null ? null : () => _formulario(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Registrar avión'),
                  ),
                  IconButton(tooltip: 'Cerrar', onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close, color: Colors.white)),
                ],
              ),
            ),
            Flexible(child: _cuerpo()),
          ],
        ),
      ),
    );
  }

  Widget _cuerpo() {
    final lista = _aviones;
    if (lista == null) {
      if (_error != null) {
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Alerta(tipo: TipoAlerta.error, texto: _error!),
        );
      }
      return const Padding(padding: EdgeInsets.all(AppSpacing.xl), child: Center(child: CircularProgressIndicator()));
    }
    if (lista.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          'Aún no hay aviones. Registre uno con su nombre y su capacidad (número de asientos).',
          style: AppTheme.bodySm(color: AppColors.onSurfaceVariant),
        ),
      );
    }
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (_error != null) ...[
          Alerta(tipo: TipoAlerta.error, texto: _error!),
          const SizedBox(height: AppSpacing.md),
        ],
        for (final avion in lista) ...[
          _FilaAvion(
            avion: avion,
            onEditar: () => _formulario(avion: avion),
            onEstado: () => _cambiarEstado(avion),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _FilaAvion extends StatelessWidget {
  const _FilaAvion({required this.avion, required this.onEditar, required this.onEstado});

  final Avion avion;
  final VoidCallback onEditar;
  final VoidCallback onEstado;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(avion.nombre, style: AppTheme.labelLg(), overflow: TextOverflow.ellipsis),
                Text(
                  '${avion.capacidad} asientos · ${avion.filas} filas de 3 + 3${avion.activo ? '' : ' · desactivado'}',
                  style: AppTheme.bodySm(color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Switch(value: avion.activo, onChanged: (_) => onEstado()),
          IconButton(tooltip: 'Editar avión', onPressed: onEditar, icon: const Icon(Icons.edit_outlined)),
        ],
      ),
    );
  }
}

// Alta o edición de un avión. Mismo modelo que el alta de vuelo: formulario a la izquierda y vista previa
// del plano a la derecha, que se redibuja al elegir la capacidad (las mismas reglas de cabina del servidor).
class _FormularioAvion extends StatefulWidget {
  const _FormularioAvion({required this.token, this.avion});

  final String token;
  final Avion? avion;

  @override
  State<_FormularioAvion> createState() => _FormularioAvionState();
}

class _FormularioAvionState extends State<_FormularioAvion> {
  final _form = GlobalKey<FormState>();
  final TransformationController _zoom = TransformationController();
  late final TextEditingController _nombre;
  late int _capacidad;
  bool _enviando = false;
  String? _error;

  bool get _editando => widget.avion != null;

  @override
  void initState() {
    super.initState();
    _nombre = TextEditingController(text: widget.avion?.nombre ?? '');
    _capacidad = widget.avion?.capacidad ?? minimoAsientos;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _zoom.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    final nombre = _nombre.text;
    try {
      if (_editando) {
        await AvionesService.editar(id: widget.avion!.id, nombre: nombre, capacidad: _capacidad, token: widget.token);
      } else {
        await AvionesService.crear(nombre: nombre, capacidad: _capacidad, token: widget.token);
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
    final filas = _capacidad ~/ pasoAsientos;
    final opciones = [for (var n = minimoAsientos; n <= maximoAsientos; n += pasoAsientos) n];

    final formulario = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SeccionFormulario(
          titulo: 'DATOS DEL AVIÓN',
          hijo: TextFormField(
            controller: _nombre,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'Nombre del avión', hintText: 'Airbus A320-200'),
            validator: validarNombreAvion,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SeccionFormulario(
          titulo: 'CAPACIDAD',
          hijo: DropdownButtonFormField<int>(
            initialValue: _capacidad,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Número de asientos',
              helperText: '$_capacidad asientos · $filas filas de 3 + 3',
            ),
            items: [for (final n in opciones) DropdownMenuItem(value: n, child: Text('$n asientos'))],
            onChanged: (v) {
              if (v != null) setState(() => _capacidad = v);
            },
          ),
        ),
        if (_editando) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            'Cambiar la capacidad solo afecta a los vuelos que se creen después; los vuelos existentes conservan su plano.',
            style: AppTheme.bodySm(color: AppColors.onSurfaceVariant).copyWith(fontSize: 12),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Alerta(tipo: TipoAlerta.error, texto: _error!),
        ],
      ],
    );

    final previa = VistaPreviaAvion(
      key: const ValueKey('vista-previa-avion-avion'),
      total: _capacidad,
      asientos: asientosPrevia(_capacidad),
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
              CabeceraFormulario(
                icono: Icons.airplanemode_active,
                titulo: _editando ? 'Editar avión #${widget.avion!.id}' : 'Registrar avión',
                endpoint: _editando ? 'PUT /api/admin/aviones/${widget.avion!.id} · S6 :5006' : 'POST /api/admin/aviones · S6 :5006',
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
                      child: Text(_enviando ? 'Guardando...' : (_editando ? 'Guardar cambios' : 'Registrar avión')),
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
}
