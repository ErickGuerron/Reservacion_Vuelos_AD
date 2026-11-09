import 'package:flutter/material.dart';

import '../core/services.dart';
import '../theme/app_theme.dart';
import '../views/mapa_asientos.dart';

// Piezas compartidas por los formularios de vuelo y de avión: mismo modelo, mismo tamaño y misma
// vista previa del plano. La cabina es igual en ambos: filas de 3 + 3, de 18 a 180 asientos.

// Políticas de cabina (mismas reglas que el servicio S6): 18 a 180 asientos, filas de 3 + 3.
const minimoAsientos = 18;
const maximoAsientos = 180;
const pasoAsientos = 6;

// Columnas de izquierda a derecha como las ve el pasajero desde el pasillo.
const _columnasPrevia = ['F', 'E', 'D', 'C', 'B', 'A'];

// Todos los asientos libres de un avión de [total] asientos: filas de 3 + 3.
List<Asiento> asientosPrevia(int total) => asientosDesde([
      for (var fila = 1; fila <= total ~/ pasoAsientos; fila++)
        for (final c in _columnasPrevia) AsientoRemoto(codigo: '$fila$c', fila: fila, columna: c, ocupado: false),
    ]);

// Cabecera oscura del formulario: icono, título y endpoint que usa.
class CabeceraFormulario extends StatelessWidget {
  const CabeceraFormulario({
    super.key,
    required this.titulo,
    required this.endpoint,
    required this.onCerrar,
    this.icono = Icons.flight,
  });

  final String titulo;
  final String endpoint;
  final VoidCallback? onCerrar;
  final IconData icono;

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
            child: Icon(icono, color: Colors.white),
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
class SeccionFormulario extends StatelessWidget {
  const SeccionFormulario({super.key, required this.titulo, required this.hijo});

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
class VistaPreviaAvion extends StatelessWidget {
  const VistaPreviaAvion({super.key, required this.total, required this.asientos, required this.controlador});

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
            DatoChip('$total asientos'),
            DatoChip('$filas filas'),
            const DatoChip('3 + 3'),
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

// Etiqueta redondeada con un dato del avión (asientos, filas, disposición).
class DatoChip extends StatelessWidget {
  const DatoChip(this.texto, {super.key});

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
