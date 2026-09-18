import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kraft/features/canvas/canvas_codec.dart';
import 'package:kraft/features/canvas/canvas_document.dart';
import 'package:kraft/features/canvas/canvas_models.dart';

Stroke _line(CanvasDocument doc, Offset from, Offset to) => Stroke(
  id: doc.allocateStrokeId(),
  points: [for (var i = 0; i <= 10; i++) Offset.lerp(from, to, i / 10)!],
  color: const Color(0xFF000000),
  width: 4,
);

void main() {
  test(
    'el lazo selecciona trazos mayoritariamente dentro y elementos por su centro',
    () {
      final doc = CanvasDocument(
        items: const [
          CanvasItem(
            id: 'a',
            type: CanvasItemType.shape,
            position: Offset(100, 100),
          ),
          CanvasItem(
            id: 'b',
            type: CanvasItemType.shape,
            position: Offset(900, 900),
          ),
        ],
      );
      final inside = _line(doc, const Offset(50, 400), const Offset(250, 400));
      final crossing = _line(
        doc,
        const Offset(250, 450),
        const Offset(900, 450),
      );
      doc
        ..addStroke(inside)
        ..addStroke(crossing);

      final count = doc.selectInLasso(const [
        Offset(0, 0),
        Offset(400, 0),
        Offset(400, 500),
        Offset(0, 500),
      ]);

      expect(count, 2);
      expect(doc.selectedItemIds, {'a'});
      expect(doc.selectedStrokeIds, {inside.id});
    },
  );

  test('al soltar un arrastre lo movido pasa al frente', () {
    final doc = CanvasDocument(
      items: const [
        CanvasItem(
          id: 'abajo',
          type: CanvasItemType.shape,
          position: Offset(0, 0),
        ),
        CanvasItem(
          id: 'encima',
          type: CanvasItemType.shape,
          position: Offset(300, 0),
        ),
      ],
    );
    doc
      ..selectOnly(const CanvasHit.item('abajo'))
      ..updateMove(const Offset(300, 0))
      ..commitMove();

    expect(doc.items.map((i) => i.id), ['encima', 'abajo']);
    expect(doc.hitTest(const Offset(350, 40))?.itemId, 'abajo');
  });

  test('mover, duplicar y recolorear con un paso de historial cada uno', () {
    final doc = CanvasDocument(
      items: const [
        CanvasItem(
          id: 'a',
          type: CanvasItemType.shape,
          position: Offset(100, 100),
        ),
      ],
    );
    final stroke = _line(doc, const Offset(0, 0), const Offset(50, 50));
    doc
      ..addStroke(stroke)
      ..selectAll()
      ..updateMove(const Offset(10, 20));

    expect(doc.itemRect(doc.items.single).topLeft, const Offset(110, 120));
    expect(
      doc.items.single.position,
      const Offset(100, 100),
      reason: 'no se confirma hasta soltar',
    );

    doc.commitMove();
    expect(doc.items.single.position, const Offset(110, 120));
    expect(doc.strokes.single.points.first, const Offset(10, 20));

    doc.duplicateSelection();
    expect(doc.items, hasLength(2));
    expect(doc.strokes, hasLength(2));
    expect(doc.selectionCount, 2, reason: 'quedan seleccionadas las copias');

    expect(doc.recolorSelection(const Color(0xFFFFE600)), isTrue);
    expect(doc.strokes.last.color, const Color(0xFFFFE600));
    expect(doc.strokes.first.color, const Color(0xFF000000));

    doc
      ..undo()
      ..undo()
      ..undo();
    expect(doc.items.single.position, const Offset(100, 100));
    expect(doc.strokes, hasLength(1));
  });

  test(
    'el borrador sólo guarda un paso de historial por gesto y limpia la selección borrada',
    () {
      final doc = CanvasDocument(items: const []);
      final a = _line(doc, const Offset(0, 0), const Offset(100, 0));
      final b = _line(doc, const Offset(0, 50), const Offset(100, 50));
      doc
        ..addStroke(a)
        ..addStroke(b)
        ..selectInLasso(const [
          Offset(-10, -10),
          Offset(120, -10),
          Offset(120, 70),
          Offset(-10, 70),
        ])
        ..beginErase()
        ..eraseAt(const Offset(50, 0), 5)
        ..eraseAt(const Offset(50, 50), 5);

      expect(doc.strokes, isEmpty);
      expect(doc.hasSelection, isFalse);
      doc.undo();
      expect(doc.strokes, hasLength(2));
    },
  );

  test(
    'el códec conserva elementos, trazos con presión, conexiones y vista',
    () {
      final doc = CanvasDocument(items: const []);
      final stroke = Stroke(
        id: doc.allocateStrokeId(),
        points: const [Offset(1.26, 2), Offset(10, 20.04)],
        color: const Color(0xFF006875),
        width: 4,
        pressures: const [0.123, 0.9],
      );
      const item = CanvasItem(
        id: 'shape-7',
        type: CanvasItemType.shape,
        position: Offset(-40, 12.5),
        title: 'Hola',
        shape: ShapeKind.diamond,
        color: Color(0xFFFFE600),
        scale: ItemScale.large,
        iconKey: 'star',
      );

      final raw = CanvasCodec.encode(
        CanvasData(
          items: const [item],
          strokes: [stroke],
          links: const [
            CanvasLink(
              id: 'link-3',
              from: 'shape-7',
              to: 'shape-7',
              label: 'sí',
              style: LinkStyle.straight,
            ),
          ],
          viewCenter: const Offset(5, 6),
          viewScale: 1.5,
        ),
      );
      final back = CanvasCodec.decode(raw);

      expect(back.items.single.toJson(), item.toJson());
      expect(back.strokes.single.points, const [
        Offset(1.3, 2),
        Offset(10, 20),
      ]);
      expect(back.strokes.single.pressures, [0.12, 0.9]);
      expect(
        back.links.single,
        const CanvasLink(
          id: 'link-3',
          from: 'shape-7',
          to: 'shape-7',
          label: 'sí',
          style: LinkStyle.straight,
        ),
      );
      expect(back.viewCenter, const Offset(5, 6));
      expect(back.viewScale, 1.5);
      expect(CanvasCodec.decode('no es json').isEmpty, isTrue);
    },
  );

  test('un documento cargado continúa los identificadores', () {
    final doc = CanvasDocument(
      items: const [
        CanvasItem(
          id: 'card-41',
          type: CanvasItemType.card,
          position: Offset.zero,
        ),
      ],
    );
    final added = doc.addItem(
      const CanvasItem(
        id: 'template',
        type: CanvasItemType.icon,
        position: Offset.zero,
      ),
    );
    expect(added.id, 'icon-42');
  });

  test('el marco mueve el grupo; una cajita interior se mueve sola', () {
    final doc = CanvasDocument(
      items: const [
        CanvasItem(
          id: 'marco',
          type: CanvasItemType.frame,
          position: Offset.zero,
          width: 800,
          height: 400,
        ),
        CanvasItem(
          id: 'dentro',
          type: CanvasItemType.shape,
          position: Offset(40, 40),
        ),
        CanvasItem(
          id: 'al-lado',
          type: CanvasItemType.shape,
          position: Offset(300, 40),
        ),
      ],
    );
    addTearDown(doc.dispose);
    doc.selectAll();
    doc.groupSelection();
    doc.clearSelection();

    doc.selectOnly(const CanvasHit.item('dentro'));
    expect(doc.selectedItemIds, {'dentro'});
    doc
      ..updateMove(const Offset(20, 10))
      ..commitMove();
    expect(doc.itemById('dentro')!.position, const Offset(60, 50));
    expect(doc.itemById('al-lado')!.position, const Offset(300, 40));
    expect(doc.itemById('marco')!.position, Offset.zero);

    doc.selectOnly(const CanvasHit.item('marco'));
    expect(doc.selectedItemIds, {'marco', 'dentro', 'al-lado'});
    doc
      ..updateMove(const Offset(5, 0))
      ..commitMove();
    expect(doc.itemById('dentro')!.position, const Offset(65, 50));
    expect(doc.itemById('al-lado')!.position, const Offset(305, 40));
    expect(doc.itemById('marco')!.position, const Offset(5, 0));

    doc.selectOnly(const CanvasHit.item('dentro'), expandGroup: false);
    expect(doc.selectedItemIds, {'dentro'});
  });

  test('el marco seleccionado con su grupo cambia de tamaño por separado', () {
    final doc = CanvasDocument(
      items: const [
        CanvasItem(
          id: 'marco',
          type: CanvasItemType.frame,
          position: Offset.zero,
          width: 800,
          height: 400,
          group: 'capa',
        ),
        CanvasItem(
          id: 'dentro',
          type: CanvasItemType.shape,
          position: Offset(40, 40),
          group: 'capa',
        ),
      ],
    );
    addTearDown(doc.dispose);

    doc.selectOnly(const CanvasHit.item('marco'));
    expect(doc.selectedItemIds, {'marco', 'dentro'});
    expect(doc.selectedFrameForResize!.id, 'marco');

    doc
      ..beginResize('marco')
      ..updateResize(1.5)
      ..endResize();
    expect(doc.itemById('marco')!.zoom, 1.5);
    expect(doc.itemById('dentro')!.zoom, 1);
  });

  test('los ajustes manuales de conexión y etiqueta se guardan', () {
    final doc = CanvasDocument(
      items: const [
        CanvasItem(id: 'a', type: CanvasItemType.shape, position: Offset.zero),
        CanvasItem(
          id: 'b',
          type: CanvasItemType.shape,
          position: Offset(300, 0),
        ),
      ],
      links: const [CanvasLink(id: 'l', from: 'a', to: 'b', label: 'pasa')],
    );
    addTearDown(doc.dispose);

    doc
      ..beginLinkBend('l')
      ..updateLinkBend(const Offset(150, 120))
      ..endLinkBend()
      ..beginLinkLabelMove('l')
      ..updateLinkLabelOffset(const Offset(20, -30))
      ..endLinkLabelMove();

    final link = doc.links.single;
    expect(link.bend, const Offset(150, 120));
    expect(link.labelOffset, const Offset(20, -30));
    final data = CanvasCodec.decode(
      CanvasCodec.encode(CanvasData(items: doc.items, links: doc.links)),
    );
    expect(data.links.single, link);
  });

  test('redimensionar conserva el borde real para selección y conexiones', () {
    final doc = CanvasDocument(
      items: const [
        CanvasItem(id: 'a', type: CanvasItemType.card, position: Offset.zero),
        CanvasItem(
          id: 'b',
          type: CanvasItemType.shape,
          position: Offset(700, 0),
        ),
      ],
      links: const [CanvasLink(id: 'l', from: 'a', to: 'b')],
    );
    addTearDown(doc.dispose);

    // La tarjeta corta, aunque su estimación por defecto sea más alta.
    doc.reportItemSize('a', const Size(260, 96));
    doc
      ..beginResize('a')
      ..updateResize(2)
      ..endResize();

    expect(doc.itemRect(doc.itemById('a')!).size, const Size(520, 192));
    // La flecha parte de ese borde medido, no de la altura de la estimación.
    expect(doc.linkGeometry(doc.links.single)!.start.dx, closeTo(526, 0.01));
  });

  test(
    'el área de trabajo limita elementos y movimientos sin cortar el grupo',
    () {
      final doc = CanvasDocument(
        items: const [
          CanvasItem(
            id: 'a',
            type: CanvasItemType.shape,
            position: Offset(9000, 0),
          ),
        ],
      );
      addTearDown(doc.dispose);

      doc.selectOnly(const CanvasHit.item('a'));
      doc.updateMove(const Offset(5000, 0));
      expect(doc.moveOffset.dx, 820);
      doc.commitMove();
      expect(doc.itemById('a')!.position.dx, 9820);

      final added = doc.addItem(
        const CanvasItem(
          id: 'new',
          type: CanvasItemType.shape,
          position: Offset(50000, 0),
        ),
      );
      expect(added.position.dx, 9820);
    },
  );
}
