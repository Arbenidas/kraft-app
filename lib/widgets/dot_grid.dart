import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/kraft_colors.dart';

/// Fondo técnico de puntos (equivalente al `radial-gradient` de Stitch).
/// Todos los puntos se envían en una sola llamada `drawRawPoints`.
class DotGridPainter extends CustomPainter {
  const DotGridPainter({this.spacing = 24, this.radius = 1.2, this.color});

  final double spacing;
  final double radius;

  /// Por defecto, los puntos de la paleta activa.
  final Color? color;

  @override
  void paint(Canvas canvas, Size size) {
    final cols = (size.width / spacing).ceil();
    final rows = (size.height / spacing).ceil();
    if (cols <= 0 || rows <= 0) return;

    final points = Float32List(cols * rows * 2);
    var i = 0;
    for (var r = 0; r < rows; r++) {
      final y = spacing / 2 + r * spacing;
      for (var c = 0; c < cols; c++) {
        points[i++] = spacing / 2 + c * spacing;
        points[i++] = y;
      }
    }
    canvas.drawRawPoints(
      ui.PointMode.points,
      points,
      Paint()
        ..color = color ?? KraftColors.dots
        ..strokeWidth = radius * 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(DotGridPainter old) =>
      old.spacing != spacing || old.radius != radius || old.color != color;
}

class DotGrid extends StatelessWidget {
  const DotGrid({super.key, this.spacing = 24, this.radius = 1.2, this.color});

  final double spacing;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return CustomPaint(
      painter: DotGridPainter(
        spacing: spacing,
        radius: radius,
        color: color ?? KraftColors.dots,
      ),
      child: const SizedBox.expand(),
    );
  }
}
