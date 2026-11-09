import 'package:aerovuelo_app/widgets/scroll_por_teclado.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ScrollController> pumpPagina(WidgetTester tester) async {
    final controlador = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollPorTeclado(
            controller: controlador,
            child: SingleChildScrollView(
              controller: controlador,
              child: const SizedBox(height: 3000, width: 300),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controlador;
  }

  testWidgets('la flecha abajo desplaza la página hacia abajo', (tester) async {
    final controlador = await pumpPagina(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(controlador.offset, greaterThan(0));
  });

  testWidgets('la flecha arriba vuelve hacia arriba', (tester) async {
    final controlador = await pumpPagina(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final bajado = controlador.offset;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    expect(controlador.offset, lessThan(bajado));
  });

  testWidgets('no se sale de los límites de la página', (tester) async {
    final controlador = await pumpPagina(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(controlador.offset, 0);

    for (var i = 0; i < 60; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(controlador.offset, controlador.position.maxScrollExtent);
  });
}
