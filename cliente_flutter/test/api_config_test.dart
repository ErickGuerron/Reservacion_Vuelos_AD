import 'package:aerovuelo_app/core/api_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('La URL base del gateway es una URI absoluta sin barra final', () {
    final uri = Uri.parse(ApiConfig.gateway);

    expect(uri.hasScheme, isTrue);
    expect(uri.host, isNotEmpty);
    expect(ApiConfig.gateway.endsWith('/'), isFalse);
  });

  test('Todos los servicios usan la misma URL base del gateway', () {
    expect(ApiConfig.usuarios, ApiConfig.gateway);
    expect(ApiConfig.autenticacion, ApiConfig.gateway);
    expect(ApiConfig.vuelos, ApiConfig.gateway);
    expect(ApiConfig.reservas, ApiConfig.gateway);
    expect(ApiConfig.gestion, ApiConfig.gateway);
  });
}
