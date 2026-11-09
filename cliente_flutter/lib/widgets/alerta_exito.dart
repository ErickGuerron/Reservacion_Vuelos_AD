import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

// Alerta de éxito tipo SweetAlert: icono de confirmación, título, mensaje y un botón para aceptar.
// No se cierra tocando fuera: la persona debe pulsar "Aceptar". Vuelve cuando se acepta.
Future<void> mostrarAlertaExito(BuildContext context, {required String titulo, required String mensaje}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogo) => Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.successBg,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.successBorder, width: 2),
                ),
                child: const Icon(Icons.check_circle, size: 44, color: AppColors.successIcon),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(titulo, textAlign: TextAlign.center, style: AppTheme.headlineSm()),
              const SizedBox(height: AppSpacing.sm),
              Text(mensaje, textAlign: TextAlign.center, style: AppTheme.bodyMd(color: AppColors.onSurfaceVariant)),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: () => Navigator.of(dialogo).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.successIcon,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(160, 44),
                ),
                child: Text('Aceptar', style: AppTheme.labelLg(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
