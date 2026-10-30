import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/services.dart';

// Mapa interactivo de asientos (port del mapa HTML). El plano usa el mismo sistema de
// coordenadas que el original: el dibujo del avión se gira 180° para que el frente quede a la izquierda.

const _anchoPlano = 2300.0;
const _altoPlano = 1800.0;
const _cy = 900.0;
const _numFilas = 30; // máximo: 180 asientos = 30 filas de 3 + 3
const _pitch = 39.6;
const _anchoAsiento = 34.0;
const _altoAsiento = 28.0;
const _extra = 22.0;
const _filasSalida = [13, 14];
const _letras = ['F', 'E', 'D', 'C', 'B', 'A'];
const _yAsiento = [815.0, 839.0, 863.0, 913.0, 937.0, 961.0];

enum EstadoAsiento { disponible, reservado, seleccionado }

class Asiento {
  Asiento({
    required this.codigo,
    required this.letra,
    required this.fila,
    required this.x,
    required this.y,
    required this.salida,
    required this.estado,
    this.nombre,
  });

  final String codigo;
  final String letra;
  final int fila;
  final double x;
  final double y;
  final bool salida;
  EstadoAsiento estado;
  String? nombre;

  Rect get area => Rect.fromLTWH(x, y, _anchoAsiento, _altoAsiento);
}

// Posición X de cada fila en coordenadas del avión (antes del giro).
List<double> posicionesFilas() {
  final xs = List<double>.filled(_numFilas + 1, 0);
  var x = 1752.0;
  for (var r = 1; r <= _numFilas; r++) {
    if (r == _filasSalida.first) x -= _extra;
    xs[r] = x;
    x -= _pitch;
  }
  return xs;
}

// Convierte el mapa de S3 en asientos dibujables. Los ocupados por otros pasajeros quedan sin
// nombre (protección de datos): el nombre solo se asigna a los asientos que elige el propio cliente.
List<Asiento> asientosDesde(List<AsientoRemoto> remotos) {
  final filasX = posicionesFilas();
  return [
    for (final r in remotos)
      Asiento(
        codigo: r.codigo,
        letra: r.columna,
        fila: r.fila,
        x: _anchoPlano - filasX[r.fila] - _anchoAsiento,
        y: _yAsiento[_letras.indexOf(r.columna)],
        salida: _filasSalida.contains(r.fila),
        estado: r.ocupado ? EstadoAsiento.reservado : EstadoAsiento.disponible,
      ),
  ];
}

class MapaAsientos extends StatefulWidget {
  const MapaAsientos({super.key, required this.asientos, required this.onToque, required this.controlador});

  final List<Asiento> asientos;
  final ValueChanged<Asiento> onToque;
  final TransformationController controlador;

  @override
  State<MapaAsientos> createState() => _MapaAsientosState();
}

class _MapaAsientosState extends State<MapaAsientos> {
  final List<double> _filasX = posicionesFilas();
  bool _encuadrado = false;

  Size _tamano = Size.zero;

  Offset get _centro => Offset(_tamano.width / 2, _tamano.height / 2);

  // Centra la cabina (x 334..1774, y 790..1010) en el visor.
  void _encuadrar([Size? s]) {
    final t = s ?? _tamano;
    if (t.isEmpty) return;
    // Encuadra el avión que se dibuja: desde la nariz hasta la cola ajustada al número de asientos.
    final izquierda = 2300 - 2126.0;
    final derecha = 2300 - colaX(ultimaFila(widget.asientos));
    final k = math.min(t.width / (derecha - izquierda + 80), t.height / (220 + 120));
    final centroX = (izquierda + derecha) / 2;
    widget.controlador.value = Matrix4.identity()
      ..translateByDouble(t.width / 2 - centroX * k, t.height / 2 - _cy * k, 0, 1)
      ..scaleByDouble(k, k, 1, 1);
  }

  // Zoom alrededor de un punto del visor: el cursor, o el centro con los botones.
  void _zoomEn(double factor, Offset foco) {
    final actual = widget.controlador.value.getMaxScaleOnAxis();
    final nueva = math.min(math.max(actual * factor, .3), 4.0);
    final real = nueva / actual;
    if (real == 1) return;
    final ajuste = Matrix4.translationValues(foco.dx, foco.dy, 0)
      ..scaleByDouble(real, real, 1, 1)
      ..translateByDouble(-foco.dx, -foco.dy, 0, 1);
    widget.controlador.value = ajuste * widget.controlador.value;
  }

