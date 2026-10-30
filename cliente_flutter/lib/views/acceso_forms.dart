import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../core/services.dart';
import '../core/session.dart';
import '../core/validadores.dart';
import '../theme/app_theme.dart';
import '../widgets/alerta.dart';

// Campo con el estilo de .campo de login.html y registro.html.
class CampoAcceso extends StatelessWidget {
  const CampoAcceso({
    super.key,
    required this.controller,
    required this.icono,
    required this.hint,
    this.obscure = false,
    this.keyboardType,
    this.sufijo,
    this.onChanged,
    this.formatos,
  });

  final TextEditingController controller;
  final IconData icono;
  final String hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final Widget? sufijo;
  final ValueChanged<String>? onChanged;
  // Filtros de lo que se puede escribir (por ejemplo, sin espacios o solo letras).
  final List<TextInputFormatter>? formatos;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.slate300),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(icono, size: 20, color: AppColors.slate400),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              keyboardType: keyboardType,
              onChanged: onChanged,
              inputFormatters: formatos,
              style: AppTheme.bodySm(color: AppColors.slate900),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: AppTheme.bodySm(color: AppColors.slate400),
                border: InputBorder.none,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          ?sufijo,
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(texto, style: AppTheme.bodySm(color: AppColors.slate700).copyWith(fontWeight: FontWeight.w600));
  }
}

class _BotonPrincipal extends StatelessWidget {
  const _BotonPrincipal({required this.texto, required this.icono, required this.onPressed});

  final String texto;
  final IconData icono;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icono, size: 20),
        label: Text(texto, style: AppTheme.bodySm(color: Colors.white).copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.3)),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brandNavy,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.brandNavy.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.titulo, required this.subtitulo});
  final String titulo;
  final String subtitulo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: AppTheme.headlineMd(color: AppColors.slate900).copyWith(fontSize: 24)),
        const SizedBox(height: 4),
        Text(subtitulo, style: AppTheme.bodySm(color: AppColors.slate500)),
      ],
    );
  }
}

// Formulario de inicio de sesión: POST /api/auth/login (S2).
class LoginForm extends StatefulWidget {
  const LoginForm({super.key, required this.onSesionIniciada});

  final VoidCallback onSesionIniciada;

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _mostrarClave = false;
  bool _enviando = false;
  ({TipoAlerta tipo, String texto})? _alerta;


  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final email = _email.text.trim();
    final password = _password.text;

    final errorEmail = validarEmail(email);
    if (errorEmail != null) {
      setState(() => _alerta = (tipo: TipoAlerta.error, texto: errorEmail));
      return;
    }
    if (password.isEmpty) {
      setState(() => _alerta = (tipo: TipoAlerta.error, texto: 'Ingresa tu contraseña.'));
      return;
    }

    setState(() => _enviando = true);
    try {
      final token = await AuthService.login(email, password);
      session.iniciar(token);
      if (!mounted) return;
      setState(() => _alerta = (tipo: TipoAlerta.exito, texto: '¡Sesión iniciada con éxito! Sincronizando tus reservas de vuelo...'));
      widget.onSesionIniciada();
    } on ConexionFallida {
      if (!mounted) return;
      setState(() => _alerta = (tipo: TipoAlerta.error, texto: 'No se pudo conectar con el servicio de autenticación. ¿Está levantado?'));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _alerta = (tipo: TipoAlerta.error, texto: e.mensaje));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Encabezado(titulo: 'Bienvenido de nuevo', subtitulo: 'Ingresa tus credenciales para acceder a tus itinerarios.'),
        const SizedBox(height: 24),
        if (_alerta != null) ...[Alerta(tipo: _alerta!.tipo, texto: _alerta!.texto), const SizedBox(height: 24)],
        const _Etiqueta('Correo Electrónico'),
        const SizedBox(height: 6),
        CampoAcceso(
          controller: _email,
          icono: Icons.mail_outline,
          hint: 'pasajero@aerovuelo.com',
          keyboardType: TextInputType.emailAddress,
          formatos: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
        ),
        const SizedBox(height: 20),
        const _Etiqueta('Contraseña'),
        const SizedBox(height: 6),
        CampoAcceso(
          controller: _password,
          icono: Icons.lock_outline,
          hint: '••••••••••••',
          obscure: !_mostrarClave,
          formatos: [SinEspacioInicialFormatter()],
          sufijo: IconButton(
            tooltip: 'Mostrar u ocultar contraseña',
            icon: Icon(_mostrarClave ? Icons.visibility_off : Icons.visibility, size: 20, color: AppColors.slate400),
            onPressed: () => setState(() => _mostrarClave = !_mostrarClave),
          ),
        ),
        const SizedBox(height: 24),
        _BotonPrincipal(texto: 'Ingresar al Sistema', icono: Icons.flight_takeoff, onPressed: _enviando ? null : _enviar),
      ],
    );
  }
}

// Formulario de registro: POST /api/usuarios (S1), con medidor de seguridad de la contraseña.
class RegistroForm extends StatefulWidget {
  const RegistroForm({super.key});

  @override
  State<RegistroForm> createState() => _RegistroFormState();
}

class _RegistroFormState extends State<RegistroForm> {
  static const _minimoClave = 8; // igual que el servicio de usuarios

  final _nombre = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _mostrarClave = false;
  bool _enviando = false;
  ({TipoAlerta tipo, String texto})? _alerta;
  String _clave = '';


