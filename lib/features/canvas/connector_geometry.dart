import 'dart:math' as math;
import 'dart:ui';

import 'canvas_models.dart';

/// Punto del contorno de un elemento y la normal hacia fuera en ese punto.
typedef OutlinePoint = ({Offset point, Offset normal});

/// Separación entre el contorno del elemento y el extremo de la línea.
const _gap = 6.0;
const arrowHeadLength = 13.0;

/// Dónde sale del contorno de [item] (ocupando [rect]) la recta desde su centro hacia [toward].
/// Respeta la forma: rectángulos y tarjetas por su lado, círculos, rombos y triángulos por su silueta.
OutlinePoint outlinePoint(CanvasItem item, Rect rect, Offset toward) {
  // Las formas rellenas dejan 4 pt de sombra dura a la derecha y abajo.
  final body = item.type == CanvasItemType.shape && !item.shape.isStroke
      ? Rect.fromLTWH(
          rect.left,
          rect.top,
          math.max(1, rect.width - 4),
          math.max(1, rect.height - 4),
        )
      : rect;
  final c = body.center;
  final d = toward - c;
  if (d.distanceSquared < 1e-6) return (point: c, normal: const Offset(1, 0));
  final a = body.width / 2, b = body.height / 2;

  if (item.type == CanvasItemType.shape) {
    switch (item.shape) {
      case ShapeKind.ellipse:
        final t = 1 / math.sqrt(d.dx * d.dx / (a * a) + d.dy * d.dy / (b * b));
        final p = c + d * t;
        return (
          point: p,
          normal: _unit(
            Offset((p.dx - c.dx) / (a * a), (p.dy - c.dy) / (b * b)),
          ),
        );
      case ShapeKind.diamond:
        final t = 1 / (d.dx.abs() / a + d.dy.abs() / b);
        return (
          point: c + d * t,
          normal: _unit(Offset(d.dx.sign / a, d.dy.sign / b)),
        );
      case ShapeKind.triangle:
        final hit = _rayPolygon(c, d, [
          Offset(body.center.dx, body.top),
          body.bottomRight,
          body.bottomLeft,
        ]);
        if (hit != null) return hit;
      default:
        break;
    }
  }

  // Rectángulo: el lado que corta primero la recta.
  final tx = d.dx == 0 ? double.infinity : a / d.dx.abs();
  final ty = d.dy == 0 ? double.infinity : b / d.dy.abs();
  return tx < ty
      ? (point: c + d * tx, normal: Offset(d.dx.sign, 0))
      : (point: c + d * ty, normal: Offset(0, d.dy.sign));
}

OutlinePoint? _rayPolygon(Offset origin, Offset dir, List<Offset> vertices) {
  double? best;
  Offset? normal;
  for (var i = 0; i < vertices.length; i++) {
    final p = vertices[i], q = vertices[(i + 1) % vertices.length];
    final e = q - p;
    final denom = dir.dx * e.dy - dir.dy * e.dx;
    if (denom.abs() < 1e-9) continue;
    final w = p - origin;
    final t = (w.dx * e.dy - w.dy * e.dx) / denom;
    final u = (w.dx * dir.dy - w.dy * dir.dx) / denom;
    if (t > 0 && u >= 0 && u <= 1 && (best == null || t < best)) {
      best = t;
      var n = _unit(Offset(e.dy, -e.dx));
      // La normal apunta hacia fuera: en sentido contrario al centro.
      if ((n.dx * w.dx + n.dy * w.dy) < 0) n = -n;
      normal = n;
    }
  }
  return best == null ? null : (point: origin + dir * best, normal: normal!);
}

Offset _unit(Offset v) {
  final l = v.distance;
  return l == 0 ? const Offset(1, 0) : v / l;
}

/// Trazado listo para pintar y tocar.
class LinkGeometry {
  LinkGeometry._(
    this.line,
    this.start,
    this.end,
    this.startTangent,
    this.endTangent,
    this.mid,
    this.arrow,
    this.control,
  );

  /// Línea ya recortada para dejar sitio a las puntas.
  final Path line;
  final Offset start;
  final Offset end;

  /// Dirección de la línea al salir de [start] y al llegar a [end].
  final Offset startTangent;
  final Offset endTangent;

  /// Centro del recorrido: ahí va la etiqueta.
  final Offset mid;
  final LinkArrow arrow;

  /// Punto de ruta elegido manualmente, si lo hay.
  final Offset? control;

  late final List<Offset> _samples = _sample();

  List<Offset> _sample() {
    final points = <Offset>[];
    for (final metric in line.computeMetrics()) {
      for (var d = 0.0; d <= metric.length; d += 6) {
        points.add(metric.getTangentForOffset(d)!.position);
      }
    }
    return [start, ...points, end];
  }

