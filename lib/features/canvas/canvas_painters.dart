import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/kraft_colors.dart';
import 'canvas_document.dart';
import 'canvas_models.dart';
import 'connector_geometry.dart';
import 'stroke_geometry.dart';

/// Trazos terminados. Sólo se repinta cuando cambia la lista, la selección o su desplazamiento;
/// nunca mientras se dibuja: el trazo en curso va en [LiveStrokePainter].
class StrokesPainter extends CustomPainter {
  final palette = KraftColors.active;
  StrokesPainter({
    required this.strokes,
    this.selected = const {},
    this.moveOffset = Offset.zero,
  });

  final List<Stroke> strokes;
  final Set<int> selected;

  /// Desplazamiento provisional de los trazos seleccionados mientras se arrastran.
  final Offset moveOffset;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      final isSelected = selected.contains(stroke.id);
      if (isSelected && moveOffset != Offset.zero) {
        canvas.save();
        canvas.translate(moveOffset.dx, moveOffset.dy);
      }
      if (isSelected) {
        // Halo amarillo bajo el trazo seleccionado.
        if (stroke.highlighter) {
          paintUniformStroke(
            canvas,
            stroke.points,
            _halo,
            stroke.paintedWidth + 10,
            false,
          );
        } else {
          stroke.haloOutline.paint(canvas, Paint()..color = _halo);
        }
      }
      if (stroke.highlighter) {
        paintUniformStroke(
          canvas,
          stroke.points,
          stroke.color,
          stroke.width,
          true,
        );
      } else {
        stroke.outline.paint(canvas, Paint()..color = stroke.color);
      }
      if (isSelected && moveOffset != Offset.zero) canvas.restore();
    }
  }

  // Getter y no `static final`: si no, el halo se queda con el color del tema
  // que estuviera activo la primera vez que se pintó una selección.
  static Color get _halo =>
      KraftColors.primaryContainer.withValues(alpha: 0.85);

  @override
  bool shouldRepaint(StrokesPainter old) =>
      old.palette != palette ||
      !identical(old.strokes, strokes) ||
      !setEquals(old.selected, selected) ||
      old.moveOffset != moveOffset;
}

/// Trazo en curso; escucha a [LiveStroke] directamente (sin setState).
class LiveStrokePainter extends CustomPainter {
  final palette = KraftColors.active;
  LiveStrokePainter(this.live) : super(repaint: live);

  final LiveStroke live;

  @override
  void paint(Canvas canvas, Size size) {
    if (!live.isActive) return;
    if (live.highlighter) {
      paintUniformStroke(canvas, live.points, live.color, live.width, true);
    } else {
      StrokeOutline.build(
        live.points,
        live.widths,
      ).paint(canvas, Paint()..color = live.color);
    }
  }

  @override
  bool shouldRepaint(LiveStrokePainter old) =>
      old.palette != palette || !identical(old.live, live);
}

/// Trazo de grosor constante con suavizado cuadrático (resaltador).
void paintUniformStroke(
  Canvas canvas,
  List<Offset> pts,
  Color color,
  double width,
  bool highlighter,
) {
  if (pts.isEmpty) return;

  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;
  if (highlighter) {
    paint
      ..color = color.withValues(alpha: 0.4)
      ..strokeWidth = width * 3
      ..strokeCap = StrokeCap.square
      ..blendMode = BlendMode.multiply;
  } else {
    paint
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
  }

  if (pts.length == 1) {
    canvas.drawCircle(
      pts.first,
      paint.strokeWidth / 2,
      paint..style = PaintingStyle.fill,
    );
    return;
  }

  final path = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (var i = 1; i < pts.length - 1; i++) {
    final mid = Offset(
      (pts[i].dx + pts[i + 1].dx) / 2,
      (pts[i].dy + pts[i + 1].dy) / 2,
    );
    path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
  }
  path.lineTo(pts.last.dx, pts.last.dy);
  canvas.drawPath(path, paint);
}

/// Fondo de puntos infinito, pintado en coordenadas de pantalla: sólo los puntos visibles,
/// alineados con el lienzo a cualquier desplazamiento y zoom.
class InfiniteDotGridPainter extends CustomPainter {
  final palette = KraftColors.active;
  InfiniteDotGridPainter(this.viewer) : super(repaint: viewer);

