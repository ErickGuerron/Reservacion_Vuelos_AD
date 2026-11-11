import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// Un intercambio HTTP registrado, equivalente a window.registroHttp de cargador.js.
// Las contraseñas se ocultan y el token nunca se guarda en claro.
class HttpExchange {
  HttpExchange({
    required this.fecha,
    required this.metodo,
    required this.url,
    required this.status,
    required this.ms,
    required this.autorizacion,
    required this.peticion,
    required this.respuesta,
    required this.error,
  });

  final DateTime fecha;
  final String metodo;
  final String url;
  final int status;
  final int ms;
  final String? autorizacion;
  final Object? peticion;
  final Object? respuesta;
  final String? error;

  bool get conError => status == 0 || status >= 400;

  // Clave de servicio (5001..5005) extraída del puerto de la URL.
  String? get puertoServicio => RegExp(r':(\d{4})/').firstMatch(url)?.group(1);

  Map<String, dynamic> toJson() => {
        'fecha': fecha.toIso8601String(),
        'metodo': metodo,
        'url': url,
        'status': status,
        'ms': ms,
        'autorizacion': autorizacion,
        'peticion': peticion,
        'respuesta': respuesta,
        'error': error,
      };
}

// Respuesta ya parseada: status + cuerpo JSON (o null si no era JSON).
class ApiResponse {
  const ApiResponse(this.status, this.cuerpo);
  final int status;
  final dynamic cuerpo;
  bool get ok => status >= 200 && status < 300;

  // Mensaje de error del servicio: cuerpo.mensaje, como en el cliente web.
  String? get mensaje => cuerpo is Map ? cuerpo['mensaje'] as String? : null;
}

class ApiException implements Exception {
  ApiException(this.mensaje, {this.status, this.codigo});
  final String mensaje;
  // Código de error del servicio (cuerpo.codigo), por ejemplo ASIENTO_OCUPADO o MAPA_DESACTUALIZADO.
  final String? codigo;
  final int? status;
  @override
  String toString() => mensaje;
}

// El servicio no respondió (equivale al catch de cada componente web).
class ConexionFallida extends ApiException {
  ConexionFallida() : super('No se pudo establecer la conexión.');
}

// Cliente HTTP único: registra cada intercambio y expone el registro a la consola de auditoría.
class ApiClient {
  static const _maximoRegistros = 200;
  static final ValueNotifier<int> cambios = ValueNotifier(0);
  static final List<HttpExchange> registro = [];

  static Future<ApiResponse> enviar(
    String metodo,
    Uri uri, {
    Map<String, String>? cabeceras,
    Object? cuerpo,
  }) async {
    final headers = <String, String>{'Accept': 'application/json', ...?cabeceras};
    final tieneAuth = headers.containsKey('Authorization');
    final peticion = cuerpo == null ? null : _ocultarSecretos(cuerpo);
    final inicio = DateTime.now();
    final sw = Stopwatch()..start();

    try {
      final request = http.Request(metodo, uri)..headers.addAll(headers);
      if (cuerpo != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(cuerpo);
      }
      final streamed = await request.send();
      final texto = await streamed.stream.bytesToString();
      final respuesta = _leerJson(texto);
      _registrar(HttpExchange(
        fecha: inicio,
        metodo: metodo,
        url: uri.toString(),
        status: streamed.statusCode,
        ms: sw.elapsedMilliseconds,
        autorizacion: tieneAuth ? 'Bearer (oculto)' : null,
        peticion: peticion,
        respuesta: respuesta,
        error: null,
      ));
      return ApiResponse(streamed.statusCode, respuesta);
    } catch (_) {
      _registrar(HttpExchange(
        fecha: inicio,
        metodo: metodo,
        url: uri.toString(),
        status: 0,
        ms: sw.elapsedMilliseconds,
        autorizacion: tieneAuth ? 'Bearer (oculto)' : null,
        peticion: peticion,
        respuesta: null,
        error: 'No se pudo establecer la conexión.',
      ));
      throw ConexionFallida();
    }
  }

  static Object? _ocultarSecretos(Object cuerpo) {
    if (cuerpo is Map && cuerpo.containsKey('password')) {
      return {...cuerpo, 'password': '********'};
    }
    return cuerpo;
  }

  static dynamic _leerJson(String texto) {
    if (texto.isEmpty) return null;
    try {
      return jsonDecode(texto);
    } catch (_) {
      return texto;
    }
  }

  static void _registrar(HttpExchange evento) {
    registro.add(evento);
    if (registro.length > _maximoRegistros) registro.removeAt(0);
    cambios.value++;
  }
}