  bool hits(Offset point, double tolerance) {
    final r2 = tolerance * tolerance;
    for (var i = 0; i + 1 < _samples.length; i++) {
      if (_distanceToSegmentSquared(point, _samples[i], _samples[i + 1]) <= r2)
        return true;
    }
    return false;
  }

  /// Triángulos de las puntas (tip, base izquierda, base derecha).
  List<Path> heads({double length = arrowHeadLength}) => [
    if (arrow != LinkArrow.none) _head(end, endTangent, length),
    if (arrow == LinkArrow.both) _head(start, -startTangent, length),
  ];

  static Path _head(Offset tip, Offset direction, double length) {
    final back = tip - direction * length;
    final side = Offset(-direction.dy, direction.dx) * (length * 0.5);
    return Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(back.dx + side.dx, back.dy + side.dy)
      ..lineTo(back.dx - side.dx, back.dy - side.dy)
      ..close();
  }
}

double _distanceToSegmentSquared(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.distanceSquared;
  if (len2 == 0) return (p - a).distanceSquared;
  final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2).clamp(
    0.0,
    1.0,
  );
  return (p - (a + ab * t)).distanceSquared;
}

/// Conexión entre dos elementos: cada extremo sale del contorno mirando al centro del otro,
/// así la línea se recoloca sola al mover cualquiera de los dos.
LinkGeometry? linkBetween({
  required CanvasItem from,
  required Rect fromRect,
  required CanvasItem to,
  required Rect toRect,
  LinkStyle style = LinkStyle.curved,
  LinkArrow arrow = LinkArrow.end,
  Offset? bend,
}) {
  if (fromRect.overlaps(toRect)) return null;
  final a = outlinePoint(from, fromRect, toRect.center);
  final b = outlinePoint(to, toRect, fromRect.center);
  return _build(
    start: a.point + a.normal * _gap,
    startNormal: a.normal,
    end: b.point + b.normal * _gap,
    endNormal: b.normal,
    style: style,
    arrow: arrow,
    bend: bend,
  );
}

/// Vista previa mientras se arrastra el conector hacia un punto libre.
LinkGeometry? linkToPoint({
  required CanvasItem from,
  required Rect fromRect,
  required Offset point,
}) {
  if (fromRect.inflate(_gap).contains(point)) return null;
  final a = outlinePoint(from, fromRect, point);
  return _build(
    start: a.point + a.normal * _gap,
    startNormal: a.normal,
    end: point,
    endNormal: _unit(a.point - point),
    style: LinkStyle.curved,
    arrow: LinkArrow.end,
  );
}

LinkGeometry? _build({
  required Offset start,
  required Offset startNormal,
  required Offset end,
  required Offset endNormal,
  required LinkStyle style,
  required LinkArrow arrow,
  Offset? bend,
}) {
  final distance = (end - start).distance;
  if (distance < arrowHeadLength * 1.5) return null;

  final full = Path()..moveTo(start.dx, start.dy);
  if (bend != null) {
    if (style == LinkStyle.straight) {
      full
        ..lineTo(bend.dx, bend.dy)
        ..lineTo(end.dx, end.dy);
    } else {
      final first = (bend - start).distance;
      final second = (end - bend).distance;
      final c1 = start + startNormal * (first * .35).clamp(16.0, 120.0);
      final c2 = bend - (bend - start) * .25;
      final c3 = bend + (end - bend) * .25;
      final c4 = end + endNormal * (second * .35).clamp(16.0, 120.0);
      full
        ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, bend.dx, bend.dy)
        ..cubicTo(c3.dx, c3.dy, c4.dx, c4.dy, end.dx, end.dy);
    }
  } else if (style == LinkStyle.curved) {
    final k = (distance * 0.4).clamp(24.0, 160.0);
    final c1 = start + startNormal * k;
    final c2 = end + endNormal * k;
    full.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
  } else {
    full.lineTo(end.dx, end.dy);
  }

  final metric = full.computeMetrics().first;
  final length = metric.length;
  final startTangent = _unit(metric.getTangentForOffset(0)!.vector);
  final endTangent = _unit(metric.getTangentForOffset(length)!.vector);
  // La línea se detiene bajo la punta para que el trazo no asome por delante.
  final trimEnd = arrow == LinkArrow.none ? 0.0 : arrowHeadLength * 0.7;
  final trimStart = arrow == LinkArrow.both ? arrowHeadLength * 0.7 : 0.0;
  final line = metric.extractPath(
    trimStart,
    math.max(trimStart, length - trimEnd),
  );

  return LinkGeometry._(
    line,
    start,
    end,
    startTangent,
    endTangent,
    metric.getTangentForOffset(length / 2)!.position,
    arrow,
    bend,
  );
}
