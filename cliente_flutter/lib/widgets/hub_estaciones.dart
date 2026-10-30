import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

// Galería de estaciones (hub-estaciones.html). Es solo visual, igual que en la versión web.
class HubEstaciones extends StatelessWidget {
  const HubEstaciones({super.key});

  static const _estaciones = [
    (
      codigo: 'UIO · Quito',
      subtitulo: 'Ecuador · 2,400 m',
      imagen:
          'https://lh3.googleusercontent.com/aida-public/AB6AXuB06D3Y-JGYK-WY1PfeOR5iVhxK_hCHrzjC3yLnwYyhMIB30noF_XqSPDp9tXAD-DHBCkPKAmJHqZnjFTm3Sl6KCfPQKp-YcQgECDtJpY_88zV2vtcwXlLTuBQfcV-zHn0_Yiptrtc_HgpFjdB536KWA8ns7oZvLFpgb0J2zdu4UcrcefYYb0dqwWLPKV2qqoqfTvD-t2_Peip820WM9B73WbTLO9BhlbHIW8gBV4tPNTvk6p8VgXtj9A',
      descripcion: 'Terminal del aeropuerto de Quito con los Andes al fondo',
    ),
    (
      codigo: 'GYE · Guayaquil',
      subtitulo: 'Ecuador · Nivel del mar',
      imagen:
          'https://lh3.googleusercontent.com/aida-public/AB6AXuBIFqDSLisXlMPp7tEvsgajrMxRH-_MtbFKKwkmwf9O-ECLG1tlZt4fkN3NbZ2Oza8WoQgJNyuhNd-Q-jFFBVhJUTkFuaZOpa9ptwVkIr6veVrp0FnMnEe5Zh0JEFNECfgfvR6DWf9J3Agsb9D5tnyfP0P1e-2AGl--WkUK1BgCfhKkKCIEQEBSkOSaHHamKw2ROHqK_sXh20kt2DztUIJldfuIgwgs1MHGVSuZnYsw1jiAGx7YRjph0Q',
      descripcion: 'Pista del aeropuerto de Guayaquil al atardecer',
    ),
    (
      codigo: 'MAD · Madrid',
      subtitulo: 'España · Terminal 4S',
      imagen:
          'https://lh3.googleusercontent.com/aida-public/AB6AXuCg73BG1E9Fs16CsBsJSC8x57lSS1KZ_7QhtZPJFGUJ-djDBVQ2L7IRat0P4kXvuEiOm9n2snQpVhUyb_VFo7ulG1gBiI_HSsSzyF8o-LIJ9WLmtFRMd19Ldcrv1nVwKFBCdv1TTv36cMdEmAJtKYe0glEAUblayjO4rp1-RwSGYZnEttZQ_z2UFhpZNe8GSoTSBnkfrRbD-cOTp-flewwVua8OrDYi9n4NqDjctNiOJY-BwtSuZIXAaA',
      descripcion: 'Terminal del aeropuerto de Madrid-Barajas',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final enFila = ancho >= 768; // md: tres columnas; en móvil, una tarjeta por fila

    final tarjetas = [
      for (final e in _estaciones)
        SizedBox(
          height: 224, // h-56 del diseño original
          child: _Estacion(codigo: e.codigo, subtitulo: e.subtitulo, imagen: e.imagen, descripcion: e.descripcion),
        ),
    ];

    return Container(
      width: double.infinity,
      color: AppColors.surfaceContainerLow,
      padding: EdgeInsets.symmetric(horizontal: ancho >= 768 ? AppSpacing.margin : AppSpacing.marginMobile, vertical: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'HUB · ESTACIONES CONECTADAS',
            style: AppTheme.telemetry(size: 12, weight: FontWeight.w700, color: AppColors.secondary).copyWith(letterSpacing: 1),
          ),
          Text('Centros de operación aeronáutica', style: AppTheme.headlineMd()),
          const SizedBox(height: 4),
          Text('Estaciones de referencia de la red AeroVuelo.', style: AppTheme.bodySm(color: AppColors.onSurfaceVariant)),
          const SizedBox(height: AppSpacing.lg),
          if (enFila)
            Row(
              children: [
                for (var i = 0; i < tarjetas.length; i++) ...[
                  Expanded(child: tarjetas[i]),
                  if (i < tarjetas.length - 1) const SizedBox(width: AppSpacing.md),
                ],
              ],
            )
          else
            Column(
              children: [
                for (var i = 0; i < tarjetas.length; i++) ...[
                  tarjetas[i],
                  if (i < tarjetas.length - 1) const SizedBox(height: AppSpacing.md),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _Estacion extends StatelessWidget {
  const _Estacion({required this.codigo, required this.subtitulo, required this.imagen, required this.descripcion});

  final String codigo;
  final String subtitulo;
  final String imagen;
  final String descripcion;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            imagen,
            fit: BoxFit.cover,
            semanticLabel: descripcion,
            errorBuilder: (_, _, _) => Container(color: AppColors.primaryContainer),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xCC000000)]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(subtitulo, style: AppTheme.telemetry(size: 10, color: AppColors.secondaryContainer)),
                Text(codigo, style: AppTheme.headlineSm(color: Colors.white).copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
