import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kraft/widgets/neo_checkbox.dart';
import 'package:kraft/utils/dates.dart';

import 'helpers.dart';

void main() {
  testWidgets('crear una tarea, marcarla y persistirla', (tester) async {
    final db = await pumpKraft(tester);

    await tester.tap(find.text(' Nueva ').first);
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, 'Llamar al cliente');
    await tester.pump(); // El botón se habilita al reconstruir con texto.
    await tester.tap(find.text('AÑADIR'));
    await settle(tester);

    expect(find.text('Llamar al cliente'), findsOneWidget);

    await tester.tap(checkboxFor('Llamar al cliente'));
    // La casilla marca al instante y guarda tras la animación.
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);

    final saved = await tester.runAsync(() => db.select(db.tasks).get());
    expect(saved!.firstWhere((t) => t.title == 'Llamar al cliente').done, isTrue);
  });

  testWidgets('borrar una tarea desde el menú y deshacer', (tester) async {
    final db = await pumpKraft(tester);
    const title = 'Exportar esquemas de color para cliente';

    final menu = find.descendant(
      of: find.ancestor(of: find.text(title), matching: find.byType(Dismissible)),
      matching: find.byTooltip('Más opciones'),
    );
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrar'));
    // Cierre del menú → borrado en la base → aviso entrando (sin esperar a que se oculte).
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text(title), findsNothing);

    await tester.tap(find.text('DESHACER'));
    await settle(tester);
    expect(find.text(title), findsOneWidget);
    expect((await tester.runAsync(() => db.select(db.tasks).get()))!.length, 3);
  });

  testWidgets('cronograma: navegar semanas, vista mes y volver a hoy', (tester) async {
    await pumpKraft(tester);
    final today = DateTime.now();
    expect(find.text(longDay(today).toUpperCase()), findsOneWidget);
    expect(find.text('HOY'), findsOneWidget);

    await tester.tap(find.byTooltip('Siguiente'));
    await settle(tester);
    expect(find.text(longDay(addDays(dateOnly(today), 7)).toUpperCase()), findsOneWidget);
    expect(find.text('IR A HOY'), findsOneWidget);

    await tester.tap(find.text('Mes'));
    await settle(tester);
    // La cuadrícula mensual muestra 6 semanas × 7 días.
    expect(find.text('${startOfWeek(DateTime(today.year, today.month, 1)).day}'), findsWidgets);

    await tester.tap(find.text('IR A HOY'));
    await settle(tester);
    expect(find.text('HOY'), findsOneWidget);
    expect(find.text('Review Arquitectura iPad'), findsOneWidget);
  });

  testWidgets('crear un proyecto desde el menú Crear', (tester) async {
    final db = await pumpKraft(tester);

    await tester.tap(find.text('CREAR'));
    await settle(tester);
    await tester.tap(find.text('Proyecto'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, 'Identidad Kraft');
    await tester.pump();
    await tester.tap(find.text('STYLUS').last);
    await tester.pump();
    await tester.tap(find.text('CREAR').last);
    await settle(tester);

    final projects = await tester.runAsync(() => db.select(db.projects).get());
    expect(projects!.map((p) => p.title), contains('Identidad Kraft'));
    expect(find.text('Identidad Kraft'), findsOneWidget);
  });
}

/// Casilla de la fila que contiene [text] (la fila más cercana que también contiene una casilla).
Finder checkboxFor(String text) => find.descendant(
      of: find.ancestor(
        of: find.text(text),
        matching: find.byWidgetPredicate((w) => w is Row && w.children.any((c) => c is NeoCheckbox)),
      ),
      matching: find.byType(NeoCheckbox),
    );
