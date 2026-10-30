import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum TipoAlerta { exito, error, aviso }

// Alerta con los estilos de mostrarAlerta() en cargador.js.
class Alerta extends StatelessWidget {
  const Alerta({super.key, required this.tipo, required this.texto});

  final TipoAlerta tipo;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final Color fondo;
    final Color borde;
    final Color colorTexto;
    final Color colorIcono;
    final IconData icono;

    switch (tipo) {
      case TipoAlerta.exito:
        fondo = AppColors.successBg;
        borde = AppColors.successBorder;
        colorTexto = AppColors.successText;
        colorIcono = AppColors.successIcon;
        icono = Icons.check_circle_outline;
      case TipoAlerta.error:
        fondo = AppColors.errorBg;
        borde = AppColors.errorBorder;
        colorTexto = AppColors.errorText;
        colorIcono = AppColors.errorIcon;
        icono = Icons.error_outline;
      case TipoAlerta.aviso:
        fondo = AppColors.warningBg;
        borde = AppColors.warningBorder;
        colorTexto = AppColors.warningText;
        colorIcono = AppColors.warningIcon;
        icono = Icons.warning_amber_outlined;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(12), border: Border.all(color: borde)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 20, color: colorIcono),
          const SizedBox(width: 12),
          Expanded(child: Text(texto, style: AppTheme.bodySm(color: colorTexto))),
        ],
      ),
    );
  }
}
