import 'api_client.dart';
import 'api_config.dart';
import 'horarios.dart';
import 'models.dart';

// Servicios REST, uno por microservicio. Misma forma de llamada que los componentes web.

class AuthService {
  // POST /api/auth/login (S2). Devuelve el token o lanza ApiException con el mensaje del servicio.
  static Future<String> login(String email, String password) async {
    final respuesta = await ApiClient.enviar(
      'POST',
      Uri.parse('${ApiConfig.autenticacion}/api/auth/login'),
      cuerpo: {'email': email, 'password': password},
    );
    if (!respuesta.ok) {
      throw ApiException(respuesta.mensaje ?? 'No se pudo iniciar sesión.');
    }
    return (respuesta.cuerpo as Map)['token'] as String;
  }

  // POST /api/auth/logout (S2): revoca el token en el servidor. El cliente cierra su sesión aunque falle.
  static Future<void> logout(String token) async {
    await ApiClient.enviar(
      'POST',
      Uri.parse('${ApiConfig.autenticacion}/api/auth/logout'),
      cabeceras: {'Authorization': 'Bearer $token'},
    );
  }
}

class UsuariosService {
  // POST /api/usuarios (S1). Devuelve el correo registrado.
  static Future<String> registrar({required String nombre, required String email, required String password}) async {
    final respuesta = await ApiClient.enviar(
      'POST',
      Uri.parse('${ApiConfig.usuarios}/api/usuarios'),
      cuerpo: {'nombre': nombre, 'email': email, 'password': password},
    );
    if (respuesta.status != 201) {
      throw ApiException(respuesta.mensaje ?? 'No se pudo completar el registro.', status: respuesta.status);
    }
    return (respuesta.cuerpo as Map)['email'] as String;
  }
}

class VuelosService {
  // GET /api/vuelos (S3) con los filtros de la búsqueda.
  static Future<List<Vuelo>> buscar({required String origen, String? destino, String? fecha}) async {
    final parametros = <String, String>{'origen': origen};
    if (destino != null) parametros['destino'] = destino;
    if (fecha != null && fecha.isNotEmpty) parametros['fecha'] = fecha;

    final respuesta = await ApiClient.enviar(
      'GET',
      Uri.parse('${ApiConfig.vuelos}/api/vuelos').replace(queryParameters: parametros),
    );
    if (!respuesta.ok) {
      throw ApiException(respuesta.mensaje ?? 'No se pudo consultar los vuelos.');
    }
    return (respuesta.cuerpo as List).map((v) => Vuelo.fromJson(v as Map<String, dynamic>)).toList();
  }