  Asiento? _buscar(Offset p) {
    for (final a in widget.asientos) {
      if (a.area.inflate(2).contains(p)) return a;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, restricciones) {
      _tamano = restricciones.biggest;
      if (!_encuadrado) {
        _encuadrado = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _encuadrar(restricciones.biggest);
        });
      }
      return Stack(
        children: [
          Positioned.fill(
            child: ClipRect(
              child: Listener(
                // Rueda del ratón: el zoom se hace en la posición del cursor.
                onPointerSignal: (e) {
                  if (e is PointerScrollEvent) {
                    _zoomEn(e.scrollDelta.dy < 0 ? 1.15 : 1 / 1.15, e.localPosition);
                  }
                },
                child: InteractiveViewer(
                  transformationController: widget.controlador,
                  minScale: .3,
                  maxScale: 4,
                  // Sin límite de paneo: se puede llegar a cualquier asiento del plano.
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  constrained: false,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) {
                      final a = _buscar(d.localPosition);
                      if (a != null) widget.onToque(a);
                    },
                    child: SizedBox(
                      width: _anchoPlano,
                      height: _altoPlano,
                      child: CustomPaint(painter: _PlanoPainter(widget.asientos, _filasX)),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 10,
            top: 10,
            child: Column(
              children: [
                _BotonZoom(icono: Icons.add, tooltip: 'Acercar', onPressed: () => _zoomEn(1.25, _centro)),
                _BotonZoom(icono: Icons.remove, tooltip: 'Alejar', onPressed: () => _zoomEn(1 / 1.25, _centro)),
                _BotonZoom(icono: Icons.center_focus_strong, tooltip: 'Centrar cabina', onPressed: () => _encuadrar()),
              ],
            ),
          ),
        ],
      );
    });
  }
}

class _BotonZoom extends StatelessWidget {
  const _BotonZoom({required this.icono, required this.tooltip, required this.onPressed});

  final IconData icono;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.white,
        elevation: 2,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tooltip,
          icon: Icon(icono, size: 18, color: const Color(0xFF64549D)),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

double _lw(double d) => 1470 - .466 * (d - 60); // ala: borde de ataque
double _tw(double d) => 1150 - .16 * (d - 60); // ala: borde de salida
double _lh(double d) => 530 - .55 * (d - 40); // estabilizador horizontal
double _th(double d) => 380 - .28 * (d - 40);

double _cp(double Function(double) l, double Function(double) t, double d, double f) => t(d) + (l(d) - t(d)) * f;

Path _trapecio(double s, double Function(double) l, double Function(double) t, double d0, double d1) {
  return Path()
    ..moveTo(l(d0), _cy + s * d0)
    ..lineTo(l(d1), _cy + s * d1)
    ..lineTo(t(d1), _cy + s * d1)
    ..lineTo(t(d0), _cy + s * d0)
    ..close();
}

Path _nacela(double yc) {
  const xf = 1470.0, xc = 1365.0, xr = 1252.0;
  return Path()
    ..moveTo(xf, yc - 50)
    ..lineTo(xc - 30, yc - 50)
    ..lineTo(xr + 16, yc - 34)
    ..quadraticBezierTo(xr, yc - 32, xr, yc - 24)
    ..lineTo(xr, yc + 24)
    ..quadraticBezierTo(xr, yc + 32, xr + 16, yc + 34)
    ..lineTo(xc - 30, yc + 50)
    ..lineTo(xf, yc + 50)
    ..quadraticBezierTo(xf + 10, yc, xf, yc - 50)
    ..close();
}

// Fuselaje con la cola en `cola` (x original). Con 30 filas la cola queda en ~150, igual que el dibujo original.
Path _fuselaje(double cola) {
  return Path()
    ..moveTo(cola, 886)
    ..cubicTo(cola + 210, 878, cola + 350, 797, cola + 500, 797)
    ..lineTo(1850, 797)
    ..cubicTo(2000, 797, 2118, 840, 2126, 900)
    ..cubicTo(2118, 960, 2000, 1003, 1850, 1003)
    ..lineTo(cola + 500, 1003)
    ..cubicTo(cola + 350, 1003, cola + 210, 922, cola, 914)
    ..close();
}

// Posición (x original) de la cola del avión según la última fila con asientos. Sigue la misma distancia
// que hay en el dibujo completo entre la última fila y la cola.
double colaX(int ultimaFila) {
  final n = ultimaFila.clamp(1, _numFilas);
  return posicionesFilas()[n] - 430;
}

int ultimaFila(List<Asiento> asientos) => asientos.fold<int>(0, (maximo, a) => math.max(maximo, a.fila));

class _PlanoPainter extends CustomPainter {
  _PlanoPainter(this.asientos, this.filasX);

