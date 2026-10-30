import 'package:flutter/foundation.dart';

import 'models.dart';
import 'services.dart';
import 'session.dart';

// Contador de "Mis Reservas" en la cabecera (número de reservas confirmadas).
final ValueNotifier<int?> contadorReservas = ValueNotifier(null);

// Se incrementa cuando se crea una reserva; Mis Reservas escucha para recargarse,
// igual que el evento "reserva:creada" del cliente web.
final ValueNotifier<int> reservaCreadaVersion = ValueNotifier(0);

void anunciarReservaCreada() {
  reservaCreadaVersion.value++;
  refrescarContador();
}

Future<void> refrescarContador() async {
  final token = session.token;
  if (token == null) {
    contadorReservas.value = null;
    return;
  }
  try {
    final reservas = await ReservasService.listar(token: token);
    final confirmadas = reservas.where((Reserva r) => r.confirmada).length;
    contadorReservas.value = confirmadas == 0 ? null : confirmadas;
  } catch (_) {
    contadorReservas.value = null;
  }
}
