import 'package:flutter/material.dart';

import '../core/aeropuertos.dart';
import '../core/api_client.dart';
import '../core/models.dart';
import '../core/services.dart';
import '../core/validadores.dart';
import '../theme/app_theme.dart';

// Políticas de cabina (mismas reglas que el servicio S3): 18 a 180 asientos, filas de 3 + 3.
const minimoAsientos = 18;
const maximoAsientos = 180;
const pasoAsientos = 6;

bool _totalValido(int n) => n >= minimoAsientos && n <= maximoAsientos && n % pasoAsientos == 0;

// Alta o edición de vuelo para administradores. Crear: POST /api/admin/vuelos.
// Editar: PUT /api/admin/vuelos/{id}, solo si el vuelo no tiene reservas.
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
  late final TextEditingController _precio;
  late int _total;
  bool _enviando = false;
  String? _error;
  // Al crear: false deja el vuelo como borrador (valor por defecto).
  bool _publicar = false;

  bool get _editando => widget.vuelo != null;

  @override
  void initState() {
    super.initState();
    final v = widget.vuelo;
    // Solo se pueden elegir aeropuertos de la lista; si el vuelo guardado usa otro, se parte del primero.
    _origen = aeropuertos.containsKey(v?.origen) ? v!.origen : aeropuertos.keys.first;
    _destino = aeropuertos.containsKey(v?.destino) ? v!.destino : aeropuertos.keys.last;
    _fecha = TextEditingController(text: v?.fecha ?? '');
    _precio = TextEditingController(text: v == null ? '' : v.precio.toStringAsFixed(2));
    // Un vuelo puede tener un total que ya no es válido (por ejemplo 0 asientos): se parte de uno válido.
    final total = v?.totalAsientos;
    _total = total != null && _totalValido(total) ? total : minimoAsientos;
  }

  @override
  void dispose() {
    _fecha.dispose();
    _precio.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    final fecha = _fecha.text.trim();
    final precio = double.parse(_precio.text.trim());
    try {
      if (_editando) {
        await GestionVuelosService.editar(
          id: widget.vuelo!.id,
          origen: _origen,
          destino: _destino,
          fecha: fecha,
          precio: precio,
          totalAsientos: _total,
          token: widget.token,
        );
      } else {
        await AdminService.crearVuelo(
          activo: _publicar,
          origen: _origen,
          destino: _destino,
          fecha: fecha,
          precio: precio,
          totalAsientos: _total,
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
    final opciones = [for (var n = minimoAsientos; n <= maximoAsientos; n += pasoAsientos) n];

    return AlertDialog(
      title: Text(_editando ? 'Editar vuelo #${widget.vuelo!.id}' : 'Crear vuelo', style: AppTheme.headlineSm()),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _origen,
                        decoration: const InputDecoration(labelText: 'Origen'),
                        items: [
                          for (final e in aeropuertos.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _origen = v);
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _destino,
                        decoration: const InputDecoration(labelText: 'Destino'),
                        items: [
                          for (final e in aeropuertos.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
                        ],
                        validator: (v) => v == _origen ? 'Debe ser distinto del origen' : null,
                        onChanged: (v) {
                          if (v != null) setState(() => _destino = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _fecha,
                  inputFormatters: [FechaFormatter()],
                  keyboardType: TextInputType.datetime,
                  decoration: const InputDecoration(labelText: 'Fecha (AAAA-MM-DD)'),
                  validator: validarFecha,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _precio,
                  inputFormatters: [PrecioFormatter()],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Precio por pasajero (USD)'),
                  validator: validarPrecio,
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<int>(
                  initialValue: _total,
                  decoration: InputDecoration(
                    labelText: 'Total de asientos (filas de 3 + 3)',
                    helperText: _editando && !_totalValido(widget.vuelo!.totalAsientos)
                        ? 'El vuelo tenía ${widget.vuelo!.totalAsientos} asientos (no válido): elija un total.'
                        : null,
                  ),
                  items: [
                    for (final n in opciones) DropdownMenuItem(value: n, child: Text('$n asientos (${n ~/ 6} filas)')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _total = v);
                  },
                ),
                if (!_editando)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _publicar,
                    onChanged: (v) => setState(() => _publicar = v),
                    title: const Text('Publicar al crear'),
                    subtitle: const Text('Apagado: el vuelo queda como borrador y nadie lo verá hasta publicarlo.'),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(_error!, style: AppTheme.bodySm(color: AppColors.errorText)),
                ],
              ],
            ),
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
          child: Text(_enviando ? 'Guardando...' : (_editando ? 'Guardar cambios' : 'Crear vuelo')),
        ),
      ],
    );
  }
}