  // GET /api/vuelos/estimacion (S3): duración habitual de la ruta y llegada sugerida. Es una ayuda: si el
  // servicio no responde o la ruta no tiene datos, devuelve null y el formulario sigue sin la estimación.
  static Future<EstimacionVuelo?> estimacion({
    required String origen,
    required String destino,
    required String fecha,
    required String hora,
    String? horaLlegada,
  }) async {
    try {
      final respuesta = await ApiClient.enviar(
        'GET',
        Uri.parse('${ApiConfig.vuelos}/api/vuelos/estimacion').replace(queryParameters: {
          'origen': origen,
          'destino': destino,
          'fecha': fecha,
          'hora': hora,
          if (horaLlegada != null) 'horaLlegada': horaLlegada,
        }),
      );
      if (!respuesta.ok) return null;
      return EstimacionVuelo.fromJson(respuesta.cuerpo as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  // GET /api/vuelos/{id}/asientos (S3): disponibilidad real de cada asiento.
  static Future<List<AsientoRemoto>> mapa(int vueloId) async {
    final respuesta = await ApiClient.enviar('GET', Uri.parse('${ApiConfig.vuelos}/api/vuelos/$vueloId/asientos'));
    if (!respuesta.ok) {
      throw ApiException(respuesta.mensaje ?? 'No se pudo cargar el mapa de asientos.', status: respuesta.status);
    }
    final asientos = (respuesta.cuerpo as Map)['asientos'] as List;
    return asientos.map((a) => AsientoRemoto.fromJson(a as Map<String, dynamic>)).toList();
  }

  // GET /api/vuelos/{id} (S3). Devuelve null si el vuelo ya no existe.
  static Future<Vuelo?> obtener(int id) async {
    try {
      final respuesta = await ApiClient.enviar('GET', Uri.parse('${ApiConfig.vuelos}/api/vuelos/$id'));
      if (!respuesta.ok) return null;
      return Vuelo.fromJson(respuesta.cuerpo as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

class FacturasService {
  // GET /api/reservas/lote/{id}/factura (S5). Devuelve el XML tal cual lo genera el servicio.
  static Future<String> obtener({required int loteId, required String token}) async {
    final respuesta = await ApiClient.enviar(
      'GET',
      Uri.parse('${ApiConfig.gestion}/api/reservas/lote/$loteId/factura'),
      cabeceras: {'Authorization': 'Bearer $token', 'Accept': 'application/xml'},
    );
    if (respuesta.status == 401) throw SesionExpirada();
    if (!respuesta.ok || respuesta.cuerpo is! String) {
      throw ApiException(respuesta.mensaje ?? 'No se pudo generar la factura.', status: respuesta.status);
    }
    return respuesta.cuerpo as String;
  }
}

class ReservasService {
  // POST /api/reservas (S4). Devuelve la reserva creada.
  // POST /api/reservas/lote (S4): reserva todos los asientos o ninguno.
  // Si alguno ya está ocupado, el servidor responde 409 y no guarda nada; el status viene en la excepción.
  static Future<List<Reserva>> crearLote({
    required int vueloId,
    required List<({String pasajero, String asiento, String tipoDocumento, String documento})> reservas,
    required String token,
  }) async {
    final respuesta = await ApiClient.enviar(
      'POST',
      Uri.parse('${ApiConfig.reservas}/api/reservas/lote'),
      cabeceras: {'Authorization': 'Bearer $token'},
      cuerpo: {
        'vueloId': vueloId,
        'reservas': [
          for (final r in reservas)
            {'pasajero': r.pasajero, 'asiento': r.asiento, 'tipoDocumento': r.tipoDocumento, 'documento': r.documento},
        ],
      },
    );
    if (respuesta.status != 201) {
      throw ApiException(respuesta.mensaje ?? 'No se pudo crear la reserva.', status: respuesta.status);
    }
    return (respuesta.cuerpo as List).map((r) => Reserva.fromJson(r as Map<String, dynamic>)).toList();
  }

  // GET /api/reservas (S5).
  static Future<List<Reserva>> listar({required String token}) async {
    final respuesta = await ApiClient.enviar(
      'GET',
      Uri.parse('${ApiConfig.gestion}/api/reservas'),
      cabeceras: {'Authorization': 'Bearer $token'},
    );
    if (respuesta.status == 401) throw SesionExpirada();
    if (!respuesta.ok) {
      throw ApiException(respuesta.mensaje ?? 'No se pudieron cargar las reservas.');
    }
    return (respuesta.cuerpo as List).map((r) => Reserva.fromJson(r as Map<String, dynamic>)).toList();
  }

  // DELETE /api/reservas/{id} (S5).
  static Future<void> cancelar({required int id, required String token}) async {
    final respuesta = await ApiClient.enviar(
      'DELETE',
      Uri.parse('${ApiConfig.gestion}/api/reservas/$id'),
      cabeceras: {'Authorization': 'Bearer $token'},
    );
    if (!respuesta.ok) {
      throw ApiException(respuesta.mensaje ?? 'No se pudo cancelar la reserva.');
    }
  }

  // PUT /api/reservas/{id}/asiento (S4): mueve la reserva propia a otro asiento libre.
  static Future<String> cambiarAsiento({required int id, required String asiento, required String token}) async {
    final respuesta = await ApiClient.enviar(
      'PUT',
      Uri.parse('${ApiConfig.reservas}/api/reservas/$id/asiento'),
      cabeceras: {'Authorization': 'Bearer $token'},
      cuerpo: {'asiento': asiento},
    );
    if (!respuesta.ok) {
      throw ApiException(respuesta.mensaje ?? 'No se pudo cambiar el asiento.', status: respuesta.status);
    }
    return (respuesta.cuerpo as Map)['asiento'] as String;
  }
}

// Alta de vuelos (solo administradores). El servidor valida el total: 18 a 180 y múltiplo de 6.
class AdminService {
  static Future<Vuelo> crearVuelo({
    // false (por defecto) crea el vuelo como borrador: no se muestra a los clientes hasta publicarlo.
    bool activo = false,
    required String origen,
    required String destino,
    required String fecha,
    required String hora,
    String? horaLlegada,
    required double precio,
    // Avión registrado (S6): sus asientos son los del vuelo.
    required int avionId,
    required String token,
  }) async {
    final respuesta = await ApiClient.enviar(
      'POST',
      Uri.parse('${ApiConfig.vuelos}/api/admin/vuelos'),
      cabeceras: {'Authorization': 'Bearer $token'},
      cuerpo: {
        'origen': origen,
        'destino': destino,
        'fecha': fecha,
        'hora': hora,
        'horaLlegada': horaLlegada,
        'precio': precio,
        'avionId': avionId,
        'activo': activo,
      },
    );
    if (respuesta.status != 201) {
      throw ApiException(respuesta.mensaje ?? 'No se pudo crear el vuelo.', status: respuesta.status);
    }
    return Vuelo.fromJson(respuesta.cuerpo as Map<String, dynamic>);
  }
}

// Registro de aviones (S6): solo administradores. Nombre y capacidad (número de asientos).
class AvionesService {
  // GET /api/admin/aviones: todos los aviones, también los inactivos.
  static Future<List<Avion>> listar({required String token}) async {
    final respuesta = await ApiClient.enviar(
      'GET',
      Uri.parse('${ApiConfig.aviones}/api/admin/aviones'),
      cabeceras: {'Authorization': 'Bearer $token'},
    );
    if (!respuesta.ok) {
      throw ApiException(respuesta.mensaje ?? 'No se pudieron cargar los aviones.', status: respuesta.status);
    }
    return (respuesta.cuerpo as List).map((a) => Avion.fromJson(a as Map<String, dynamic>)).toList();
  }

  // POST /api/admin/aviones: 201 con el avión creado. Nombre repetido: 409 AVION_DUPLICADO.
  static Future<Avion> crear({required String nombre, required int capacidad, required String token}) async {
    final respuesta = await ApiClient.enviar(
      'POST',
      Uri.parse('${ApiConfig.aviones}/api/admin/aviones'),
      cabeceras: {'Authorization': 'Bearer $token'},
      cuerpo: {'nombre': nombre, 'capacidad': capacidad},
    );
    if (respuesta.status != 201) {
      throw ApiException(respuesta.mensaje ?? 'No se pudo registrar el avión.', status: respuesta.status);
    }
    return Avion.fromJson(respuesta.cuerpo as Map<String, dynamic>);
  }

  // PUT /api/admin/aviones/{id}: cambia nombre y capacidad. Los vuelos existentes conservan su mapa.
  static Future<Avion> editar({required int id, required String nombre, required int capacidad, required String token}) async {
    final respuesta = await ApiClient.enviar(
      'PUT',
      Uri.parse('${ApiConfig.aviones}/api/admin/aviones/$id'),
      cabeceras: {'Authorization': 'Bearer $token'},
      cuerpo: {'nombre': nombre, 'capacidad': capacidad},
    );
    if (!respuesta.ok) {
      throw ApiException(respuesta.mensaje ?? 'No se pudo editar el avión.', status: respuesta.status);
    }
    return Avion.fromJson(respuesta.cuerpo as Map<String, dynamic>);
  }

  // PATCH /api/admin/aviones/{id}/estado: activa o desactiva el avión para nuevos vuelos.
  static Future<Avion> cambiarEstado({required int id, required bool activo, required String token}) async {
    final respuesta = await ApiClient.enviar(
      'PATCH',
      Uri.parse('${ApiConfig.aviones}/api/admin/aviones/$id/estado'),
      cabeceras: {'Authorization': 'Bearer $token'},
      cuerpo: {'activo': activo},
    );
    if (!respuesta.ok) {
      throw ApiException(respuesta.mensaje ?? 'No se pudo cambiar el estado del avión.', status: respuesta.status);
    }
    return Avion.fromJson(respuesta.cuerpo as Map<String, dynamic>);
  }
}

// Gestión de vuelos por el administrador: listar todos, editar los que no tienen reservas, activar o desactivar.
class GestionVuelosService {
  // GET /api/admin/vuelos (S3): todos los vuelos, también los inactivos.
  static Future<List<VueloAdmin>> listar({required String token}) async {
    final respuesta = await ApiClient.enviar(
      'GET',
      Uri.parse('${ApiConfig.vuelos}/api/admin/vuelos'),
      cabeceras: {'Authorization': 'Bearer $token'},
    );
    if (!respuesta.ok) {
      throw ApiException(respuesta.mensaje ?? 'No se pudieron cargar los vuelos.', status: respuesta.status);
    }
    return (respuesta.cuerpo as List).map((v) => VueloAdmin.fromJson(v as Map<String, dynamic>)).toList();
  }

  // PUT /api/admin/vuelos/{id} (S3): solo si el vuelo no tiene reservas (409 VUELO_CON_RESERVAS si las tiene).
  static Future<VueloAdmin> editar({
    required int id,
    required String origen,
    required String destino,
    required String fecha,
    required String hora,
    String? horaLlegada,
    required double precio,
    required int avionId,
    required String token,
  }) async {
    final respuesta = await ApiClient.enviar(
      'PUT',
      Uri.parse('${ApiConfig.vuelos}/api/admin/vuelos/$id'),
      cabeceras: {'Authorization': 'Bearer $token'},
      cuerpo: {
        'origen': origen,
        'destino': destino,
        'fecha': fecha,
        'hora': hora,
        // El PUT reemplaza el vuelo completo: sin este campo la llegada guardada se borraría.
        'horaLlegada': horaLlegada,
        'precio': precio,
        'avionId': avionId,
      },
    );
    if (!respuesta.ok) {
      throw ApiException(respuesta.mensaje ?? 'No se pudo editar el vuelo.', status: respuesta.status);
    }
    return VueloAdmin.fromJson(respuesta.cuerpo as Map<String, dynamic>);
  }

  // PATCH /api/admin/vuelos/{id}/estado (S3): activa o desactiva el vuelo para los clientes.
  static Future<VueloAdmin> cambiarEstado({required int id, required bool activo, required String token}) async {
    final respuesta = await ApiClient.enviar(
      'PATCH',
      Uri.parse('${ApiConfig.vuelos}/api/admin/vuelos/$id/estado'),
      cabeceras: {'Authorization': 'Bearer $token'},
      cuerpo: {'activo': activo},
    );
    if (!respuesta.ok) {
      throw ApiException(respuesta.mensaje ?? 'No se pudo cambiar el estado del vuelo.', status: respuesta.status);
    }
    return VueloAdmin.fromJson(respuesta.cuerpo as Map<String, dynamic>);
  }
}

// Asiento tal como lo entrega S3 en GET /api/vuelos/{id}/asientos.
class AsientoRemoto {
  const AsientoRemoto({required this.codigo, required this.fila, required this.columna, required this.ocupado});

  final String codigo;
  final int fila;
  final String columna;
  final bool ocupado;

  factory AsientoRemoto.fromJson(Map<String, dynamic> json) => AsientoRemoto(
        codigo: json['codigo'] as String,
        fila: (json['fila'] as num).toInt(),
        columna: json['columna'] as String,
        ocupado: json['ocupado'] as bool,
      );
}

class SesionExpirada extends ApiException {
  SesionExpirada() : super('Su sesión expiró. Inicie sesión de nuevo.');
}
