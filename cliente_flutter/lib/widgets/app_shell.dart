import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/ruta.dart';
import '../core/roles.dart';
import '../core/services.dart';
import '../core/session.dart';
import '../theme/app_theme.dart';
import '../views/acceso_view.dart';
import '../views/consola_view.dart';
import '../views/mis_reservas_view.dart';
import '../views/vuelos_view.dart';

const _anchoNavegacion = 1280.0; // breakpoint xl de tailwind: la navegación aparece desde aquí
const _anchoSesion = 768.0; // breakpoint md: la pastilla de sesión aparece desde aquí

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  Ruta _ruta = Ruta.vuelos;

  @override
  void initState() {
    super.initState();
    session.addListener(_alCambiarSesion);
  }

  @override
  void dispose() {
    session.removeListener(_alCambiarSesion);
    super.dispose();
  }

  void _alCambiarSesion() {
    if (!session.activa) contadorReservas.value = null;
    if (mounted) setState(() {});
  }

  void _irA(Ruta ruta) => setState(() => _ruta = ruta);

  void _cerrarSesion() {
    final token = session.token;
    if (token != null) {
      // Revoca el token en el servidor; si no responde, la sesión local se cierra igual.
      AuthService.logout(token).catchError((_) {});
    }
    session.cerrar();
    _irA(Ruta.login);
  }

  Widget _vista() {
    return switch (_ruta) {
      Ruta.vuelos => VuelosView(onIrALogin: () => _irA(Ruta.login)),
      // Mis Reservas es solo para clientes: a un administrador lo llevamos a la vista de vuelos.
      Ruta.reservas => Permisos(session.rol).puedeReservar
          ? MisReservasView(onIrALogin: () => _irA(Ruta.login))
          : VuelosView(onIrALogin: () => _irA(Ruta.login)),
      Ruta.consola => const ConsolaView(),
      Ruta.login => AccesoView(
          vista: Ruta.login,
          onCambiar: _irA,
          onSesionIniciada: () {
            refrescarContador();
            _irA(Ruta.reservas);
          },
        ),
      Ruta.registro => AccesoView(
          vista: Ruta.registro,
          onCambiar: _irA,
          onSesionIniciada: () {
            refrescarContador();
            _irA(Ruta.reservas);
          },
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Cabecera(ruta: _ruta, onIrA: _irA, onCerrarSesion: _cerrarSesion),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    KeyedSubtree(key: ValueKey(_ruta), child: _vista()),
                    const _Pie(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cabecera extends StatelessWidget {
  const _Cabecera({required this.ruta, required this.onIrA, required this.onCerrarSesion});

  final Ruta ruta;
  final ValueChanged<Ruta> onIrA;
  final VoidCallback onCerrarSesion;

  static const _enlaces = [
    (Ruta.vuelos, 'Explorar Vuelos'),
    (Ruta.reservas, 'Mis Reservas'),
    (Ruta.consola, 'Consola API / JSON'),
  ];

  // "Mis Reservas" solo se muestra a clientes; el administrador no reserva.
  static List<(Ruta, String)> enlacesVisibles() => [
        for (final enlace in _enlaces)
          if (enlace.$1 != Ruta.reservas || Permisos(session.rol).puedeReservar) enlace,
      ];

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final margen = ancho >= 768 ? AppSpacing.margin : AppSpacing.marginMobile;
    final mostrarNav = ancho >= _anchoNavegacion;

    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: margen),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest.withValues(alpha: 0.9),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 1))],
      ),
      child: Row(
        children: [
          _Logo(onTap: () => onIrA(Ruta.vuelos)),
          const Spacer(),
          if (mostrarNav) _Navegacion(ruta: ruta, onIrA: onIrA),
          const Spacer(),
          if (ancho >= _anchoSesion) _PastillaSesion(),
          if (ancho >= _anchoSesion) ...[
            const SizedBox(width: AppSpacing.md),
            Container(width: 1, height: 24, color: AppColors.surfaceVariant),
            const SizedBox(width: AppSpacing.md),
          ],
          _Avatar(),
          const SizedBox(width: AppSpacing.sm),
          // En pantallas estrechas el botón de salir solo muestra el icono (evita desbordar la cabecera).
          if (session.activa && ancho >= 600)
            TextButton.icon(
              onPressed: onCerrarSesion,
              icon: const Icon(Icons.logout, size: 16),
              label: const Text('Cerrar sesión'),
              style: TextButton.styleFrom(foregroundColor: AppColors.onSurfaceVariant),
            )
          else if (session.activa)
            IconButton(
              tooltip: 'Cerrar sesión',
              onPressed: onCerrarSesion,
              icon: const Icon(Icons.logout, size: 20, color: AppColors.onSurfaceVariant),
            )
          else
            TextButton(
              onPressed: () => onIrA(Ruta.login),
              style: TextButton.styleFrom(foregroundColor: AppColors.onSurfaceVariant),
              child: Text('Ingresar', style: AppTheme.labelMd()),
            ),
          if (!mostrarNav)
            PopupMenuButton<Ruta>(
              icon: const Icon(Icons.menu),
              tooltip: 'Menú',
              onSelected: onIrA,
              itemBuilder: (_) => [for (final (ruta_, texto) in _Cabecera.enlacesVisibles()) PopupMenuItem(value: ruta_, child: Text(texto))],
            ),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.flight_takeoff, color: AppColors.onPrimary, size: 22),
          ),
          // En móvil solo queda el icono: el nombre y el subtítulo harían que la cabecera supere el ancho de la pantalla.
          if (MediaQuery.sizeOf(context).width >= 600) ...[
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('AeroVuelo', style: AppTheme.headlineSm().copyWith(height: 1, letterSpacing: -0.3)),
                Text(
                  'SKY BOOKING SYSTEM',
                  style: AppTheme.telemetry(size: 10, weight: FontWeight.w700, color: AppColors.secondary).copyWith(letterSpacing: 1),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Navegacion extends StatelessWidget {
  const _Navegacion({required this.ruta, required this.onIrA});

  final Ruta ruta;
  final ValueChanged<Ruta> onIrA;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (destino, texto) in _Cabecera.enlacesVisibles())
            _EnlaceRuta(
              texto: texto,
              activo: ruta == destino,
              insignia: destino == Ruta.reservas ? const _ContadorReservas() : null,
              onTap: () => onIrA(destino),
            ),
        ],
      ),
    );
  }
}

