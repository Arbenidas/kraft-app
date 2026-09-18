import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kraft/features/canvas/canvas_document.dart';
import 'package:kraft/features/canvas/canvas_models.dart';
import 'package:kraft/features/canvas/canvas_painters.dart';

import 'helpers.dart';

const _node1 = '1. REGISTRO MÓVIL';

Future<void> _drag(WidgetTester tester, List<Offset> path, PointerDeviceKind kind, {int pointer = 1}) async {
  final g = await tester.startGesture(path.first, kind: kind, pointer: pointer);
  for (final p in path.skip(1)) {
    await g.moveTo(p);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await g.up();
  await tester.pumpAndSettle();
}

List<Stroke> _strokes(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((c) => c.painter)
    .whereType<StrokesPainter>()
    .single
    .strokes;

Stroke _line(CanvasDocument doc, Offset from, Offset to) => Stroke(
      id: doc.allocateStrokeId(),
      points: [for (var i = 0; i <= 20; i++) Offset.lerp(from, to, i / 20)!],
      color: const Color(0xFF000000),
      width: 4,
    );

void main() {
  testWidgets('con el lápiz activo el dedo no dibuja: selecciona y mueve elementos', (tester) async {
    await pumpKraft(tester, size: const Size(1366, 1024));
    await openCanvasEditor(tester);
    await tester.tap(toolButton('Lápiz / Trazo libre'));
    await tester.pumpAndSettle();

    // Dedo en vacío: desplaza, no deja trazo.
    await _drag(tester, [for (var i = 0; i <= 5; i++) Offset(1000.0 - i * 20, 700)], PointerDeviceKind.touch, pointer: 2);
    expect(_strokes(tester), isEmpty);

    // Select with a completed tap first; only then does dragging move the item.
    await tester.tap(find.text(_node1));
    await tester.pumpAndSettle();
    final before = tester.getRect(find.text(_node1));
    await _drag(tester, [for (var i = 0; i <= 6; i++) before.center + Offset(0, 15.0 * i)], PointerDeviceKind.touch, pointer: 3);
    expect(tester.getRect(find.text(_node1)).top - before.top, closeTo(90, 0.5));
    expect(find.text('1 SELECCIONADO'), findsOneWidget);
    expect(_strokes(tester), isEmpty);

    // El lápiz sigue dibujando.
    await _drag(tester, [for (var i = 0; i <= 6; i++) Offset(900.0 + i * 20, 800)], PointerDeviceKind.stylus, pointer: 4);
    expect(_strokes(tester), hasLength(1));
  });

  testWidgets('"Dibujar con el dedo" hace que el dedo use la herramienta', (tester) async {
    await pumpKraft(tester, size: const Size(1366, 1024));
    await openCanvasEditor(tester);
    await tester.tap(toolButton('Lápiz / Trazo libre'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sólo el Apple Pencil dibuja; el dedo selecciona y mueve'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pumpAndSettle();

    await _drag(tester, [for (var i = 0; i <= 6; i++) Offset(900.0 + i * 20, 700)], PointerDeviceKind.touch, pointer: 5);
    expect(_strokes(tester), hasLength(1));
  });

  group('borrador', () {
    CanvasDocument doc() => CanvasDocument(items: const [
          CanvasItem(id: 'card-1', type: CanvasItemType.card, position: Offset(0, 300)),
        ]);

    test('parcial corta el trazo en dos y se deshace de una vez', () {
      final d = doc();
      final stroke = _line(d, const Offset(0, 0), const Offset(200, 0));
      d
        ..addStroke(stroke)
        ..beginErase()
        ..erasePartialAt(const Offset(100, 0), 8)
        ..erasePartialAt(const Offset(104, 0), 8);
      expect(d.strokes, hasLength(2));
      expect(d.strokes.every((s) => s.points.every((p) => (p.dx - 100).abs() > 8)), isTrue);
      d.undo();
      expect(d.strokes.single.id, stroke.id);
    });

    test('por trazo borra el trazo entero y por elemento sólo elementos', () {
      final d = doc()..addStroke(_line(CanvasDocument(), const Offset(0, 0), const Offset(200, 0)));
      d
        ..beginErase()
        ..eraseItemsAt(const Offset(100, 0), 8);
      expect(d.strokes, hasLength(1), reason: 'el modo elemento no toca trazos');

      d
        ..beginErase()
        ..eraseItemsAt(const Offset(40, 340), 8);
      expect(d.items, isEmpty);

      d
        ..beginErase()
        ..eraseAt(const Offset(100, 0), 8);
      expect(d.strokes, isEmpty);
      d.undo();
      d.undo();
      expect(d.items, hasLength(1));
      expect(d.strokes, hasLength(1));
    });
  });
}
