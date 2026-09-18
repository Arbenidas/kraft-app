import 'dart:math' as math;
import 'dart:ui';

/// El logotipo de KRAFT dibujado a mano: un lienzo con algo seleccionado y el cursor encima.
/// De aquí salen el icono de la app y `assets/images/logo.png`, así que hay una sola fuente.
abstract final class KraftLogo {
  static const yellow = Color(0xFFFFE600);
  static const ink = Color(0xFF1C1B1B);
  static const paper = Color(0xFFFCF9F8);

  /// Dibuja el logotipo ocupando un cuadrado de lado [size].
  ///
  /// [inset] es el margen transparente alrededor (0 = a sangre, como pide iOS;
  /// 0.09 deja el aire que espera el Dock de macOS).
  static void paint(Canvas canvas, double size, {double inset = 0}) {
    final margin = size * inset;
    final field = size - margin * 2;
    canvas.save();
    canvas.translate(margin, margin);

    // ---- Fondo amarillo ----
    // A sangre en iOS (la máscara de la app redondea) y con esquinas propias en macOS.
    final ground = Rect.fromLTWH(0, 0, field, field);
    final groundShape = inset == 0
        ? RRect.fromRectAndRadius(ground, Radius.zero)
        : RRect.fromRectAndRadius(ground, Radius.circular(field * 0.225));
    canvas.drawRRect(groundShape, Paint()..color = yellow);
    // El filo negro sólo en macOS: a sangre lo recortaría la máscara de iOS por las esquinas.
    if (inset > 0) {
      canvas.drawRRect(
        groundShape.deflate(field * 0.018),
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = field * 0.036,
      );
    }

    // ---- El lienzo: marco negro grueso y papel dentro ----
    final canvasRect = Rect.fromLTWH(
      field * 0.155,
      field * 0.155,
      field * 0.69,
      field * 0.69,
    );
    final canvasShape = RRect.fromRectAndRadius(
      canvasRect,
      Radius.circular(field * 0.075),
    );
    final frame = field * 0.055;
    canvas
      ..drawRRect(canvasShape, Paint()..color = paper)
      ..drawRRect(
        canvasShape.deflate(frame / 2),
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = frame,
      );

    // ---- La K, construida con barras: nítida a cualquier tamaño, sin depender de la fuente ----
    _paintK(canvas, field);

    // ---- El cursor, rompiendo el marco por abajo a la derecha ----
    _paintCursor(canvas, field);
    canvas.restore();
  }

  static void _paintK(Canvas canvas, double field) {
    final height = field * 0.34;
    final width = height * 0.80;
    final bar = width * 0.30;
    // Desplazada arriba a la izquierda: el cursor ocupa la esquina de abajo a la derecha.
    final left = field * 0.44 - width / 2;
    final top = field * 0.46 - height / 2;
    final pen = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = bar
      ..strokeCap = StrokeCap.butt;

    // Astil.
    canvas.drawLine(
      Offset(left + bar / 2, top),
      Offset(left + bar / 2, top + height),
      pen,
    );
    // Brazos: arrancan del astil y salen en diagonal.
    final joint = Offset(left + bar * 0.9, top + height * 0.52);
    canvas
      ..drawLine(joint, Offset(left + width, top + bar * 0.15), pen)
      ..drawLine(joint, Offset(left + width, top + height - bar * 0.15), pen);
  }

  static void _paintCursor(Canvas canvas, double field) {
    // Puntero clásico dibujado en una caja de 0 a 1 y llevado a su sitio.
    const shape = [
      Offset(0, 0),
      Offset(0, 0.76),
      Offset(0.21, 0.57),
      Offset(0.35, 0.93),
      Offset(0.53, 0.85),
      Offset(0.39, 0.50),
      Offset(0.66, 0.47),
    ];
    final scale = field * 0.215;
    final origin = Offset(field * 0.615, field * 0.575);
    final path = Path();
    for (final (i, p) in shape.indexed) {
      final at = origin + p * scale;
      i == 0 ? path.moveTo(at.dx, at.dy) : path.lineTo(at.dx, at.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = ink);
  }
}

/// Redondea al píxel más cercano para que los tamaños pequeños no salgan borrosos.
int px(double value) => math.max(1, value.round());