  final List<Asiento> asientos;
  final List<double> filasX;

  @override
  void paint(Canvas canvas, Size size) {
    // Avión: se dibuja en coordenadas originales y se gira 180°.
    canvas.save();
    canvas.translate(_anchoPlano, _altoPlano);
    canvas.scale(-1, -1);
    _dibujarAvion(canvas, colaX(ultimaFila(asientos)));
    canvas.restore();

    _dibujarDetalles(canvas);
    for (final a in asientos) {
      _dibujarAsiento(canvas, a);
    }
    _dibujarEtiquetas(canvas);
  }

  @override
  bool shouldRepaint(covariant _PlanoPainter oldDelegate) => true;

  void _dibujarAvion(Canvas c, double cola) {
    // Desplazamiento de la cola respecto al avión completo; las alas se mueven a la mitad.
    final dx = cola - colaX(_numFilas);
    final fusel = _fuselaje(cola);

    // Sombra difusa
    final sombra = Paint()
      ..color = const Color(0x3339446F)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    c.save();
    c.translate(0, -22);
    for (final s in [-1.0, 1.0]) {
      c.drawPath(_trapecio(s, _lw, _tw, 60, 880), sombra);
      c.drawPath(_trapecio(s, _lh, _th, 40, 326), sombra);
    }
    c.drawPath(fusel, sombra);
    c.restore();

    final relleno = Paint()..color = const Color(0xFFDCE3F5);
    final bordeAla = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = const Color(0xFFA3B0D6);
    final lineas = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFA7B4DA);

    for (final s in [-1.0, 1.0]) {
      c.save();
      c.translate(dx / 2, 0);
      final yc = _cy + s * 292;
      final nac = _nacela(yc);
      c.drawPath(nac, Paint()..color = const Color(0xFFE6EBF9));
      c.drawPath(
        nac,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF8C99C4),
      );
      c.drawOval(Rect.fromCenter(center: Offset(1471, yc), width: 10, height: 92), Paint()..color = const Color(0xFF6C7AAB));
      c.drawOval(Rect.fromCenter(center: Offset(1259, yc), width: 14, height: 38), Paint()..color = const Color(0xFF7B88B4));

      // Ala con flaps, alerones y slats
      final ala = _trapecio(s, _lw, _tw, 60, 880);
      c.drawPath(ala, relleno);
      c.drawPath(ala, bordeAla);
      void seg(double f, double d0, double d1) {
        c.drawLine(Offset(_cp(_lw, _tw, d0, f), _cy + s * d0), Offset(_cp(_lw, _tw, d1, f), _cy + s * d1), lineas);
      }

      void tick(double d, double f0, double f1) {
        c.drawLine(Offset(_cp(_lw, _tw, d, f0), _cy + s * d), Offset(_cp(_lw, _tw, d, f1), _cy + s * d), lineas);
      }

      seg(.27, 106, 560);
      seg(.27, 610, 862);
      seg(.88, 112, 868);
      for (final d in [250.0, 400.0, 560.0, 612.0, 735.0, 862.0]) {
        tick(d, 0, .27);
      }
      for (final d in [230.0, 340.0, 470.0, 600.0, 720.0, 810.0]) {
        tick(d, .88, 1);
      }

      // Estabilizador horizontal
      c.translate(dx / 2, 0); // el estabilizador va con la cola
      final estab = _trapecio(s, _lh, _th, 40, 326);
      c.drawPath(estab, relleno);
      c.drawPath(estab, bordeAla);
      c.drawLine(
        Offset(_cp(_lh, _th, 70, .32), _cy + s * 70),
        Offset(_cp(_lh, _th, 318, .32), _cy + s * 318),
        lineas,
      );

