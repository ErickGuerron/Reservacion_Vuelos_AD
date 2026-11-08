import 'package:flutter/material.dart';

import '../core/ruta.dart';
import '../theme/app_theme.dart';
import 'acceso_forms.dart';

// Login y registro comparten la tarjeta: panel de marca, pestañas y el formulario de la ruta.
class AccesoView extends StatelessWidget {
  const AccesoView({super.key, required this.vista, required this.onCambiar, required this.onSesionIniciada});

  final Ruta vista;
  final ValueChanged<Ruta> onCambiar;
  final VoidCallback onSesionIniciada;

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final lateral = ancho >= 1024; // lg: hero y formulario lado a lado
    final margen = ancho >= 768 ? 48.0 : 16.0;

    final contenido = Container(
      padding: EdgeInsets.symmetric(horizontal: lateral ? 64 : 32, vertical: 48),
      color: AppColors.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Pestanas(vista: vista, onCambiar: onCambiar),
                  if (vista == Ruta.login)
                    LoginForm(onSesionIniciada: onSesionIniciada)
                  else
                    RegistroForm(
                      onSesionIniciada: onSesionIniciada,
                      onIrALogin: () => onCambiar(Ruta.login),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: Text(
                'Al continuar, aceptas las Condiciones de Transporte y la Política de Privacidad de AeroVuelo.',
                textAlign: TextAlign.center,
                style: AppTheme.labelSm(color: AppColors.slate400),
              ),
            ),
          ),
        ],
      ),
    );

    // SingleChildScrollView evita el desbordamiento (franja amarilla/negra de debug)
    // cuando el formulario es más alto que el espacio disponible.
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: margen, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1280),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [BoxShadow(color: const Color(0xFF0B192C).withValues(alpha: 0.08), blurRadius: 50, offset: const Offset(0, 20))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            // En escritorio no se usa IntrinsicHeight: sus mediciones intrínsecas de texto
          // con salto de línea dejan la altura por debajo del alto real y provocan el
          // desbordamiento. El fondo de dos mitades se pinta con Stack y cubre toda la altura.
          child: lateral
              ? Stack(
                  children: [
                    Positioned.fill(
                      child: Row(
                        children: [
                          Expanded(flex: 5, child: ColoredBox(color: AppColors.brandNavy)),
                          Expanded(flex: 7, child: ColoredBox(color: AppColors.surfaceContainerLowest)),
                        ],
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Expanded(flex: 5, child: PanelHero()),
                        Expanded(flex: 7, child: contenido),
                      ],
                    ),
                  ],
                )
              : Column(children: [const PanelHero(), contenido]),
          ),
        ),
      ),
    );
  }
}

class _Pestanas extends StatelessWidget {
  const _Pestanas({required this.vista, required this.onCambiar});

  final Ruta vista;
  final ValueChanged<Ruta> onCambiar;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 32),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: const Color(0xFFF1F5F9).withValues(alpha: 0.9), borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          _Pestana(texto: 'Iniciar Sesión', icono: Icons.login, activa: vista == Ruta.login, onTap: () => onCambiar(Ruta.login)),
          _Pestana(texto: 'Crear Cuenta', icono: Icons.person_add_alt, activa: vista == Ruta.registro, onTap: () => onCambiar(Ruta.registro)),
        ],
      ),
    );
  }
}

class _Pestana extends StatelessWidget {
  const _Pestana({required this.texto, required this.icono, required this.activa, required this.onTap});