  final TransformationController viewer;

  /// Separación en coordenadas del lienzo.
  static const spacing = 24.0;

  /// Por debajo de esta separación en pantalla se salta un punto de cada dos (al alejar).
  static const _minScreenSpacing = 14.0;

  @override
  void paint(Canvas canvas, Size size) {
    final m = viewer.value;
    final scale = m.getMaxScaleOnAxis();
    final t = m.getTranslation();
    var step = spacing;
    while (step * scale < _minScreenSpacing) {
      step *= 2;
    }
    final screenStep = step * scale;

    final firstCol = (-t.x / screenStep).floor();
    final lastCol = ((size.width - t.x) / screenStep).ceil();
    final firstRow = (-t.y / screenStep).floor();
    final lastRow = ((size.height - t.y) / screenStep).ceil();
    final cols = lastCol - firstCol + 1;
    final rows = lastRow - firstRow + 1;
    if (cols <= 0 || rows <= 0 || cols * rows > 40000) return;

    final points = Float32List(cols * rows * 2);
    var i = 0;
    for (var r = firstRow; r <= lastRow; r++) {
      final y = t.y + r * screenStep;
      for (var c = firstCol; c <= lastCol; c++) {
        points[i++] = t.x + c * screenStep;
        points[i++] = y;
      }
    }
    canvas.drawRawPoints(
      ui.PointMode.points,
      points,
      Paint()
        ..color = KraftColors.dots
        ..strokeWidth = (2.4 * scale).clamp(1.6, 3.2)
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(InfiniteDotGridPainter old) =>
      old.palette != palette || !identical(old.viewer, viewer);
}

/// Conexiones entre elementos. Cada extremo sale del contorno del elemento hacia el otro,
/// así que al mover cualquiera la línea se recoloca sola.
class LinksPainter extends CustomPainter {
  final palette = KraftColors.active;
  LinksPainter(this.document, {required this.scale}) : super(repaint: document);

  final CanvasDocument document;

  /// Escala de la vista: el halo de selección mantiene grosor en pantalla.
  final double scale;

  // Se crean en cada pintado: cacheados se quedaban con la tinta del tema anterior.
  static Paint get _line => Paint()
    ..color = KraftColors.ink
    ..strokeWidth = 2.5
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  static Paint get _head => Paint()..color = KraftColors.ink;

  @override
  void paint(Canvas canvas, Size size) {
    final selected = document.selectedLink?.id;
    // Una vez por pintado, no una por conexión, pero leyendo el tema de ahora.
    final linePaint = _line;
    final headPaint = _head;
    for (final link in document.links) {
      final g = document.linkGeometry(link);
      if (g == null) continue;
      if (link.id == selected) {
        final halo = Paint()
          ..color = KraftColors.primaryContainer
          ..strokeWidth = 2.5 + 12 / scale
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        canvas.drawPath(g.line, halo);
        for (final head in g.heads()) {
          canvas.drawPath(head, halo..style = PaintingStyle.stroke);
        }
      }
      canvas.drawPath(g.line, linePaint);
      for (final head in g.heads()) {
        canvas.drawPath(head, headPaint);
      }
      if (link.label.isNotEmpty)
        paintLinkLabel(canvas, g.mid + link.labelOffset, link.label);
    }
  }

  @override
  bool shouldRepaint(LinksPainter old) =>
      old.palette != palette || old.document != document || old.scale != scale;
}

/// Etiqueta de conexión: píldora blanca con borde de tinta, centrada en [center].
void paintLinkLabel(Canvas canvas, Offset center, String label) {
  final text = TextPainter(
    text: TextSpan(
      text: label.toUpperCase(),
      style: TextStyle(
        fontFamily: 'JetBrains Mono',
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: KraftColors.ink,
        letterSpacing: 0.6,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: 180);
  final box = RRect.fromRectAndRadius(
    Rect.fromCenter(
      center: center,
      width: text.width + 14,
      height: text.height + 8,
    ),
    const Radius.circular(4),
  );
  canvas
    ..drawRRect(box.shift(const Offset(2, 2)), Paint()..color = KraftColors.ink)
    ..drawRRect(box, Paint()..color = KraftColors.surfaceContainerLowest)
    ..drawRRect(
      box,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = KraftColors.ink,
    );
  text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
}

/// Conector mientras se arrastra desde el tirador: línea discontinua hasta el lápiz
/// o, sobre otro elemento, la conexión definitiva y el destino resaltado.
class ConnectorPreviewPainter extends CustomPainter {
  final palette = KraftColors.active;
  ConnectorPreviewPainter(this.document, this.drag, {required this.scale})
    : super(repaint: drag);

  final CanvasDocument document;
  final ValueListenable<ConnectorDrag?> drag;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final state = drag.value;
    if (state == null) return;
    final from = document.itemById(state.fromId);
    if (from == null) return;
    final target = state.targetId == null
        ? null
        : document.itemById(state.targetId!);

    final geometry = target != null
        ? linkBetween(
            from: from,
            fromRect: document.itemRect(from),
            to: target,
            toRect: document.itemRect(target),
          )
        : linkToPoint(
            from: from,
            fromRect: document.itemRect(from),
            point: state.point,
          );

    if (target != null) {
      final rect = document.itemRect(target).inflate(8 / scale);
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(8 / scale));
      canvas
        ..drawRRect(
          rrect,
          Paint()..color = KraftColors.primaryContainer.withValues(alpha: 0.25),
        )
        ..drawRRect(
          rrect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3 / scale
            ..color = KraftColors.ink,
        );
    }
    if (geometry == null) return;

    final paint = Paint()
      ..color = KraftColors.ink
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    if (target != null) {
      canvas.drawPath(geometry.line, paint);
    } else {
      for (final metric in geometry.line.computeMetrics()) {
        for (var d = 0.0; d < metric.length; d += 12) {
          canvas.drawPath(metric.extractPath(d, d + 7), paint);
        }
      }
    }
    for (final head in geometry.heads()) {
      canvas.drawPath(head, Paint()..color = KraftColors.ink);
    }
    if (target == null) {
      canvas
        ..drawCircle(
          state.point,
          7 / scale,
          Paint()..color = KraftColors.primaryContainer,
        )
        ..drawCircle(
          state.point,
          7 / scale,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 / scale
            ..color = KraftColors.ink,
        );
    }
  }

  @override
  bool shouldRepaint(ConnectorPreviewPainter old) =>
      old.palette != palette ||
      old.document != document ||
      old.drag != drag ||
      old.scale != scale;
}

/// Arrastre del conector: elemento de origen, punto del lienzo bajo el lápiz y destino si lo hay.
@immutable
class ConnectorDrag {
  const ConnectorDrag({
    required this.fromId,
    required this.point,
    this.targetId,
  });

  final String fromId;
  final Offset point;
  final String? targetId;
}

/// Boceto de wireframe a mano con borde discontinuo (grupo SVG de Stitch).
class WireframeSketchPainter extends CustomPainter {
  final palette = KraftColors.active;
  WireframeSketchPainter();

  static const size = Size(280, 210);

  @override
  void paint(Canvas canvas, Size size) {
    final teal = KraftColors.tertiary;
    final outer = RRect.fromRectAndRadius(
      Offset.zero & WireframeSketchPainter.size,
      const Radius.circular(10),
    );
    canvas.drawRRect(outer, Paint()..color = Colors.white);
    _drawDashed(
      canvas,
      Path()..addRRect(outer),
      Paint()
        ..color = teal
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );

    final inner = RRect.fromRectAndRadius(
      const Rect.fromLTWH(12, 36, 256, 160),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      inner,
      Paint()..color = KraftColors.tertiaryContainer.withValues(alpha: 0.15),
    );
    final stroke = Paint()
      ..color = teal
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(inner, stroke);
    canvas.drawCircle(const Offset(140, 18), 3, Paint()..color = teal);

    stroke.strokeWidth = 1.8;
    canvas
      ..drawLine(const Offset(28, 56), const Offset(84, 56), stroke)
      ..drawLine(const Offset(28, 70), const Offset(60, 70), stroke)
      ..drawLine(const Offset(28, 90), const Offset(252, 170), stroke)
      ..drawLine(const Offset(28, 170), const Offset(252, 90), stroke);
  }

  void _drawDashed(Canvas canvas, Path path, Paint paint) {
    for (final ui.PathMetric metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 5), paint);
        distance += 8;
      }
    }
  }

  @override
  bool shouldRepaint(WireframeSketchPainter old) =>
      old.palette != palette || false;
}
