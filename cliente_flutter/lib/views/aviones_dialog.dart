import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/services.dart';
import '../core/validadores.dart';
import '../theme/app_theme.dart';
import '../widgets/alerta.dart';
import 'admin_vuelo_dialog.dart'
    show maximoAsientos, minimoAsientos, pasoAsientos;

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
      await AvionesService.cambiarEstado(
        id: avion.id,
        activo: !avion.activo,
        token: widget.token,
      );
      await _cargar();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: AppColors.brandNavy,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Aviones',
                      style: AppTheme.headlineSm(color: Colors.white),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _aviones == null ? null : () => _formulario(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Registrar avión'),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
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
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
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
  const _FilaAvion({
    required this.avion,
    required this.onEditar,
    required this.onEstado,
  });

  final Avion avion;
  final VoidCallback onEditar;
  final VoidCallback onEstado;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
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
                Text(
                  avion.nombre,
                  style: AppTheme.labelLg(),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${avion.capacidad} asientos · ${avion.filas} filas de 3 + 3${avion.activo ? '' : ' · desactivado'}',
                  style: AppTheme.bodySm(color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Switch(value: avion.activo, onChanged: (_) => onEstado()),
          IconButton(
            tooltip: 'Editar avión',
            onPressed: onEditar,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
    );
  }
}

// Alta o edición de un avión. La capacidad usa las mismas reglas de cabina que el servidor.
class _FormularioAvion extends StatefulWidget {
  const _FormularioAvion({required this.token, this.avion});

  final String token;
  final Avion? avion;

  @override
  State<_FormularioAvion> createState() => _FormularioAvionState();
}

class _FormularioAvionState extends State<_FormularioAvion> {
  final _form = GlobalKey<FormState>();
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
        await AvionesService.editar(
          id: widget.avion!.id,
          nombre: nombre,
          capacidad: _capacidad,
          token: widget.token,
        );
      } else {
        await AvionesService.crear(
          nombre: nombre,
          capacidad: _capacidad,
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
    final opciones = [
      for (var n = minimoAsientos; n <= maximoAsientos; n += pasoAsientos) n,
    ];
    return AlertDialog(
      title: Text(_editando ? 'Editar avión' : 'Registrar avión'),
      content: Form(
        key: _form,
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nombre,
                maxLength: 60,
                decoration: const InputDecoration(
                  labelText: 'Nombre del avión',
                  hintText: 'Airbus A320-200',
                ),
                validator: validarNombreAvion,
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<int>(
                initialValue: _capacidad,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Capacidad (asientos)',
                  helperText:
                      '$_capacidad asientos · ${_capacidad ~/ pasoAsientos} filas de 3 + 3',
                ),
                items: [
                  for (final n in opciones)
                    DropdownMenuItem(value: n, child: Text('$n asientos')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _capacidad = v);
                },
              ),
              if (_editando) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Cambiar la capacidad solo afecta a los vuelos que se creen después; los vuelos existentes conservan su plano.',
                  style: AppTheme.bodySm(color: AppColors.onSurfaceVariant)
                      .copyWith(fontSize: 12),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Alerta(tipo: TipoAlerta.error, texto: _error!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enviando ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _enviando ? null : _guardar,
          child: Text(
            _enviando
                ? 'Guardando...'
                : (_editando ? 'Guardar cambios' : 'Registrar'),
          ),
        ),
      ],
    );
  }
}
