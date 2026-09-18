import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'kraft_logo.dart';

/// Hoja de contactos: el icono a los tamaños chicos, ampliado sin suavizar,
/// para ver si se sigue leyendo. `flutter test tool/preview_icons.dart`
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('hoja de contactos', () async {
    const sizes = [16, 20, 29, 40, 64, 128];
    const zoom = 5.0;
    const gap = 16.0;
    final scaled = [for (final s in sizes) s * zoom];
    final width = scaled.fold(gap, (a, b) => a + b + gap);
    final height = scaled.last + gap * 2;

    Future<ui.Image> render(int size, double inset) async {
      final recorder = ui.PictureRecorder();
      KraftLogo.paint(ui.Canvas(recorder), size.toDouble(), inset: inset);
      return recorder.endRecording().toImage(size, size);
    }

    for (final (name, inset) in [('ios', 0.0), ('macos', 0.09)]) {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, width, height),
        ui.Paint()..color = const ui.Color(0xFF8A8A8A),
      );
      var x = gap;
      for (final size in sizes) {
        final image = await render(size, inset);
        canvas.drawImageRect(
          image,
          ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
          ui.Rect.fromLTWH(x, gap, size * zoom, size * zoom),
          ui.Paint()..filterQuality = ui.FilterQuality.none,
        );
        image.dispose();
        x += size * zoom + gap;
      }
      final sheet = await recorder.endRecording().toImage(
        width.round(),
        height.round(),
      );
      final data = await sheet.toByteData(format: ui.ImageByteFormat.png);
      final out = Directory('build/icon-preview')..createSync(recursive: true);
      await File(
        '${out.path}/$name.png',
      ).writeAsBytes(data!.buffer.asUint8List());
    }
  });
}
