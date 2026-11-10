# aerovuelo_app

Cliente Flutter de Reservas de Vuelos. Consume el API Gateway (`/api/...`), que reenvía cada ruta a su microservicio.

## URL del API

La URL base se define en compilación con `--dart-define` (`lib/core/api_config.dart`):

- Variable: `API_BASE_URL`
- Por defecto: `http://localhost:8000` (gateway en local)

## Comandos

Ejecutar desde la carpeta `cliente_flutter/`.

```powershell
# Local (gateway en tu PC)
flutter run

# Emulador Android (localhost del emulador apunta al propio emulador)
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000

# Producción (backend en Render)
flutter run -d chrome --web-port=8083 --dart-define=API_BASE_URL=https://tu-gateway.onrender.com

# APK de producción
flutter build apk --dart-define=API_BASE_URL=https://tu-gateway.onrender.com

# Pruebas
flutter test
```

Reemplaza `tu-gateway.onrender.com` por la URL pública del servicio gateway en Render. Sin `https://` o con una barra final, las peticiones fallan.

Flutter no lee variables de entorno del sistema en tiempo de ejecución: la URL queda fijada en el build por `--dart-define`.
