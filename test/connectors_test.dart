import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kraft/data/db/database.dart';
import 'package:kraft/features/canvas/canvas_codec.dart';
import 'package:kraft/features/canvas/canvas_document.dart';
import 'package:kraft/features/canvas/canvas_models.dart';
import 'package:kraft/features/canvas/connector_geometry.dart';

import 'helpers.dart';

const _box = CanvasItem(id: 'a', type: CanvasItemType.card, position: Offset.zero);
const _circle = CanvasItem(id: 'c', type: CanvasItemType.shape, position: Offset.zero, shape: ShapeKind.ellipse);

Future<CanvasData> _saved(WidgetTester tester, AppDatabase db) async {
  final rows = await tester.runAsync(() => db.select(db.canvases).get());
  return CanvasCodec.decode(rows!.single.data);
}

void main() {
  group('geometría', () {
    test('el extremo sale por el lado que mira al otro elemento, no por anclas fijas', () {
      const rect = Rect.fromLTWH(0, 0, 200, 100);
      final right = outlinePoint(_box, rect, const Offset(600, 60));
      expect(right.point.dx, 200);
      expect(right.normal, const Offset(1, 0));

      final below = outlinePoint(_box, rect, const Offset(120, 700));
      expect(below.point.dy, 100);
      expect(below.normal, const Offset(0, 1));
      // No es el centro del lado: sigue la recta hacia el otro elemento.
      expect(below.point.dx, isNot(100));
    });

    test('en un círculo el punto cae sobre la circunferencia', () {
      const rect = Rect.fromLTWH(0, 0, 154, 154); // 150 + 4 de sombra
      final p = outlinePoint(_circle, rect, const Offset(500, 500)).point;
      expect((p - const Offset(75, 75)).distance, closeTo(75, 0.01));
    });

    test('la línea se recoloca al mover un elemento', () {
      const b = CanvasItem(id: 'b', type: CanvasItemType.card, position: Offset.zero);
      final side = linkBetween(from: _box, fromRect: const Rect.fromLTWH(0, 0, 200, 100), to: b, toRect: const Rect.fromLTWH(500, 0, 200, 100))!;
      final under = linkBetween(from: _box, fromRect: const Rect.fromLTWH(0, 0, 200, 100), to: b, toRect: const Rect.fromLTWH(0, 400, 200, 100))!;
      expect(side.start.dx, greaterThan(200));
      expect(under.start.dy, greaterThan(100));
      expect(under.end.dy, lessThan(400));
      expect(side.hits(side.mid, 4), isTrue);
      expect(side.hits(const Offset(350, 300), 4), isFalse);
    });
  });

  group('documento', () {
    CanvasDocument doc() => CanvasDocument(items: const [
          CanvasItem(id: 'a', type: CanvasItemType.card, position: Offset(0, 0)),
          CanvasItem(id: 'b', type: CanvasItemType.card, position: Offset(500, 0)),
          CanvasItem(id: 'c', type: CanvasItemType.card, position: Offset(0, 500)),
        ]);

    test('conectar no duplica, se deshace y se va con el elemento borrado', () {
      final d = doc();
      final link = d.addLink('a', 'b')!;
      expect(d.addLink('b', 'a'), link, reason: 'misma pareja en sentido contrario');
      d.addLink('a', 'c');
      expect(d.links, hasLength(2));

      d.undo();
      expect(d.links, [link]);

      d
        ..selectOnly(const CanvasHit.item('b'))
        ..deleteSelection();
      expect(d.links, isEmpty);
      d.undo();
      expect(d.links, [link]);
    });

    test('tocar una conexión la selecciona y borrar la quita sólo a ella', () {
      final d = doc();
      final link = d.addLink('a', 'b')!;
      final mid = d.linkGeometry(link)!.mid;
      final hit = d.hitTest(mid);
      expect(hit, CanvasHit.link(link.id));
      d
        ..selectOnly(hit!)
        ..deleteSelection();
      expect(d.links, isEmpty);
      expect(d.items, hasLength(3));
    });

    test('lee conexiones del formato antiguo', () {
      final data = CanvasCodec.decode('{"v":1,"items":[],"links":[["node-1","node-2"]]}');
      expect(data.links.single.from, 'node-1');
      expect(data.links.single.id, 'link-1');
    });
  });

  testWidgets('arrastrar el tirador de un elemento hasta otro los conecta', (tester) async {
    final db = await pumpKraft(tester, size: const Size(1366, 1024));
    await openCanvasEditor(tester);

    await tester.tap(find.text('2. BIOMETRÍA'));
    await tester.pumpAndSettle();
    final knob = tester.getCenter(find.bySemanticsLabel('Conectar'));
    final target = tester.getCenter(find.text('Flujo de autenticación sin contraseñas con biometría táctil.'));

    final g = await tester.startGesture(knob, kind: PointerDeviceKind.stylus, pointer: 40);
    for (var i = 1; i <= 12; i++) {
      await g.moveTo(Offset.lerp(knob, target, i / 12)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Guardar y salir'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await settle(tester);
    final links = (await _saved(tester, db)).links;
    expect(links.map((l) => (l.from, l.to)), contains(('node-2', 'sticky-1')));
  });

  testWidgets('soltar el tirador en vacío abre la rueda y lo creado queda conectado', (tester) async {
    final db = await pumpKraft(tester, size: const Size(1366, 1024));
    await openCanvasEditor(tester);

    await tester.tap(find.text('2. BIOMETRÍA'));
    await tester.pumpAndSettle();
    final knob = tester.getCenter(find.bySemanticsLabel('Conectar'));
    final empty = knob + const Offset(0, 330);
    final g = await tester.startGesture(knob, kind: PointerDeviceKind.stylus, pointer: 41);
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset.lerp(knob, empty, i / 10)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(find.text('AÑADIR'), findsOneWidget);

    // La rueda queda abierta para elegir tocando: "Nota" es la porción superior.
    final wheel = tester.getCenter(find.text('AÑADIR'));
    await tester.tapAt(wheel + const Offset(0, -70));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Guardar y salir'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await settle(tester);
    final saved = await _saved(tester, db);
    final note = saved.items.firstWhere((i) => i.type == CanvasItemType.sticky && i.id != 'sticky-1');
    expect(saved.links.map((l) => (l.from, l.to)), contains(('node-2', note.id)));
  });
}
