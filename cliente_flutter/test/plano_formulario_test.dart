import 'package:aerovuelo_app/widgets/plano_formulario.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la vista previa tiene un asiento por plaza de la capacidad', () {
    expect(asientosPrevia(18).length, 18);
    expect(asientosPrevia(72).length, 72);
    expect(asientosPrevia(180).length, 180);
  });

  testWidgets('la vista previa muestra asientos, filas y disposición del avión', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: VistaPreviaAvion(
              total: 36,
              asientos: asientosPrevia(36),
              controlador: TransformationController(),
            ),
          ),
        ),
      ),
    );

    expect(find.text('36 asientos'), findsOneWidget);
    expect(find.text('6 filas'), findsOneWidget);
    expect(find.text('3 + 3'), findsOneWidget);
  });
}
