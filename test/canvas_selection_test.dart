import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const _node1 = '1. REGISTRO MÓVIL';
const _node2 = '2. BIOMETRÍA';

Future<void> _openCanvas(WidgetTester tester) async {
  await pumpKraft(tester, size: const Size(1366, 1024));
  await openCanvasEditor(tester);
}

/// Arrastre punto a punto con el dispositivo indicado.
Future<void> _drag(
  WidgetTester tester,
  List<Offset> path, {
  PointerDeviceKind kind = PointerDeviceKind.stylus,
  int pointer = 1,
}) async {
  final gesture = await tester.startGesture(
    path.first,
    kind: kind,
    pointer: pointer,
  );
  for (final p in path.skip(1)) {
    await gesture.moveTo(p);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

/// Rodea [rect] con un lazo de 24 puntos.
List<Offset> _loop(Rect rect) {
  final r = rect.inflate(40);
  return [
    for (var i = 0; i <= 6; i++) Offset(r.left + r.width * i / 6, r.top),
    for (var i = 1; i <= 6; i++) Offset(r.right, r.top + r.height * i / 6),
    for (var i = 1; i <= 6; i++) Offset(r.right - r.width * i / 6, r.bottom),
    for (var i = 1; i <= 6; i++) Offset(r.left, r.bottom - r.height * i / 6),
  ];
}

Rect _cardRect(WidgetTester tester, String title) =>
    tester.getRect(find.text(title));

void main() {
  testWidgets('lazo con Apple Pencil selecciona dos nodos, borrar y deshacer', (
    tester,
  ) async {
    await _openCanvas(tester);
    await tester.tap(toolButton('Lazo de selección'));
    await tester.pumpAndSettle();
    final bounds = _cardRect(
      tester,
      _node1,
    ).expandToInclude(_cardRect(tester, _node2));

    await _drag(tester, _loop(bounds));

    expect(find.text('2 SELECCIONADOS'), findsOneWidget);
    expect(find.text('APPLE PENCIL ACTIVO'), findsOneWidget);

    await tester.tap(find.byTooltip('Borrar selección'));
    await tester.pump(); // primer fotograma: arranca la animación del aviso
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(_node1), findsNothing);
    expect(find.text(_node2), findsNothing);

    await tester.tap(find.text('DESHACER'));
    await tester.pumpAndSettle();
    expect(find.text(_node1), findsOneWidget);
    expect(find.text(_node2), findsOneWidget);
  });

  testWidgets(
    'selección: arrastrar el lápiz en vacío hace un recuadro, no un lazo',
    (tester) async {
      await _openCanvas(tester);
      final bounds = _cardRect(
        tester,
        _node1,
      ).expandToInclude(_cardRect(tester, _node2)).inflate(60);
      await _drag(tester, [
        for (var i = 0; i <= 8; i++)
          Offset.lerp(bounds.topLeft, bounds.bottomRight, i / 8)!,
      ]);
      expect(find.text('2 SELECCIONADOS'), findsOneWidget);
    },
  );

  testWidgets('mover lienzo: el lápiz desplaza en vez de seleccionar', (
    tester,
  ) async {
    await _openCanvas(tester);
    await tester.tap(toolButton('Mover lienzo'));
    await tester.pumpAndSettle();
    final before = _cardRect(tester, _node1);
    await _drag(tester, [
      for (var i = 0; i <= 5; i++) before.center + Offset(-20.0 * i, 0),
    ]);
    expect(
      _cardRect(tester, _node1).topLeft - before.topLeft,
      const Offset(-100, 0),
    );
    expect(find.textContaining('SELECCIONADO'), findsNothing);
  });

  testWidgets('tocar con el lápiz selecciona y arrastrar mueve el nodo', (
    tester,
  ) async {
    await _openCanvas(tester);
    final before = _cardRect(tester, _node1);

    await _drag(tester, [before.center]);
    expect(find.text('1 SELECCIONADO'), findsOneWidget);

    await _drag(tester, [
      for (var i = 0; i <= 8; i++) before.center + Offset(20.0 * i, 10.0 * i),
    ]);
    final after = _cardRect(tester, _node1);
    expect(after.topLeft - before.topLeft, const Offset(160, 80));

    await tester.tap(find.byTooltip('Deshacer'));
    await tester.pumpAndSettle();
    expect(_cardRect(tester, _node1).topLeft, before.topLeft);
  });

  testWidgets('la barra de selección permite agrandar una tarjeta', (
    tester,
  ) async {
    await _openCanvas(tester);
    final before = _cardRect(tester, _node1);

    await _drag(tester, [before.center]);
    await tester.tap(find.byTooltip('Tamaño M · tocar para cambiar'));
    await tester.pumpAndSettle();

    final after = _cardRect(tester, _node1);
    expect(after.width, greaterThan(before.width));
    expect(find.byTooltip('Tamaño L · tocar para cambiar'), findsOneWidget);
  });

  testWidgets(
    'con Apple Pencil detectado el dedo mueve el lienzo y el lápiz dibuja',
    (tester) async {
      await _openCanvas(tester);
      await tester.tap(toolButton('Lápiz / Trazo libre'));
      await tester.pumpAndSettle();

      // Primer trazo con lápiz: activa "sólo dibujar con Apple Pencil".
      await _drag(tester, [
        for (var i = 0; i <= 6; i++) Offset(900.0 + i * 20, 700),
      ]);
      expect(find.text('APPLE PENCIL ACTIVO'), findsOneWidget);

      final before = _cardRect(tester, _node1);
      await _drag(
        tester,
        [for (var i = 0; i <= 5; i++) Offset(1000.0 - i * 20, 600.0 + i * 10)],
        kind: PointerDeviceKind.touch,
        pointer: 2,
      );
      expect(
        _cardRect(tester, _node1).topLeft - before.topLeft,
        const Offset(-100, 50),
      );

      // Deshacer sólo quita el trazo del lápiz (el desplazamiento del dedo no es un cambio del documento).
      await tester.tap(find.byTooltip('Deshacer'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Deshacer'));
      await tester.pumpAndSettle();
      expect(
        _cardRect(tester, _node1).topLeft - before.topLeft,
        const Offset(-100, 50),
      );
    },
  );

  testWidgets('sin lápiz: mantener pulsado y arrastrar hace lazo con el dedo', (
    tester,
  ) async {
    await _openCanvas(tester);
    final bounds = _cardRect(tester, _node1);
    final path = _loop(bounds);

    final gesture = await tester.startGesture(
      path.first,
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 400)); // pulsación larga
    for (final p in path.skip(1)) {
      await gesture.moveTo(p);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('1 SELECCIONADO'), findsOneWidget);
    expect(_cardRect(tester, _node1), bounds); // no desplazó el lienzo
  });

  testWidgets('pellizco con dos dedos cambia el zoom', (tester) async {
    await _openCanvas(tester);
    expect(find.text('100%'), findsOneWidget);

    final a = await tester.startGesture(
      const Offset(600, 500),
      kind: PointerDeviceKind.touch,
      pointer: 11,
    );
    final b = await tester.startGesture(
      const Offset(700, 500),
      kind: PointerDeviceKind.touch,
      pointer: 12,
    );
    for (var i = 1; i <= 10; i++) {
      await a.moveTo(Offset(600.0 - i * 5, 500));
      await b.moveTo(Offset(700.0 + i * 5, 500));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();

    expect(find.text('200%'), findsOneWidget);
  });

  testWidgets('doble toque del Apple Pencil alterna el borrador', (
    tester,
  ) async {
    await _openCanvas(tester);

    Future<void> doubleTap() async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'kraft/pencil',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('tap', {'action': 'switchEraser'}),
        ),
        (_) {},
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    await doubleTap();
    expect(find.text('Herramienta: Borrador'), findsOneWidget);
    await tester.pumpAndSettle();

    await doubleTap();
    // Vuelve a la herramienta anterior al borrador.
    expect(find.text('Herramienta: Selección'), findsOneWidget);
    await tester.pumpAndSettle();
  });
}