  final String texto;
  final IconData icono;
  final bool activa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: activa ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: activa ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 2, offset: const Offset(0, 1))] : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icono, size: 18, color: activa ? AppColors.slate900 : AppColors.slate600),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  texto,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: AppTheme.bodySm(color: activa ? AppColors.slate900 : AppColors.slate600)
                      .copyWith(fontWeight: activa ? FontWeight.w600 : FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Panel izquierdo de marca (panel-hero.html): fondo azul noche, badge, titular y tarjeta de vuelo.
class PanelHero extends StatelessWidget {
  const PanelHero({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.brandNavy,
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF0EA5E9), Color(0xFF2563EB)]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.flight_takeoff, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AeroVuelo', style: AppTheme.headlineSm(color: Colors.white).copyWith(fontWeight: FontWeight.w800, height: 1)),
                    Text('Portal Global de Pasajeros', style: AppTheme.labelSm(color: AppColors.slate400)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF082F49).withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF075985).withValues(alpha: 0.4)),
            ),
            child: Text('EXPERIENCIA PREMIUM', style: AppTheme.telemetry(size: 12, weight: FontWeight.w600, color: AppColors.sky400)),
          ),
          const SizedBox(height: 12),
          Text(
            'Vuela sin fricciones hacia cada destino.',
            style: AppTheme.headlineLg(color: Colors.white).copyWith(fontWeight: FontWeight.w800, height: 1.15),
          ),
          const SizedBox(height: 12),
          Text(
            'Accede a tus reservas, gestiona itinerarios de conexión directa a UIO, GYE y MAD, y obtén tu pase de abordar en tiempo real.',
            style: AppTheme.bodySm(color: AppColors.slate300),
          ),
          const SizedBox(height: 32),
          const _TarjetaVuelo(),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.only(top: 16),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1)))),
            child: Row(
              children: [
                const Icon(Icons.verified_user_outlined, size: 16, color: AppColors.sky400),
                const SizedBox(width: 8),
                Expanded(child: Text('Certificación IATA & Seguridad TLS 1.3', style: AppTheme.labelSm(color: AppColors.slate400))),
                Text('2025', style: AppTheme.telemetry(size: 11, color: AppColors.slate400)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaVuelo extends StatelessWidget {
  const _TarjetaVuelo();

  @override
  Widget build(BuildContext context) {
    Widget bloque(String etiqueta, String codigo, String ciudad, CrossAxisAlignment alineacion) {
      return Column(
        crossAxisAlignment: alineacion,
        children: [
          Text(etiqueta, style: AppTheme.telemetry(size: 11, color: AppColors.slate300)),
          Text(codigo, style: AppTheme.headlineMd(color: Colors.white).copyWith(fontWeight: FontWeight.w900)),
          Text(ciudad, style: AppTheme.labelSm(color: AppColors.slate300)),
        ],
      );
    }

    Widget datoCaja(String etiqueta, String valor, {bool verde = false}) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: verde ? const Color(0xFF10B981).withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: verde ? Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.2)) : null,
          ),
          child: Column(
            children: [
              Text(etiqueta, style: AppTheme.telemetry(size: 10, color: verde ? const Color(0xFF34D399) : AppColors.slate400)),
              const SizedBox(height: 2),
              Text(valor, style: AppTheme.bodySm(color: verde ? const Color(0xFF6EE7B7) : Colors.white).copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)))),
            child: Row(
              children: [
                bloque('Origen', 'UIO', 'Quito', CrossAxisAlignment.start),
                Expanded(
                  child: Column(
                    children: [
                      Text('AV-502', style: AppTheme.telemetry(size: 11, weight: FontWeight.w600, color: AppColors.sky300)),
                      const SizedBox(height: 4),
                      Container(
                        height: 2,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(colors: [Colors.transparent, AppColors.sky400, Colors.transparent]),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('Directo · 10h 30m', style: AppTheme.labelSm(color: AppColors.slate400)),
                    ],
                  ),
                ),
                bloque('Destino', 'MAD', 'Madrid', CrossAxisAlignment.end),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              datoCaja('ASIENTO', '04A'),
              const SizedBox(width: 12),
              datoCaja('EMBARQUE', 'Zona 1'),
              const SizedBox(width: 12),
              datoCaja('ESTADO', 'A tiempo', verde: true),
            ],
          ),
        ],
      ),
    );
  }
}
