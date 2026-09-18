import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'kraft_logo.dart';

/// Genera el icono de la app y el logotipo de la barra superior.
/// Se ejecuta a mano cuando cambia la marca:
///
///     flutter test tool/make_icons.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('genera los iconos de KRAFT', () async {
    Future<void> write(String path, int size, {double inset = 0}) async {
      final recorder = ui.PictureRecorder();
      KraftLogo.paint(
        ui.Canvas(recorder),
        size.toDouble(),
        inset: inset,
      );
      final image = await recorder.endRecording().toImage(size, size);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      await File(path).writeAsBytes(data!.buffer.asUint8List());
    }

    // ---- iOS: a sangre, iOS ya redondea ----
    const ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    const iphone = {
      'Icon-App-20x20@1x.png': 20,
      'Icon-App-20x20@2x.png': 40,
      'Icon-App-20x20@3x.png': 60,
      'Icon-App-29x29@1x.png': 29,
      'Icon-App-29x29@2x.png': 58,
      'Icon-App-29x29@3x.png': 87,
      'Icon-App-40x40@1x.png': 40,
      'Icon-App-40x40@2x.png': 80,
      'Icon-App-40x40@3x.png': 120,
      'Icon-App-60x60@2x.png': 120,
      'Icon-App-60x60@3x.png': 180,
      'Icon-App-76x76@1x.png': 76,
      'Icon-App-76x76@2x.png': 152,
      'Icon-App-83.5x83.5@2x.png': 167,
      'Icon-App-1024x1024@1x.png': 1024,
    };
    for (final MapEntry(key: name, value: size) in iphone.entries) {
      await write('$ios/$name', size);
    }

    // ---- macOS: con el aire que deja el Dock alrededor ----
    const mac = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
    for (final size in [16, 32, 64, 128, 256, 512, 1024]) {
      await write('$mac/app_icon_$size.png', size, inset: 0.09);
    }

    // ---- El logotipo de dentro de la app (la barra superior lo recorta) ----
    await write('assets/images/logo.png', 512);

    // ---- Pantalla de arranque de iOS: sobre blanco, con sus esquinas ----
    const launch = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';
    for (final (name, size) in [
      ('LaunchImage.png', 160),
      ('LaunchImage@2x.png', 320),
      ('LaunchImage@3x.png', 480),
    ]) {
      await write('$launch/$name', size, inset: 0.09);
    }

    // ---- Una hoja de contactos para mirar cómo queda a cada tamaño ----
    expect(File('$ios/Icon-App-1024x1024@1x.png').existsSync(), isTrue);
    expect(File('$mac/app_icon_1024.png').existsSync(), isTrue);
    expect(File('assets/images/logo.png').existsSync(), isTrue);
  });
}
