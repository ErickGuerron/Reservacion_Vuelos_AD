// Detecta desbordamientos (RenderFlex overflow) de las vistas principales en tamaños de móvil,
// tableta y escritorio. Flutter reporta un overflow como excepción de la prueba.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aerovuelo_app/core/lotes.dart';
import 'package:aerovuelo_app/core/models.dart';
import 'package:aerovuelo_app/views/tarjeta_lote.dart';
import 'package:aerovuelo_app/core/ruta.dart';
import 'package:aerovuelo_app/core/session.dart';
import 'package:aerovuelo_app/main.dart';
import 'package:aerovuelo_app/theme/app_theme.dart';
import 'package:aerovuelo_app/views/acciones_admin_vuelo.dart';
import 'package:aerovuelo_app/views/acceso_view.dart';
import 'package:aerovuelo_app/views/consola_view.dart';
import 'package:aerovuelo_app/views/mis_reservas_view.dart';
import 'package:aerovuelo_app/views/vuelos_view.dart';

// Sin red en las pruebas: cada petición falla como si el servicio estuviera apagado.
class _SinRed extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _ClienteCaido();
}

class _ClienteCaido implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw const SocketException('sin red en pruebas');
}

// JWT sin firma válida: el cliente solo lee los claims "sub" y "rol" para la interfaz.
String _token(String rol) {
  String b64(Map<String, Object> json) => base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${b64({'alg': 'HS256'})}.${b64({'sub': 'ana@correo.com', 'rol': rol})}.firma';
}

String _tokenCliente() => _token('cliente');

const _vuelosAdmin = [
  VueloAdmin(id: 1, origen: 'UIO', destino: 'GYE', fecha: '2031-11-10', hora: '08:30', precio: 45.0, totalAsientos: 30, asientosDisponibles: 30, asientosOcupados: 0, activo: true, editable: true),
  VueloAdmin(id: 2, origen: 'UIO', destino: 'MAD', fecha: '2031-12-01', hora: '22:10', precio: 780.0, totalAsientos: 18, asientosDisponibles: 5, asientosOcupados: 13, activo: false, editable: false),
];

// Vuelos de ejemplo para la tabla: fechas futuras para que la venta no aparezca como cerrada.
const _vuelosEjemplo = [
  Vuelo(id: 1, origen: 'UIO', destino: 'GYE', fecha: '2031-11-10', hora: '08:30', precio: 45.0, asientosDisponibles: 30, activo: true),
  Vuelo(id: 2, origen: 'UIO', destino: 'MAD', fecha: '2031-12-01', hora: '22:10', precio: 780.0, asientosDisponibles: 0, activo: true),
  Vuelo(id: 3, origen: 'GYE', destino: 'UIO', fecha: '2031-11-15', hora: '09:45', precio: 48.0, asientosDisponibles: 12, activo: true),
];

const _tamanos = <String, Size>{
  'movil 360x740': Size(360, 740),
  'movil 390x844': Size(390, 844),
  'tableta 768x1024': Size(768, 1024),
  'escritorio 1280x800': Size(1280, 800),
};

// Monta una vista como lo hace AppShell: dentro de un scroll vertical (la altura del contenido no está acotada).
Future<void> _pumpEn(WidgetTester tester, Size tamano, Widget vista, {double escala = 1.0}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      debugShowCheckedModeBanner: false,
      // escala > 1 simula fuentes más anchas y el texto ampliado del sistema (accesibilidad).
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
        child: child!,
      ),
      home: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [vista]),
          ),
        ),
      ),
    ),
  );
  // Un tiempo fijo en vez de pumpAndSettle: las vistas tienen indicadores de carga que nunca se asientan.
  await tester.pump(const Duration(milliseconds: 500));
}

// La aplicación completa ya trae su propio MaterialApp.
Future<void> _pumpApp(WidgetTester tester, Size tamano) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const AeroVueloApp());
  await tester.pump(const Duration(milliseconds: 500));
}

// Las fuentes de Google no se descargan en pruebas, y Flutter usaría Ahem (glifos cuadrados, mucho más
// anchos que las reales) y daría overflows falsos. Se registran Arial y Consolas, de anchos parecidos,
// con los nombres de las familias del tema. Es una aproximación: confirmar en el navegador o el móvil.
Future<void> _cargarFuentesAproximadas() async {
  Future<ByteData> leer(String ruta) async => ByteData.view((await File(ruta).readAsBytes()).buffer);
  // google_fonts nombra cada variante como Familia_peso (p. ej. PlusJakartaSans_w600) cuando no puede descargarla.
  const sansFamilias = [
    'PlusJakartaSans', 'PlusJakartaSans_regular', 'PlusJakartaSans_w500', 'PlusJakartaSans_w600', 'PlusJakartaSans_w700', 'PlusJakartaSans_w800',
  ];
  const monoFamilias = ['JetBrainsMono', 'JetBrainsMono_regular', 'JetBrainsMono_w400', 'JetBrainsMono_w500'];
  for (final familia in sansFamilias) {
    final loader = FontLoader(familia)..addFont(leer(r'C:\Windows\Fonts\arial.ttf'));
    await loader.load();
  }
  for (final familia in monoFamilias) {
    final loader = FontLoader(familia)..addFont(leer(r'C:\Windows\Fonts\consola.ttf'));
    await loader.load();
  }
}

