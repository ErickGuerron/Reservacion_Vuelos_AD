// Todas las peticiones pasan por el API Gateway (puerto 8000), que reenvía cada ruta al
// microservicio correspondiente. Las constantes por servicio se mantienen para no cambiar
// los servicios que las usan; las rutas son las mismas que antes.
// Para Android emulator usar 10.0.2.2 en lugar de localhost.
class ApiConfig {
  static const gateway = 'http://localhost:8000';
  static const usuarios = gateway;
  static const autenticacion = gateway;
  static const vuelos = gateway;
  static const reservas = gateway;
  static const gestion = gateway;
}
