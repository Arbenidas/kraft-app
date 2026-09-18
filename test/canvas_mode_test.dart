import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kraft/data/db/database.dart';
import 'package:kraft/features/canvas/canvas_codec.dart';
import 'package:kraft/features/canvas/canvas_input.dart';
import 'package:kraft/features/canvas/floating_palette.dart';
import 'package:kraft/theme/kraft_colors.dart';

import 'helpers.dart';

const _size = Size(1366, 1024);

Future<CanvasData> _savedCanvas(
  WidgetTester tester,
  AppDatabase db, {
  String title = 'Boceto de Arquitectura',
}) async {
  final rows = await tester.runAsync(() => db.select(db.canvases).get());
  return CanvasCodec.decode(rows!.firstWhere((r) => r.title == title).data);
}

Future<void> _pencilLine(
  WidgetTester tester,
  Offset from,
  Offset to, {
  int pointer = 7,
}) async {
  final g = await tester.startGesture(
    from,
    kind: PointerDeviceKind.stylus,
    pointer: pointer,
  );
  for (var i = 1; i <= 8; i++) {
    await g.moveTo(Offset.lerp(from, to, i / 8)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await g.up();
  await tester.pumpAndSettle();
}

Future<void> _exit(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Guardar y salir'));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await settle(tester);
}

void main() {
  testWidgets('salir con el botón guarda el lienzo y vuelve a la galería', (
    tester,
  ) async {
    final db = await pumpKraft(tester, size: _size);
    await openCanvasEditor(tester);

    await tester.tap(toolButton('Lápiz / Trazo libre'));
    await tester.pumpAndSettle();
    await _pencilLine(tester, const Offset(900, 600), const Offset(1100, 650));

    await _exit(tester);
    expect(find.byType(CanvasInputLayer), findsNothing);
    expect(find.text('Lienzos'), findsWidgets);

    final saved = await _savedCanvas(tester, db);
    expect(saved.strokes, hasLength(1));
    expect(saved.items, hasLength(4));
    expect(saved.viewCenter, isNotNull);

    // Se puede volver a entrar al lienzo guardado.
    await tester.tap(find.text('Boceto de Arquitectura'));
    await settle(tester);
    expect(find.byType(CanvasInputLayer), findsOneWidget);
  });

  testWidgets('"Nuevo lienzo" crea uno vacío y entra en modo lienzo', (
    tester,
  ) async {
    final db = await pumpKraft(tester, size: _size);
    await tapNav(tester, 'Lienzo');
    await tester.tap(find.text('NUEVO LIENZO').first);
    await settle(tester);

    expect(find.byType(CanvasInputLayer), findsOneWidget);
    expect(find.text('Lienzo sin título'), findsOneWidget);
    final rows = await tester.runAsync(() => db.select(db.canvases).get());
    expect(rows, hasLength(2));
  });

  testWidgets(
    'mantener el lápiz abre la rueda y soltar sobre una opción la añade',
    (tester) async {
      final db = await pumpKraft(tester, size: _size);
      await openCanvasEditor(tester);

      const point = Offset(1000, 650);
      final g = await tester.startGesture(
        point,
        kind: PointerDeviceKind.stylus,
        pointer: 30,
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('AÑADIR'), findsOneWidget);

      // Hacia arriba: primera porción, "Nota".
      for (var i = 1; i <= 6; i++) {
        await g.moveTo(point + Offset(0, -12.0 * i));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('NOTA'), findsWidgets);
      await g.up();
      await tester.pumpAndSettle();

      expect(find.text('AÑADIR'), findsNothing);
      expect(find.text('Nueva idea'), findsOneWidget);

      await _exit(tester);
      expect((await _savedCanvas(tester, db)).items, hasLength(5));
    },
  );

  testWidgets(
    'al dibujar la paleta se hace bolita, se arrastra a una esquina y se despliega',
    (tester) async {
      await pumpKraft(tester, size: _size);
      await openCanvasEditor(tester);
      await tester.tap(toolButton('Lápiz / Trazo libre'));
      await tester.pumpAndSettle();

      await _pencilLine(
        tester,
        const Offset(900, 500),
        const Offset(1000, 540),
      );
      final bubble = find.bySemanticsLabel('Mostrar herramientas');
      expect(
        tester.getRect(bubble).width,
        closeTo(FloatingPalette.bubbleSize, 0.5),
      );

      // Arrastrar la burbuja cerca de la esquina superior izquierda: se ancla ahí.
      final start = tester.getCenter(bubble);
      final g = await tester.startGesture(start, pointer: 8);
      for (var i = 1; i <= 10; i++) {
        await g.moveTo(Offset.lerp(start, const Offset(80, 160), i / 10)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pumpAndSettle();
      final docked = tester.getRect(bubble);
      expect(docked.left, lessThan(40));
      expect(docked.top, lessThan(260));

      await tester.tap(bubble);
      await tester.pumpAndSettle();
      // En un lado la paleta se pone en vertical: las herramientas quedan en columna pegadas al borde izquierdo.
      final select = tester.getRect(toolButton('Selección'));
      final pen = tester.getRect(toolButton('Lápiz / Trazo libre'));
      expect(select.left, lessThan(60));
      expect(pen.left, closeTo(select.left, 1));
      expect(pen.top, greaterThan(select.bottom));
      expect(select.top, lessThan(160), reason: 'se despliega arriba');
      expect(find.text('PRESIÓN'), findsNothing, reason: 'versión compacta');
    },
  );

  testWidgets('arrastrar un elemento de la galería lo coloca en el lienzo', (
    tester,
  ) async {
    await pumpKraft(tester, size: _size);
    await openCanvasEditor(tester);
    await tester.tap(find.byTooltip('Biblioteca de elementos'));
    await tester.pumpAndSettle();

    final tile = tester.getCenter(find.byTooltip('Círculo'));
    final g = await tester.startGesture(tile, pointer: 9);
    const target = Offset(1050, 300);
    for (var i = 1; i <= 12; i++) {
      await g.moveTo(Offset.lerp(tile, target, i / 12)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();

    expect(find.text('ELEMENTOS'), findsNothing);
    expect(find.text('1 SELECCIONADO'), findsOneWidget);
  });

  testWidgets('la biblioteca incluye marcos y deja escribir para buscarlos', (
    tester,
  ) async {
    await pumpKraft(tester, size: _size);
    await openCanvasEditor(tester);
    await tester.tap(find.byTooltip('Biblioteca de elementos'));
    await tester.pumpAndSettle();

    expect(find.byTooltip(RegExp('^Marco')), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'marco');
    await tester.pumpAndSettle();
    expect(find.text('MARCO'), findsWidgets);
  });

  testWidgets('el editor de elementos cambia el color y se guarda', (
    tester,
  ) async {
    final db = await pumpKraft(tester, size: _size);
    await openCanvasEditor(tester);

    final sticky = find.text(
      'Flujo de autenticación sin contraseñas con biometría táctil.',
    );
    await tester.tap(sticky, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Editar elemento'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Verde').first);
    await tester.pump();
    await tester.tap(find.text('GUARDAR'));
    await tester.pumpAndSettle();

    await _exit(tester);
    final saved = await _savedCanvas(tester, db);
    expect(
      saved.items.firstWhere((i) => i.id == 'sticky-1').color,
      KraftColors.secondaryContainer,
    );
  });
}
