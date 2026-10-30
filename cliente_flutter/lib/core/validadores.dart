import 'package:flutter/services.dart';

// Reglas de entrada del cliente. Espejo de shared/validacion.py: el servidor vuelve a validar todo,
// así que esto solo mejora la experiencia (no reemplaza la validación del backend).
//
// Reglas comunes:
// - Nada de espacios al inicio o al final, ni espacios repetidos.
// - Nada de emojis, símbolos ni caracteres de control.
// - Nombres: solo letras, espacio, apóstrofe y guion.
// - Nombre del pasajero (boletos): exactamente dos palabras, nombre y apellido.
// - Campos numéricos: solo dígitos (y un punto decimal en precios).

final _nombreRe = RegExp(r"^\p{L}+(?:[ '\-]\p{L}+)*$", unicode: true);
final _precioRe = RegExp(r'^[0-9]{1,6}(\.[0-9]{1,2})?$');
final _fechaRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

String? _bordesYEspacios(String valor, String campo) {
  if (valor != valor.trim()) return '$campo no puede empezar ni terminar con espacios.';
  if (valor.contains('  ')) return '$campo no puede tener espacios repetidos.';
  return null;
}

String? validarNombrePersona(String? valor, {String campo = 'El nombre'}) {
  final v = valor ?? '';
  final error = _bordesYEspacios(v, campo);
  if (error != null) return error;
  if (v.length < 2 || v.length > 100) return '$campo debe tener entre 2 y 100 caracteres.';
  if (!_nombreRe.hasMatch(v)) return '$campo solo puede tener letras, espacios, apóstrofes y guiones.';
  return null;
}

// Nombre del pasajero en un boleto: exactamente dos palabras (nombre y apellido).
String? validarNombrePasajero(String? valor) {
  const campo = 'El nombre del pasajero';
  final error = validarNombrePersona(valor, campo: campo);
  if (error != null) return error;
  if ((valor ?? '').split(' ').length != 2) return '$campo debe tener dos palabras: nombre y apellido.';
  return null;
}

String? validarEmail(String? valor) {
  final v = valor ?? '';
  if (v.contains(RegExp(r'\s'))) return 'El correo no puede tener espacios.';
  if (!_emailRe.hasMatch(v)) return 'Ingrese un correo electrónico válido.';
  return null;
}

String? validarPassword(String? valor) {
  final v = valor ?? '';
  if (v != v.trim()) return 'La contraseña no puede empezar ni terminar con espacios.';
  if (v.length < 8) return 'La contraseña debe tener al menos 8 caracteres.';
  if (v.length > 128) return 'La contraseña no puede superar 128 caracteres.';
  return null;
}

String? validarPrecio(String? valor) {
  final v = valor ?? '';
  if (!_precioRe.hasMatch(v)) return 'Ingrese un precio válido (solo números, hasta 2 decimales).';
  final n = double.parse(v);
  if (n <= 0 || n > 100000) return 'El precio debe estar entre 0.01 y 100 000.';
  return null;
}

String? validarFecha(String? valor) {
  final v = valor ?? '';
  if (!_fechaRe.hasMatch(v)) return 'Use el formato AAAA-MM-DD.';
  final fecha = DateTime.tryParse(v);
  if (fecha == null || fecha.toIso8601String().substring(0, 10) != v) return 'La fecha no existe.';
  return null;
}

// ----- Formatos de entrada: filtran lo que se puede escribir y conservan la posición del cursor -----

// Recorre el texto nuevo y deja solo los caracteres permitidos. El cursor se recalcula contando
// cuántos caracteres conservados quedaron antes de la posición donde estaba escribiendo la persona.
TextEditingValue _filtrar(
  TextEditingValue nuevo, {
  required bool Function(String caracter) permitido,
  bool espaciosSimples = false,
  bool sinEspacioInicial = false,
  bool unPunto = false,
  bool mayusculas = false,
  int? maximo,
}) {
  final texto = nuevo.text;
  final corte = nuevo.selection.isValid ? nuevo.selection.end : texto.length;
  final salida = <String>[];
  var cursor = -1;
  var punto = false;

  for (var i = 0; i < texto.length; i++) {
    if (i == corte) cursor = salida.length;
    var caracter = texto[i];
    if (!permitido(caracter)) continue;
    if (sinEspacioInicial && caracter == ' ' && salida.isEmpty) continue;
    if (espaciosSimples && caracter == ' ' && salida.isNotEmpty && salida.last == ' ') continue;
    if (unPunto && caracter == '.') {
      if (punto) continue;
      punto = true;
    }
    if (maximo != null && salida.length >= maximo) continue;
    if (mayusculas) caracter = caracter.toUpperCase();
    salida.add(caracter);
  }
  if (cursor == -1) cursor = salida.length;

  final resultado = salida.join();
  return TextEditingValue(text: resultado, selection: TextSelection.collapsed(offset: cursor));
}

// Nombres de personas: solo letras, espacio, apóstrofe y guion; sin espacios al inicio ni repetidos.
class NombrePersonaFormatter extends TextInputFormatter {
  static final _permitido = RegExp(r"^[\p{L}' \-]$", unicode: true);

  @override
  TextEditingValue formatEditUpdate(TextEditingValue anterior, TextEditingValue nuevo) {
    return _filtrar(
      nuevo,
      permitido: (c) => _permitido.hasMatch(c),
      espaciosSimples: true,
      sinEspacioInicial: true,
    );
  }
}

// Texto libre: letras, números, espacio y puntuación básica.
class TextoLibreFormatter extends TextInputFormatter {
  static final _permitido = RegExp(r"^[\p{L}\p{N} .,'\-()/&:;!?¿¡]$", unicode: true);

  @override
  TextEditingValue formatEditUpdate(TextEditingValue anterior, TextEditingValue nuevo) {
    return _filtrar(nuevo, permitido: (c) => _permitido.hasMatch(c), espaciosSimples: true, sinEspacioInicial: true);
  }
}

// Precios: dígitos y un solo punto decimal.
class PrecioFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue anterior, TextEditingValue nuevo) {
    return _filtrar(nuevo, permitido: (c) => RegExp(r'^[0-9.]$').hasMatch(c), unPunto: true);
  }
}

// Fechas AAAA-MM-DD: dígitos y guiones, máximo 10 caracteres.
class FechaFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue anterior, TextEditingValue nuevo) {
    return _filtrar(nuevo, permitido: (c) => RegExp(r'^[0-9\-]$').hasMatch(c), maximo: 10);
  }
}

// Contraseñas: sin espacios al inicio.
class SinEspacioInicialFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue anterior, TextEditingValue nuevo) {
    return _filtrar(nuevo, permitido: (_) => true, sinEspacioInicial: true);
  }
}
