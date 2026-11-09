// Roles de la aplicación y lo que cada uno puede hacer en la interfaz.
//
// | Rol           | Cómo se obtiene                                   | Puede                                              |
// |---------------|---------------------------------------------------|----------------------------------------------------|
// | invitado      | sin sesión                                        | buscar vuelos y ver el mapa; no reservar           |
// | cliente       | sesión con claim rol = "cliente" (valor por defecto) | reservar, elegir y cambiar asientos, cancelar     |
// | administrador | sesión con claim rol = "administrador"            | gestionar vuelos (crear, editar, publicar); no reserva |
//
// El servidor es la autoridad: S1/S2 fijan el rol en el JWT y S3/S4/S5 lo validan en cada petición.
// Estos permisos solo deciden qué controles se muestran; ocultar un botón nunca reemplaza la validación del servidor.

enum Rol { invitado, cliente, administrador }

class Permisos {
  const Permisos(this.rol);

  final Rol rol;

  bool get puedeBuscarVuelos => true;

  bool get puedeVerMapa => true;

  // Reservar, cambiar asiento y cancelar: solo cuentas de cliente. Los administradores gestionan vuelos, no reservan.
  bool get puedeReservar => rol == Rol.cliente;

  bool get puedeCambiarAsiento => puedeReservar;

  bool get puedeCancelar => puedeReservar;

  // Alta de vuelos: solo administradores (POST /api/admin/vuelos, valida el rol en S3).
  bool get puedeCrearVuelos => rol == Rol.administrador;

  // Editar y activar/desactivar vuelos: solo administradores. Editar además requiere que el vuelo no tenga reservas.
  bool get puedeGestionarVuelos => rol == Rol.administrador;

  // Registro de aviones (S6): solo administradores (POST /api/admin/aviones valida el rol en el servidor).
  bool get puedeGestionarAviones => rol == Rol.administrador;
}
