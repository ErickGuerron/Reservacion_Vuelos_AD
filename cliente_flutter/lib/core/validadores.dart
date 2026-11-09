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

// Texto de un avión: letras, números, espacio y puntuación básica (espejo de shared/validacion.validar_texto).
final _textoAvionRe = RegExp(r"""^[\p{L}\p{N} .,'"\-()/&:;!?¿¡]+$""", unicode: true);

// Nombre del avión (S6): de 2 a 60 caracteres, sin espacios al inicio o al final ni repetidos.
String? validarNombreAvion(String? valor) {
  final v = valor ?? '';
  final error = _bordesYEspacios(v, 'El nombre del avión');
  if (error != null) return error;
  if (v.length < 2 || v.length > 60) return 'El nombre del avión debe tener entre 2 y 60 caracteres.';
  if (v.toLowerCase().contains('ñ')) return 'El nombre del avión no puede contener la letra ñ.';
  if (!_textoAvionRe.hasMatch(v)) return 'El nombre del avión solo puede tener letras, números, espacios y signos básicos.';
  return null;
}

// Filtra lo que se escribe en el nombre del avión: sin ñ, sin emojis ni símbolos, máximo 60 caracteres.
// Lo que no cumple no aparece, así que el usuario no llega a escribirlo.
class NombreAvionFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue anterior, TextEditingValue nuevo) {
    return _filtrar(
      nuevo,
      permitido: (c) => c != 'ñ' && c != 'Ñ' && _textoAvionRe.hasMatch(c),
      espaciosSimples: true,
      sinEspacioInicial: true,
      maximo: 60,
    );
  }
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

// Un vuelo nuevo o editado no puede salir hoy ni en el pasado: la primera fecha válida es mañana.
String? validarFechaVuelo(String? valor) {
  final error = validarFecha(valor);
  if (error != null) return error;
  final fecha = DateTime.parse((valor ?? '').trim());
  final hoy = DateTime.now();
  final manana = DateTime(hoy.year, hoy.month, hoy.day + 1);
  if (fecha.isBefore(manana)) return 'El vuelo debe programarse desde mañana en adelante.';
  return null;
}

// Hora de salida en formato HH:MM de 24 horas.
final _horaRe = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

String? validarHora(String? valor) {
  final v = (valor ?? '').trim();
  if (!_horaRe.hasMatch(v)) return 'Use el formato HH:MM (24 horas).';
  return null;
}

// ----- Documento del pasajero (espejo de shared/validacion.py) -----

final _pasaporteRe = RegExp(r'^[A-Z0-9]{6,12}$');

// Cédula ecuatoriana: 10 dígitos, provincia 01-24 o 30, tercer dígito menor que 6 y dígito verificador (módulo 10).
bool cedulaEcuatorianaValida(String valor) {
  if (!RegExp(r'^[0-9]{10}$').hasMatch(valor)) return false;
  final provincia = int.parse(valor.substring(0, 2));
  if (!((provincia >= 1 && provincia <= 24) || provincia == 30)) return false;
  if (int.parse(valor[2]) > 5) return false;
  var suma = 0;
  for (var i = 0; i < 9; i++) {
    var parcial = int.parse(valor[i]) * (i.isEven ? 2 : 1);
    if (parcial > 9) parcial -= 9;
    suma += parcial;
  }
  return (10 - suma % 10) % 10 == int.parse(valor[9]);
}

String? validarCedula(String? valor) {
  final v = valor ?? '';
  if (v.isEmpty) return 'Ingrese el número de cédula.';
  if (!RegExp(r'^[0-9]+$').hasMatch(v)) return 'La cédula solo tiene dígitos.';
  if (v.length < 10) return 'Faltan ${10 - v.length} dígitos.';
  if (!cedulaEcuatorianaValida(v)) return 'Cédula no válida: revise los dígitos.';
  return null;
}

String? validarPasaporte(String? valor) {
  final v = (valor ?? '').toUpperCase();
  if (v.isEmpty) return 'Ingrese el número de pasaporte.';
  if (!_pasaporteRe.hasMatch(v)) return 'El pasaporte debe tener entre 6 y 12 letras o dígitos, sin espacios.';
  return null;
}

// tipo: 'cedula' o 'pasaporte'.
String? validarDocumento(String tipo, String? valor) => tipo == 'cedula' ? validarCedula(valor) : validarPasaporte(valor);

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

// Documento del pasajero: la cédula admite solo dígitos (10); el pasaporte letras y dígitos en mayúsculas (12).
class DocumentoFormatter extends TextInputFormatter {
  DocumentoFormatter({required this.cedula});

  final bool cedula;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue anterior, TextEditingValue nuevo) {
    return _filtrar(
      nuevo,
      permitido: (c) => cedula ? RegExp(r'^[0-9]$').hasMatch(c) : RegExp(r'^[A-Za-z0-9]$').hasMatch(c),
      mayusculas: !cedula,
      maximo: cedula ? 10 : 12,
    );
  }
}