void main() {
  setUpAll(() async {
    HttpOverrides.global = _SinRed();
    await _cargarFuentesAproximadas();
  });

  for (final entrada in _tamanos.entries) {
    group(entrada.key, () {
      testWidgets('aplicación completa (vuelos)', (tester) async {
        await _pumpApp(tester, entrada.value);
        expect(tester.takeException(), isNull);
      });

      testWidgets('acceso: iniciar sesión', (tester) async {
        await _pumpEn(
          tester,
          entrada.value,
          AccesoView(vista: Ruta.login, onCambiar: (_) {}, onSesionIniciada: () {}),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('acceso: crear cuenta', (tester) async {
        await _pumpEn(
          tester,
          entrada.value,
          AccesoView(vista: Ruta.registro, onCambiar: (_) {}, onSesionIniciada: () {}),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('mis reservas con sesión de cliente', (tester) async {
        session.iniciar(_tokenCliente());
        addTearDown(session.cerrar);
        await _pumpEn(
          tester,
          entrada.value,
          MisReservasView(onIrALogin: () {}),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('tarjeta de lote con detalle abierto y texto ampliado', (tester) async {
        final reservas = [
          Reserva(id: 10, vueloId: 1, pasajero: 'Ana Torres Mendoza de la Cruz', estado: 'confirmada', asiento: '1A', loteId: 10, precio: 89),
          Reserva(id: 11, vueloId: 1, pasajero: 'Luis Alberto Mora Espinoza', estado: 'confirmada', asiento: '12C', loteId: 10, precio: 89),
          Reserva(id: 12, vueloId: 1, pasajero: 'Sofía Gabriela Vallejo', estado: 'confirmada', asiento: '2F', loteId: 10, precio: 89),
        ];
        final tarjeta = TarjetaLote(
          grupo: agruparPorLote(reservas).single,
          vuelo: null,
          onCambiarAsiento: (_) {},
          onCancelar: (_) {},
          onVerFactura: () {},
        );
        await _pumpEn(tester, entrada.value, tarjeta, escala: 1.25);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Ver detalle'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(find.text('Cambiar asiento'), findsNWidgets(3));
      });

      testWidgets('consola de servicios', (tester) async {
        await _pumpEn(tester, entrada.value, const ConsolaView());
        expect(tester.takeException(), isNull);
      });

      testWidgets('vuelos en tabla (consola matricial) sin sesión', (tester) async {
        session.cerrar();
        await _pumpEn(tester, entrada.value, ResultadosVuelos(vuelos: _vuelosEjemplo, onReservar: (_) {}));
        expect(tester.takeException(), isNull);
      });

      testWidgets('texto ampliado 1.25x: acceso, mis reservas y tabla de administrador', (tester) async {
        session.iniciar(_token('administrador'));
        addTearDown(session.cerrar);
        await _pumpEn(
          tester,
          entrada.value,
          ResultadosVuelos(
            vuelos: _vuelosEjemplo,
            onReservar: (_) {},
            acciones: (v) => AccionesAdminVuelo(
              gestion: _vuelosAdmin.firstWhere((g) => g.id == v.id, orElse: () => _vuelosAdmin.first),
              onEditar: () {},
              onEstado: () {},
            ),
          ),
          escala: 1.25,
        );
        expect(tester.takeException(), isNull);
        await _pumpEn(tester, entrada.value, AccesoView(vista: Ruta.login, onCambiar: (_) {}, onSesionIniciada: () {}), escala: 1.25);
        expect(tester.takeException(), isNull);
        await _pumpEn(tester, entrada.value, MisReservasView(onIrALogin: () {}), escala: 1.25);
        expect(tester.takeException(), isNull);
      });

      testWidgets('vuelos en tabla con acciones de administrador', (tester) async {
        session.iniciar(_token('administrador'));
        addTearDown(session.cerrar);
        await _pumpEn(
          tester,
          entrada.value,
          ResultadosVuelos(
            vuelos: _vuelosEjemplo,
            onReservar: (_) {},
            acciones: (v) => AccionesAdminVuelo(
              gestion: _vuelosAdmin.firstWhere((g) => g.id == v.id, orElse: () => _vuelosAdmin.first),
              onEditar: () {},
              onEstado: () {},
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('vuelos en tabla con botón Reservar (cliente)', (tester) async {
        session.iniciar(_tokenCliente());
        addTearDown(session.cerrar);
        await _pumpEn(tester, entrada.value, ResultadosVuelos(vuelos: _vuelosEjemplo, onReservar: (_) {}));
        expect(tester.takeException(), isNull);
      });
    });
  }
}
