import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kraft/features/canvas/canvas_models.dart';
import 'package:kraft/features/canvas/canvas_painters.dart';
import 'package:kraft/features/canvas/stroke_geometry.dart';

import 'helpers.dart';

void main() {
  group('StrokePressure', () {
    test('sólo el Apple Pencil aporta presión normalizada', () {
      const pencil = PointerDownEvent(kind: PointerDeviceKind.stylus, pressure: 2, pressureMin: 0, pressureMax: 4);
      const finger = PointerDownEvent(kind: PointerDeviceKind.touch, pressure: 1, pressureMin: 0, pressureMax: 1);
      const noRange = PointerDownEvent(kind: PointerDeviceKind.stylus, pressure: 1, pressureMin: 1, pressureMax: 1);

      expect(StrokePressure.normalized(pencil), 0.5);
      expect(StrokePressure.normalized(finger), isNull);
      expect(StrokePressure.normalized(noRange), isNull);
    });

    test('el grosor crece con la presión entre 0.3x y 1.8x', () {
      expect(StrokePressure.widthFor(4, 0), closeTo(1.2, 1e-9));
      expect(StrokePressure.widthFor(4, 1), closeTo(7.2, 1e-9));
      expect(StrokePressure.widthFor(4, 0.6), greaterThan(StrokePressure.widthFor(4, 0.3)));
    });
  });

  group('LiveStroke', () {
    test('suaviza la presión y la conserva al terminar', () {
      final live = LiveStroke()
        ..start(Offset.zero, color: const Color(0xFF000000), width: 4, highlighter: false, pressure: 0)
        ..add(const Offset(10, 0), pressure: 1)
        ..add(const Offset(20, 0), pressure: 1);

      expect(live.pressure, closeTo(0.64, 1e-9)); // 0 → 0.4 → 0.64
      final stroke = live.finish(1)!;
      expect(stroke.pressures, [0, closeTo(0.4, 1e-9), closeTo(0.64, 1e-9)]);
      expect(stroke.widths.first, lessThan(stroke.widths.last));
    });

    test('el resaltador y los punteros sin presión dibujan con grosor uniforme', () {
      final marker = LiveStroke()
        ..start(Offset.zero, color: const Color(0xFF000000), width: 4, highlighter: true, pressure: 0.2);
      expect(marker.usesPressure, isFalse);

      final finger = LiveStroke()..start(Offset.zero, color: const Color(0xFF000000), width: 4, highlighter: false);
      finger.add(const Offset(30, 0), pressure: 0.9);
      expect(finger.finish(1)!.pressures, isNull);
    });
  });

  testWidgets('en el lienzo, más presión da un trazo más grueso', (tester) async {
    await pumpKraft(tester, size: const Size(1366, 1024));
    await openCanvasEditor(tester);
    await tester.tap(toolButton('Lápiz / Trazo libre'));
    await tester.pumpAndSettle();

    Future<void> pencilLine(int pointer, double y, double pressure) async {
      for (var i = 0; i <= 10; i++) {
        final position = Offset(700.0 + i * 20, y);
        final common = (pressure: pressure, pressureMin: 0.0, pressureMax: 1.0);
        tester.binding.handlePointerEvent(i == 0
            ? PointerDownEvent(
                pointer: pointer,
                position: position,
                kind: PointerDeviceKind.stylus,
                pressure: common.pressure,
                pressureMin: common.pressureMin,
                pressureMax: common.pressureMax,
              )
            : PointerMoveEvent(
                pointer: pointer,
                position: position,
                kind: PointerDeviceKind.stylus,
                pressure: common.pressure,
                pressureMin: common.pressureMin,
                pressureMax: common.pressureMax,
              ));
        await tester.pump(const Duration(milliseconds: 16));
      }
      tester.binding.handlePointerEvent(
        PointerUpEvent(pointer: pointer, position: Offset(900, y), kind: PointerDeviceKind.stylus),
      );
      await tester.pumpAndSettle();
    }

    await pencilLine(21, 420, 0.1);
    await pencilLine(22, 500, 0.9);

    final strokes = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<StrokesPainter>()
        .single
        .strokes;
    expect(strokes, hasLength(2));
    expect(strokes.every((s) => s.hasPressure), isTrue);
    expect(strokes[1].bounds.height, greaterThan(strokes[0].bounds.height * 2));

    // Al dibujar, la paleta se hizo bolita en una esquina (en vertical): se despliega para desactivar la presión.
    await tester.tap(find.bySemanticsLabel('Mostrar herramientas'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Presión del lápiz'));
    await tester.pumpAndSettle();
    await pencilLine(23, 580, 0.9);
    final all = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<StrokesPainter>()
        .single
        .strokes;
    expect(all, hasLength(3));
    final last = all.last;
    expect(last.hasPressure, isFalse);
    expect(last.paintedWidth, 4);
  });
}
