import 'package:flutter/material.dart';

import '../core/models.dart';

// Botones de administración que aparecen dentro de cada vuelo (solo para administradores).
// Editar requiere que el vuelo no tenga reservas; publicar o despublicar siempre está disponible.
class AccionesAdminVuelo extends StatelessWidget {
  const AccionesAdminVuelo({super.key, required this.gestion, required this.onEditar, required this.onEstado});

  final VueloAdmin gestion;
  final VoidCallback onEditar;
  final VoidCallback onEstado;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Tooltip(
          message: gestion.editable ? 'Editar el vuelo' : 'No se puede editar: el vuelo tiene reservas',
          child: OutlinedButton(
            onPressed: gestion.editable ? onEditar : null,
            child: const Text('Editar'),
          ),
        ),
        FilledButton.tonal(
          onPressed: onEstado,
          child: Text(gestion.activo ? 'Despublicar' : 'Publicar'),
        ),
      ],
    );
  }
}