      c.translate(-dx / 2, 0); // las luces van con las alas
      // Luces de navegación: roja a babor, verde a estribor
      final tx = _lw(880) - 4;
      final col = s < 0 ? const Color(0xFFFF4D5E) : const Color(0xFF2FD27A);
      c.drawCircle(Offset(tx, _cy + s * 876), 9, Paint()..color = col.withValues(alpha: .3));
      c.drawCircle(Offset(tx, _cy + s * 876), 3.6, Paint()..color = col);
      c.restore();
    }

    // Fuselaje
    c.drawPath(
      fusel,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFAEBAD9), Color(0xFFE3E8F6), Color(0xFFFFFFFF), Color(0xFFE3E8F6), Color(0xFFAEBAD9)],
          stops: [0, .1, .5, .9, 1],
        ).createShader(const Rect.fromLTRB(150, 797, 2126, 1003)),
    );
    c.drawCircle(const Offset(152, 900), 3, Paint()..color = Colors.white);

    // Deriva y salida de la APU (con la cola)
    c.save();
    c.translate(dx, 0);
    final aleta = Path()
      ..moveTo(205, 896.5)
      ..lineTo(560, 891.5)
      ..lineTo(650, 896)
      ..lineTo(650, 904)
      ..lineTo(560, 908.5)
      ..lineTo(205, 903.5)
      ..close();
    c.drawPath(aleta, Paint()..color = const Color(0xFFD3DAEE));
    c.drawRect(const Rect.fromLTWH(146, 888, 8, 24), Paint()..color = const Color(0xFF95A1C8));
    c.restore();

    // Interior de la cabina (recortado por el fuselaje)
    c.save();
    c.clipPath(fusel);
    _dibujarCabina(c);
    c.restore();

    // Ventanillas, puertas y salidas de emergencia
    final ventana = Paint()..color = const Color(0xFFB9C6E9);
    for (var r = 1; r <= _numFilas; r++) {
      final cx = filasX[r] + 17;
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 9, 800, 18, 5), const Radius.circular(2.5)), ventana);
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 9, 995, 18, 5), const Radius.circular(2.5)), ventana);
    }
    final puerta = Paint()..color = const Color(0xFFD2D8EE);
    final bordePuerta = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFF7783B3);
    for (final cx in [1845.0, 632.0].where((x) => x > cola + 40)) {
      for (final y in [797.0, 992.0]) {
        final rr = RRect.fromRectAndRadius(Rect.fromLTWH(cx - 21, y, 42, 11), const Radius.circular(2.5));
        c.drawRRect(rr, puerta);
        c.drawRRect(rr, bordePuerta);
      }
    }
    final hx = (filasX[_filasSalida[0]] + filasX[_filasSalida[1]]) / 2 + 17;
    for (final y in [797.5, 992.5]) {
      c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(hx - 10, y, 20, 10), const Radius.circular(2.5)),
        Paint()..color = const Color(0xFF2FB47A),
      );
    }

    c.drawPath(
      fusel,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFFA5B2D8),
    );
  }

  void _dibujarCabina(Canvas c) {
    void rect(double l, double t, double w, double h, Color col) => c.drawRect(Rect.fromLTWH(l, t, w, h), Paint()..color = col);

    void bloque(double x, double y, double w, double h) {
      final rr = RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), const Radius.circular(4));
      c.drawRRect(rr, Paint()..color = const Color(0xFFE6E9F5));
      c.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFFC3C9E2),
      );
    }

    void galera(double x, double y, double w, double h, int cols, int filas) {
      bloque(x, y, w, h);
      const gx = 5.0, gy = 5.0;
      final cw = (w - 2 * gx - (cols - 1) * 3) / cols;
      final ch = (h - 2 * gy - (filas - 1) * 3) / filas;
      for (var i = 0; i < cols; i++) {
        for (var j = 0; j < filas; j++) {
          final rr = RRect.fromRectAndRadius(
            Rect.fromLTWH(x + gx + i * (cw + 3), y + gy + j * (ch + 3), cw, ch),
            const Radius.circular(2.5),
          );
          c.drawRRect(rr, Paint()..color = const Color(0xFFF7F8FD));
        }
      }
    }

    rect(526, 780, 1640, 240, const Color(0xFFF2F3FA));
    rect(526, 808, 1440, 7, const Color(0xFFDFE2EF));
    rect(526, 985, 1440, 7, const Color(0xFFDFE2EF));
    rect(560, 887, 1400, 26, const Color(0xFFE4E7F3)); // pasillo
    rect(526, 780, 9, 240, const Color(0xFFBCC4DF)); // mamparo trasero
    bloque(582, 818, 68, 66);
    bloque(582, 916, 68, 66);
    galera(536, 868, 38, 64, 1, 2);
    bloque(1892, 818, 58, 66);
    galera(1872, 916, 78, 66, 3, 1);
    rect(1797, 815, 3, 72, const Color(0xFFC5CCE4));
    rect(1797, 913, 3, 72, const Color(0xFFC5CCE4));
    // Cabina de mando
    rect(1966, 780, 200, 240, const Color(0xFFDDE0EE));
    rect(1958, 780, 8, 92, const Color(0xFFCDD3E9));
    rect(1958, 928, 8, 92, const Color(0xFFCDD3E9));
    rect(2008, 862, 30, 28, const Color(0xFF8D96BB));
    rect(2008, 910, 30, 28, const Color(0xFF8D96BB));
    rect(2040, 893, 30, 14, const Color(0xFFAAB2D0));
  }

  // Números de fila, letras de columna y sanitarios (coordenadas de pantalla).
  void _dibujarDetalles(Canvas c) {
    final sanitarios = [
      [616.0, 851.0],
      [616.0, 949.0],
      [1921.0, 851.0],
    ];
    final cola = colaX(ultimaFila(asientos));
    for (final b in sanitarios.where((b) => b[0] > cola + 40)) {
      final x = _anchoPlano - b[0];
      final y = _altoPlano - b[1];
      c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x + 8, y - 6, 10, 12), const Radius.circular(2.5)),
        Paint()..color = Colors.white,
      );
      c.drawOval(Rect.fromCenter(center: Offset(x - 1, y), width: 22, height: 16), Paint()..color = Colors.white);
      c.drawOval(Rect.fromCenter(center: Offset(x - 1, y), width: 13, height: 8.6), Paint()..color = const Color(0xFFE4E8F5));
    }

    const estiloColumna = TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFFA9A6C0));
    for (var c_ = 0; c_ < _letras.length; c_++) {
      for (final x in [_anchoPlano - 1805, _anchoPlano - 640]) {
        _texto(c, _letras[c_], Offset(x, _yAsiento[c_] + 12), estiloColumna);
      }
    }
    const estiloFila = TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF9B99B4));
    final filas = asientos.fold<int>(0, (maximo, a) => math.max(maximo, a.fila));
    for (var r = 1; r <= filas; r++) {
      _texto(c, '$r', Offset(_anchoPlano - filasX[r] - 17, _cy), estiloFila);
    }
  }

  // Asiento visto desde arriba. Replica las capas del <symbol seatShape> del HTML ya espejadas
  // (el original se refleja con translate(34 0) scale(-1 1)): respaldo a la derecha, cojín, franjas,
  // costura, cinturón con hebilla y sombreado. Las coordenadas son relativas a la esquina del asiento.
  void _dibujarAsiento(Canvas c, Asiento a) {
    final x = a.x, y = a.y;
    final seleccionado = a.estado == EstadoAsiento.seleccionado;
    final reservado = a.estado == EstadoAsiento.reservado;

    final Color cuerpo, oscuro, claro;
    if (seleccionado) {
      cuerpo = const Color(0xFF1FA35B);
      oscuro = const Color(0xFF11713D);
      claro = const Color(0xFF4CD085);
    } else if (reservado) {
      cuerpo = Colors.white;
      oscuro = const Color(0xFFC4C9DA);
      claro = Colors.white;
    } else {
      cuerpo = const Color(0xFF111111);
      oscuro = Colors.black;
      claro = const Color(0xFF3B3B3B);
    }

    RRect rr(double l, double t, double w, double h, double r) =>
        RRect.fromRectAndRadius(Rect.fromLTWH(x + l, y + t, w, h), Radius.circular(r));
    Paint solido(Color col, [double opacidad = 1]) => Paint()..color = col.withValues(alpha: opacidad);

    // Sombreado vertical (gShadeY) y horizontal espejado (gShadeX) como en el HTML.
    void sombraY(RRect r) {
      c.drawRRect(
        r,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x3D000000), Color(0x33FFFFFF), Color(0x3D000000)],
            stops: [0, .45, 1],
          ).createShader(r.outerRect),
      );
    }

    void sombraX(RRect r) {
      c.drawRRect(
        r,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0x29FFFFFF), Color(0x00000000), Color(0x3D000000)],
            stops: [0, .4, 1],
          ).createShader(r.outerRect),
      );
    }

    // Sombra bajo el asiento
    c.drawRRect(rr(1.2, 1.4, 33, 23, 7), Paint()..color = const Color(0x292A2450));
    // Franjas superior e inferior del cojín y sus reflejos
    c.drawRRect(rr(1, -.3, 25, 4.6, 2.3), solido(oscuro));
    c.drawRRect(rr(1, 19.7, 25, 4.6, 2.3), solido(oscuro));
    c.drawRRect(rr(2.5, .5, 22, 2, 1), solido(claro, .7));
    c.drawRRect(rr(2.5, 21.5, 22, 2, 1), solido(claro, .7));
    // Cojín
    final cojin = rr(0, 3.6, 25, 16.8, 6.5);
    c.drawRRect(cojin, solido(cuerpo));
    sombraY(cojin);
    sombraX(cojin);
    if (reservado) {
      c.drawRRect(
        cojin,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .6
          ..color = const Color(0xFF9AA3C7),
      );
    }
    // Costura central punteada
    final costura = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7
      ..color = oscuro.withValues(alpha: .7);
    for (var yy = 4.6; yy < 19.4; yy += 3) {
      c.drawLine(Offset(x + 13, y + yy), Offset(x + 13, y + math.min(yy + 1.6, 19.4)), costura);
    }
    // Cinturón y hebilla (se ocultan al seleccionar, como en el HTML)
    if (!seleccionado) {
      final cinto = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFE6E9F3);
      c.drawLine(Offset(x + 15, y + 4.4), Offset(x + 9.5, y + 10.6), cinto);
      c.drawLine(Offset(x + 15, y + 19.6), Offset(x + 9.5, y + 13.4), cinto);
      final hebilla = rr(5, 10.4, 5.4, 3.2, .9);
      c.drawRRect(hebilla, solido(const Color(0xFFD9DDE9)));
      c.drawRRect(
        hebilla,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .5
          ..color = const Color(0xFF8E96B4),
      );
    }
    // Respaldo y su reflejo interior
    final respaldo = rr(21.2, 1, 12.8, 22, 5.2);
    c.drawRRect(respaldo, solido(oscuro));
    sombraY(respaldo);
    final reflejo = rr(26.9, 4.4, 6.2, 15.2, 3.1);
    c.drawRRect(reflejo, solido(claro));
    sombraY(reflejo);
    // Visto (✓ normal, en el lado opuesto al que tenía al estar reflejado)
    if (seleccionado) {
      final visto = Path()
        ..moveTo(x + 9.5, y + 11.5)
        ..lineTo(x + 12.5, y + 14.5)
        ..lineTo(x + 18.5, y + 8.5);
      c.drawPath(
        visto,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white,
      );
    }
  }

  // Nombre del propietario encima del asiento; no captura clics (se dibuja aparte).
  void _dibujarEtiquetas(Canvas c) {
    for (final a in asientos) {
      final nombre = a.nombre;
      if (a.estado == EstadoAsiento.disponible || nombre == null) continue;
      final seleccionado = a.estado == EstadoAsiento.seleccionado;
      final texto = nombre.length > 14 ? '${nombre.substring(0, 13)}…' : nombre;
      final tp = TextPainter(
        text: TextSpan(
          text: texto,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: seleccionado ? Colors.white : const Color(0xFF302D49),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final cx = a.x + 17;
      final w = tp.width + 12;
      final rect = Rect.fromLTWH(cx - w / 2, a.y - 17, w, 14);
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(7));
      c.drawRRect(
        rr,
        Paint()..color = seleccionado ? const Color(0xFF1FA35B) : Colors.white.withValues(alpha: .94),
      );
      c.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .6
          ..color = seleccionado ? const Color(0xFF11713D) : const Color(0xFFC9CDE0),
      );
      tp.paint(c, Offset(cx - tp.width / 2, rect.center.dy - tp.height / 2));
    }
  }

  void _texto(Canvas c, String t, Offset centro, TextStyle s) {
    final tp = TextPainter(text: TextSpan(text: t, style: s), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, centro - Offset(tp.width / 2, tp.height / 2));
  }
}
