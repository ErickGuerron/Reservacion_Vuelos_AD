import 'package:aerovuelo_app/widgets/alerta_exito.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpConBoton(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => mostrarAlertaExito(context, titulo: 'Boletos reservados', mensaje: 'Números de reserva: #7.'),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('muestra el título y el mensaje de éxito', (tester) async {
    await pumpConBoton(tester);

    expect(find.text('Boletos reservados'), findsOneWidget);
    expect(find.text('Números de reserva: #7.'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('no se cierra al tocar fuera: hay que aceptar', (tester) async {
    await pumpConBoton(tester);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.text('Boletos reservados'), findsOneWidget);
  });

  testWidgets('Aceptar cierra la alerta', (tester) async {
    await pumpConBoton(tester);

    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();

    expect(find.text('Boletos reservados'), findsNothing);
  });
}
