import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kraft/features/voice/assistant_markdown.dart';
import 'package:kraft/widgets/kraft_nav_bar.dart';

import 'helpers.dart';

void main() {
  testWidgets('la barra inferior navega entre las 4 pestañas', (tester) async {
    await pumpKraft(tester);
    expect(find.text('Hola, Alex'), findsOneWidget);

    await tapNav(tester, 'Lienzo');
    expect(find.text('Boceto de Arquitectura'), findsOneWidget);

    await tapNav(tester, 'Notas');
    expect(find.text('Diseño de Experiencia iPad & Stylus'), findsOneWidget);

    await tapNav(tester, 'Grafo');
    expect(find.text('Grafo de ideas'), findsOneWidget);

    await tapNav(tester, 'Inicio');
    expect(find.text('Hola, Alex'), findsOneWidget);
  });

  testWidgets('en escritorio hay navegación lateral y atajos de secciones', (
    tester,
  ) async {
    await pumpKraft(tester, size: const Size(1366, 1024));

    expect(find.byType(KraftNavigationRail), findsOneWidget);
    expect(find.byType(KraftNavBar), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);

    expect(find.text('Diseño de Experiencia iPad & Stylus'), findsOneWidget);
  });

  testWidgets('el historial del chat abre desde su overlay', (tester) async {
    await pumpKraft(tester, size: const Size(1366, 1024));

    await tester.tap(find.byTooltip('Hablar con KRAFT'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Historial de conversaciones'));
    await tester.pumpAndSettle();

    expect(find.text('Nueva conversación'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el Markdown del asistente encuadra el código', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AssistantMarkdown(
            text:
                '## Ejemplo\n\n```proto\nsyntax = "proto3";\n```\n\n- **Un** punto',
          ),
        ),
      ),
    );

    expect(find.byType(RichText), findsAtLeastNWidgets(2));
    expect(find.text('proto'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('syntax = "proto3";'), findsOneWidget);
  });

  testWidgets('el Markdown convierte tablas en columnas legibles', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AssistantMarkdown(
            text:
                '| Característica | gRPC | REST |\n| --- | --- | --- |\n| Transporte | HTTP/2 | HTTP/1.1 |',
          ),
        ),
      ),
    );

    Finder rich(String text) => find.byWidgetPredicate(
      (widget) => widget is RichText && widget.text.toPlainText() == text,
    );
    expect(rich('Característica'), findsOneWidget);
    expect(rich('HTTP/2'), findsOneWidget);
    expect(rich('| --- | --- | --- |'), findsNothing);
  });

  testWidgets('dibujar en el lienzo habilita deshacer y deshacer lo revierte', (
    tester,
  ) async {
    await pumpKraft(tester);
    await openCanvasEditor(tester);

    Color undoColor() => tester
        .widget<Icon>(
          find.descendant(
            of: find.byTooltip('Deshacer'),
            matching: find.byType(Icon),
          ),
        )
        .color!;
    final disabled = undoColor();

    await tester.tap(toolButton('Lápiz / Trazo libre'));
    await tester.pumpAndSettle();
    final pencil = await tester.startGesture(
      const Offset(500, 600),
      kind: PointerDeviceKind.stylus,
    );
    await pencil.moveBy(const Offset(120, 60));
    await pencil.up();
    await tester.pumpAndSettle();
    expect(undoColor(), isNot(disabled));

    await tester.tap(find.byTooltip('Deshacer'));
    await tester.pumpAndSettle();
    expect(undoColor(), disabled);
  });

  testWidgets('editar un nodo con el editor de elementos y deshacer', (
    tester,
  ) async {
    await pumpKraft(tester);
    await openCanvasEditor(tester);

    Future<void> editNode(
      String current,
      String next, {
      required bool save,
    }) async {
      // El toque lo recibe la capa de entrada del lienzo, no el texto: sin aviso de "tap missed".
      final node = find.text(current);
      await tester.tap(node, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(node, warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, next);
      await tester.pump();
      if (save) {
        await tester.tap(find.text('GUARDAR'));
      } else {
        await tester.tap(find.byTooltip('Cerrar'));
      }
      await tester.pumpAndSettle();
    }

    await editNode('2. BIOMETRÍA', 'Face ID', save: true);
    expect(find.text('FACE ID'), findsOneWidget);
    await editNode('FACE ID', 'Descartado', save: false);
    expect(find.text('FACE ID'), findsOneWidget);

    await tester.tap(find.byTooltip('Deshacer'));
    await tester.pumpAndSettle();
    expect(find.text('2. BIOMETRÍA'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'la galería de elementos se despliega en el lienzo e inserta un icono',
    (tester) async {
      await pumpKraft(tester, size: const Size(1366, 1024));
      await openCanvasEditor(tester);
      await tester.tap(find.byTooltip('Biblioteca de elementos'));
      await tester.pumpAndSettle();

      expect(find.text('ELEMENTOS'), findsOneWidget);
      await tester.tap(find.text('ICONOS'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Lanzamiento'));
      await tester.pumpAndSettle();

      expect(
        find.text('ELEMENTOS'),
        findsNothing,
        reason: 'se cierra al insertar',
      );
      expect(find.text('1 SELECCIONADO'), findsOneWidget);
    },
  );
}