class _EnlaceRuta extends StatelessWidget {
  const _EnlaceRuta({required this.texto, required this.activo, required this.onTap, this.insignia});

  final String texto;
  final bool activo;
  final VoidCallback onTap;
  final Widget? insignia;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: activo ? AppColors.surfaceContainerHigh : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: activo ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 2)] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              texto,
              style: AppTheme.labelLg(color: activo ? AppColors.onSurface : AppColors.onSurfaceVariant)
                  .copyWith(fontWeight: activo ? FontWeight.w700 : FontWeight.w600),
            ),
            if (insignia != null) ...[const SizedBox(width: 6), insignia!],
          ],
        ),
      ),
    );
  }
}

class _ContadorReservas extends StatelessWidget {
  const _ContadorReservas();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: contadorReservas,
      builder: (_, confirmadas, _) {
        if (confirmadas == null) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: AppColors.secondaryContainer.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(999)),
          child: Text('$confirmadas', style: AppTheme.telemetry(size: 11, weight: FontWeight.w700, color: AppColors.onSecondaryContainer)),
        );
      },
    );
  }
}

class _PastillaSesion extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.surfaceVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.secondary, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(
            session.email ?? 'Sin sesión',
            style: AppTheme.telemetry(size: 12, color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
      child: const Icon(Icons.person, color: AppColors.onPrimary, size: 18),
    );
  }
}

class _Pie extends StatelessWidget {
  const _Pie();

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final margen = ancho >= 768 ? AppSpacing.margin : AppSpacing.marginMobile;
    return Container(
      width: double.infinity,
      color: AppColors.surfaceContainerLowest,
      padding: EdgeInsets.symmetric(horizontal: margen, vertical: AppSpacing.lg),
      child: Text(
        '© 2025 AeroVuelo Sky Booking System. Arquitectura Microservicios Distribuida.',
        style: AppTheme.bodySm(color: AppColors.onSurfaceVariant),
      ),
    );
  }
}
