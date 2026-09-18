import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';

/// Presión y grosor de los trazos.
abstract final class StrokePressure {
  /// Grosor con presión mínima y máxima, como múltiplo del grosor elegido en la paleta.
  static const minFactor = 0.3;
  static const maxFactor = 1.8;

  /// Suavizado exponencial entre muestras (0 = sin cambios, 1 = sin suavizar).
  static const smoothing = 0.4;

  /// Presión normalizada 0–1, o `null` si el puntero no mide presión.
  /// Sólo el Apple Pencil la reporta de verdad: el dedo y el ratón envían siempre el máximo.
  static double? normalized(PointerEvent e) {
    final pencil = e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus;
    final range = e.pressureMax - e.pressureMin;
    if (!pencil || range <= 0) return null;
    return ((e.pressure - e.pressureMin) / range).clamp(0.0, 1.0);
  }

  /// Grosor para una presión normalizada. La curva (^0.75) da más control en la zona ligera,
  /// donde se escribe normalmente; la presión media (~0.35) queda cerca del grosor base.
  static double widthFor(double base, double pressure) =>
      base * (minFactor + (maxFactor - minFactor) * math.pow(pressure, 0.75));

  static double smooth(double previous, double sample) => previous + (sample - previous) * smoothing;
}

/// Contorno relleno de un trazo de grosor variable: cuerpo + tapas redondas en los extremos.
class StrokeOutline {
  StrokeOutline(this.body, this.caps);

  final Path body;

  /// (centro, radio) de las tapas inicial y final; se pintan aparte para evitar agujeros de relleno.
  final List<(Offset, double)> caps;

  void paint(Canvas canvas, Paint fill) {
    canvas.drawPath(body, fill);
    for (final (center, radius) in caps) {
      canvas.drawCircle(center, radius, fill);
    }
  }

  /// Construye el contorno a partir de puntos y grosores (misma longitud). [extra] ensancha todo por igual (halo).
  static StrokeOutline build(List<Offset> points, List<double> widths, {double extra = 0}) {
    assert(points.length == widths.length);
    final n = points.length;
    final body = Path();
    if (n == 0) return StrokeOutline(body, const []);
    double half(int i) => (widths[i] + extra) / 2;
    if (n == 1) return StrokeOutline(body, [(points.first, half(0))]);

    final left = <Offset>[];
    final right = <Offset>[];
    var normal = const Offset(0, 1);
    for (var i = 0; i < n; i++) {
      final tangent = points[math.min(i + 1, n - 1)] - points[math.max(i - 1, 0)];
      final length = tangent.distance;
      // Puntos repetidos: se conserva la normal anterior.
      if (length > 1e-6) normal = Offset(-tangent.dy / length, tangent.dx / length);
      left.add(points[i] + normal * half(i));
      right.add(points[i] - normal * half(i));
    }

    body.moveTo(left.first.dx, left.first.dy);
    _smoothThrough(body, left);
    body.lineTo(right.last.dx, right.last.dy);
    _smoothThrough(body, right.reversed.toList());
    body.close();

    return StrokeOutline(body, [(points.first, half(0)), (points.last, half(n - 1))]);
  }

  /// Curva cuadrática por los puntos medios (el primer punto ya es la posición actual).
  static void _smoothThrough(Path path, List<Offset> pts) {
    for (var i = 1; i < pts.length - 1; i++) {
      final mid = Offset((pts[i].dx + pts[i + 1].dx) / 2, (pts[i].dy + pts[i + 1].dy) / 2);
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
  }
}
