import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'roles.dart';

// Equivalente a sessionStorage["aerovuelo_token"] del cliente web.
// Vive solo en memoria: se pierde al cerrar la app, igual que sessionStorage al cerrar la pestaña.
class Session extends ChangeNotifier {
  String? _token;

  String? get token => _token;
  bool get activa => _token != null;

  // El correo sale del claim "sub" del JWT, como emailDeSesion() en app.js.
  String? get email => _claim('sub');

  // Rol según el claim "rol" del JWT (definición en core/roles.dart). El servidor valida la autorización real.
  Rol get rol {
    if (!activa) return Rol.invitado;
    return _claim('rol') == 'administrador' ? Rol.administrador : Rol.cliente;
  }

  String? _claim(String nombre) {
    final token = _token;
    if (token == null) return null;
    try {
      final partes = token.split('.');
      final payload = base64Url.normalize(partes[1]);
      final json = jsonDecode(utf8.decode(base64Url.decode(payload))) as Map<String, dynamic>;
      final valor = json[nombre];
      return valor is String && valor.isNotEmpty ? valor : null;
    } catch (_) {
      return null;
    }
  }

  void iniciar(String token) {
    _token = token;
    notifyListeners();
  }

  void cerrar() {
    _token = null;
    notifyListeners();
  }

  // Aviso de un solo uso para la siguiente pantalla (p. ej. "cuenta creada, inicia sesión").
  String? _aviso;

  void avisar(String texto) => _aviso = texto;

  // Devuelve el aviso pendiente y lo borra: se muestra una sola vez.
  String? tomarAviso() {
    final aviso = _aviso;
    _aviso = null;
    return aviso;
  }
}

final session = Session();
