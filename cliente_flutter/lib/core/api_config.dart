// Todas las peticiones pasan por el API Gateway, que reenvía cada ruta al
// microservicio correspondiente. Las constantes por servicio se mantienen para no cambiar
// los servicios que las usan; las rutas son las mismas que antes.
//
// La URL base se elige en compilación con --dart-define, sin tocar el código:
//   Local (por defecto):  flutter run
//   Producción:           flutter run --dart-define=API_BASE_URL=https://tu-gateway.onrender.com
//   Emulador Android:     flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
class ApiConfig {
  static const gateway = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );
  static const usuarios = gateway;
  static const autenticacion = gateway;
  static const vuelos = gateway;
  static const reservas = gateway;
  static const gestion = gateway;
  static const aviones = gateway;
}