  @override
  void dispose() {
    _nombre.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  // Igual que puntuarClave() de registro.js.
  int _puntuar(String clave) {
    var puntos = 0;
    if (clave.length >= _minimoClave) puntos++;
    if (RegExp(r'[A-Z]').hasMatch(clave)) puntos++;
    if (RegExp(r'[0-9]').hasMatch(clave)) puntos++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(clave)) puntos++;
    return puntos;
  }

  // Niveles según puntos (0 a 4): texto, color y cuántas barras se pintan.
  ({String texto, Color color, int barras}) _nivel(int puntos) {
    if (puntos == 0) return (texto: 'Baja', color: AppColors.slate500, barras: 0);
    if (puntos == 1 || puntos == 2) return (texto: 'Moderada', color: const Color(0xFFD97706), barras: 2);
    if (puntos == 3) return (texto: 'Buena', color: const Color(0xFF0284C7), barras: 3);
    return (texto: 'Excelente', color: const Color(0xFF059669), barras: 4);
  }

  Future<void> _enviar() async {
    final nombre = _nombre.text.trim();
    final email = _email.text.trim();
    final password = _password.text;

    final errorNombre = validarNombrePersona(nombre, campo: 'El nombre');
    if (errorNombre != null) {
      setState(() => _alerta = (tipo: TipoAlerta.error, texto: errorNombre));
      return;
    }
    final errorEmail = validarEmail(email);
    if (errorEmail != null) {
      setState(() => _alerta = (tipo: TipoAlerta.error, texto: errorEmail));
      return;
    }
    final errorClave = validarPassword(password);
    if (errorClave != null) {
      setState(() => _alerta = (tipo: TipoAlerta.aviso, texto: errorClave));
      return;
    }

    setState(() => _enviando = true);
    try {
      await UsuariosService.registrar(nombre: nombre, email: email, password: password);
      if (!mounted) return;
      setState(() {
        _alerta = (tipo: TipoAlerta.exito, texto: '¡Registro completado! Bienvenido a bordo, $nombre. Tu cuenta ya está activa.');
        _nombre.clear();
        _email.clear();
        _password.clear();
        _clave = '';
      });
    } on ConexionFallida {
      if (!mounted) return;
      setState(() => _alerta = (tipo: TipoAlerta.error, texto: 'No se pudo conectar con el servicio de usuarios. ¿Está levantado?'));
    } on ApiException catch (e) {
      if (!mounted) return;
      // 400 es un aviso de validación del servicio; el resto, un error (igual que registro.js).
      final tipo = e.status == 400 ? TipoAlerta.aviso : TipoAlerta.error;
      setState(() => _alerta = (tipo: tipo, texto: e.mensaje));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final puntos = _puntuar(_clave);
    final nivel = _nivel(puntos);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Encabezado(titulo: 'Crea tu cuenta de pasajero', subtitulo: 'Regístrate en pocos segundos para reservar y acumular beneficios.'),
        const SizedBox(height: 24),
        if (_alerta != null) ...[Alerta(tipo: _alerta!.tipo, texto: _alerta!.texto), const SizedBox(height: 24)],
        const _Etiqueta('Nombre y Apellido'),
        const SizedBox(height: 6),
        CampoAcceso(
          controller: _nombre,
          icono: Icons.person_outline,
          hint: 'Ej. Roberto Morales Sánchez',
          formatos: [NombrePersonaFormatter()],
        ),
        const SizedBox(height: 20),
        const _Etiqueta('Correo Electrónico'),
        const SizedBox(height: 6),
        CampoAcceso(
          controller: _email,
          icono: Icons.mail_outline,
          hint: 'pasajero@aerovuelo.com',
          keyboardType: TextInputType.emailAddress,
          formatos: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
        ),
        const SizedBox(height: 20),
        const _Etiqueta('Contraseña'),
        const SizedBox(height: 6),
        CampoAcceso(
          controller: _password,
          icono: Icons.lock_outline,
          hint: '••••••••••••',
          obscure: !_mostrarClave,
          formatos: [SinEspacioInicialFormatter()],
          onChanged: (valor) => setState(() => _clave = valor),
          sufijo: IconButton(
            tooltip: 'Mostrar u ocultar contraseña',
            icon: Icon(_mostrarClave ? Icons.visibility_off : Icons.visibility, size: 20, color: AppColors.slate400),
            onPressed: () => setState(() => _mostrarClave = !_mostrarClave),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text('Seguridad de la contraseña:', style: AppTheme.labelSm(color: AppColors.slate500).copyWith(fontSize: 12)),
            const Spacer(),
            Text(nivel.texto, style: AppTheme.telemetry(size: 12, weight: FontWeight.w600, color: nivel.color)),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < 4; i++) ...[
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 6,
                  decoration: BoxDecoration(
                    color: i < nivel.barras ? nivel.color : AppColors.slate300.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              if (i < 3) const SizedBox(width: 6),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Utiliza al menos 8 caracteres con letras mayúsculas, números o símbolos.',
          style: AppTheme.labelSm(color: AppColors.slate500),
        ),
        const SizedBox(height: 24),
        _BotonPrincipal(texto: 'Completar Registro', icono: Icons.how_to_reg, onPressed: _enviando ? null : _enviar),
      ],
    );
  }
}
