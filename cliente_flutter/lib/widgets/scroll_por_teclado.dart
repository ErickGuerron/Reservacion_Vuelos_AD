import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Desplazamiento con flechas del teclado para toda la página.
//
// Flutter solo mueve un scroll con las flechas si el foco está dentro de él, y en esta app el foco
// suele quedar en botones o campos, así que las flechas no bajan la página. Este widget toma el foco
// por defecto y, cuando una flecha llega hasta él (es decir, ningún campo de texto la usó), mueve
// el contenedor de scroll. Los campos de texto siguen usando las flechas para mover el cursor.
class ScrollPorTeclado extends StatefulWidget {
  const ScrollPorTeclado({super.key, required this.controller, required this.child, this.paso = 80});

  final ScrollController controller;
  final Widget child;
  // Píxeles que se desplazan por cada pulsación de flecha.
  final double paso;

  @override
  State<ScrollPorTeclado> createState() => _ScrollPorTecladoState();
}

// Envuelve un diálogo (cada uno es una ruta aparte, fuera de la página). Su contenido desplazable
// usa el controlador de este widget como scroll principal, y las flechas lo mueven igual que en la página.
class ScrollDialogo extends StatefulWidget {
  const ScrollDialogo({super.key, required this.child});

  final Widget child;

  @override
  State<ScrollDialogo> createState() => _ScrollDialogoState();
}

class _ScrollDialogoState extends State<ScrollDialogo> {
  final _controlador = ScrollController();

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScrollPorTeclado(
      controller: _controlador,
      child: PrimaryScrollController(controller: _controlador, child: widget.child),
    );
  }
}

class _ScrollPorTecladoState extends State<ScrollPorTeclado> {
  final _foco = FocusNode(debugLabel: 'desplazamiento-por-teclado');

  @override
  void dispose() {
    _foco.dispose();
    super.dispose();
  }

  KeyEventResult _alPulsarTecla(FocusNode nodo, KeyEvent evento) {
    if (evento is KeyUpEvent) return KeyEventResult.ignored;
    final tecla = evento.logicalKey;
    final bajar = tecla == LogicalKeyboardKey.arrowDown;
    final subir = tecla == LogicalKeyboardKey.arrowUp;
    if (!bajar && !subir) return KeyEventResult.ignored;
    if (!widget.controller.hasClients) return KeyEventResult.ignored;

    final posicion = widget.controller.position;
    final destino = (posicion.pixels + (bajar ? widget.paso : -widget.paso))
        .clamp(posicion.minScrollExtent, posicion.maxScrollExtent)
        .toDouble();
    if (destino != posicion.pixels) {
      widget.controller.animateTo(destino, duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Si se toca un punto sin campo enfocable, el foco vuelve aquí y las flechas siguen funcionando.
      onPointerUp: (_) {
        if (FocusManager.instance.primaryFocus == null) _foco.requestFocus();
      },
      child: Focus(
        focusNode: _foco,
        autofocus: true,
        onKeyEvent: _alPulsarTecla,
        child: widget.child,
      ),
    );
  }
}
