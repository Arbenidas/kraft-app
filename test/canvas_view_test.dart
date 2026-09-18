import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kraft/features/canvas/canvas_input.dart';
import 'package:kraft/features/canvas/canvas_minimap.dart';

import 'helpers.dart';

const _node1 = '1. REGISTRO MÓVIL';
const _sticky = 'Flujo de autenticación sin contraseñas con biometría táctil.';

Future<void> _openCanvas(WidgetTester tester) async {
  await pumpKraft(tester, size: const Size(1366, 1024));
  await openCanvasEditor(tester);
}

Rect _contentRect(WidgetTester tester) => tester
    .getRect(find.text(_node1))
    .expandToInclude(tester.getRect(find.text(_sticky)))
    .expandToInclude(tester.getRect(find.text('#BOCETO_PANTALLA_ACCESO')));

Future<void> _fingerDrag(
  WidgetTester tester,
  Offset from,
  Offset delta, {
  int pointer = 1,
}) async {
  final g = await tester.startGesture(
    from,
    kind: PointerDeviceKind.touch,
    pointer: pointer,
  );
  for (var i = 1; i <= 10; i++) {
    await g.moveTo(from + delta * (i / 10));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await g.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('el lienzo arranca centrado en el contenido', (tester) async {
    await _openCanvas(tester);
    final viewport = tester.getRect(find.byType(CanvasInputLayer));
    final content = _contentRect(tester);

    // El contenido medido por textos es aproximado: basta con que esté cerca del centro.
    expect((content.center.dx - viewport.center.dx).abs(), lessThan(60));
    expect((content.center.dy - viewport.center.dy).abs(), lessThan(60));
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('los atajos funcionan en el lienzo y la búsqueda acepta texto', (
    tester,
  ) async {
    await _openCanvas(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(find.textContaining('Dibuja con el lápiz'), findsOneWidget);

    await tester.tap(find.byTooltip('Biblioteca de elementos'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'marco');
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'marco',
    );
  });

  testWidgets(
    'el lienzo permite desplazamiento amplio y centrar contenido vuelve',
    (tester) async {
      await _openCanvas(tester);
      final start = tester.getRect(find.text(_node1));

      // 6 arrastres de 600 pt hacia arriba a la izquierda: más allá del antiguo tablero de 4000×3000.
      for (var i = 0; i < 6; i++) {
        await _fingerDrag(
          tester,
          const Offset(1100, 800),
          const Offset(-600, -500),
          pointer: 10 + i,
        );
      }
      expect(
        tester.getRect(find.text(_node1)).topLeft - start.topLeft,
        const Offset(-3600, -3000),
      );

      await tester.tap(toolButton('Centrar contenido'));
      await tester.pumpAndSettle();
      expect(
        (tester.getRect(find.text(_node1)).topLeft - start.topLeft).distance,
        lessThan(1),
      );
    },
  );

  testWidgets(
    'tocar el minimapa lleva la vista a ese punto y se puede plegar',
    (tester) async {
      await _openCanvas(tester);
      expect(find.text('MAPA'), findsOneWidget);
      final before = tester.getRect(find.text(_node1));

      final map = tester.getRect(find.byType(CanvasMinimap));
      await tester.tapAt(map.bottomLeft + const Offset(12, -12));
      await tester.pumpAndSettle();
      final after = tester.getRect(find.text(_node1));
      expect(
        after.left,
        greaterThan(before.left),
        reason: 'ir a la izquierda del contenido lo desplaza a la derecha',
      );
      expect(
        after.top,
        lessThan(before.top),
        reason: 'ir abajo del contenido lo desplaza hacia arriba',
      );

      await tester.tap(find.byTooltip('Ocultar minimapa'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Mostrar minimapa'), findsOneWidget);
      expect(find.byTooltip('Ocultar minimapa'), findsNothing);
    },
  );
}
