import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kraft/data/repositories.dart';
import 'package:kraft/widgets/neo_checkbox.dart';

import 'helpers.dart';

void main() {
  // El iPad mini 6 en horizontal: 1133x744 pt, mucho más estrecho que el Pro.
  const miniLandscape = Size(1133, 744);

  testWidgets('la casilla de una nota rápida la marca como hecha', (
    tester,
  ) async {
    final db = await pumpKraft(tester, size: miniLandscape);
    final tasks = TasksRepository(db);
    final id = await tasks.create(title: 'Hacer merges de la rama principal');
    await settle(tester);

    final box = find.byType(NeoCheckbox);
    expect(box, findsWidgets, reason: 'la lista debería pintar casillas');

    final target = find
        .descendant(
          of: find.ancestor(
            of: find.text('Hacer merges de la rama principal'),
            matching: find.byType(Row),
          ),
          matching: find.byType(NeoCheckbox),
        )
        .first;
    await tester.tap(target, warnIfMissed: true);
    await settle(tester);

    expect((await tasks.get(id))!.done, isTrue);
  });

  testWidgets('un recordatorio con fecha aparece en el cronograma', (
    tester,
  ) async {
    final db = await pumpKraft(tester, size: miniLandscape);
    final at = DateTime.now().add(const Duration(hours: 3));
    await TasksRepository(db).create(
      title: 'Hacer merges de la rama principal',
      detail: 'Con la rama de cambios del programa',
      remindAt: at,
    );
    await settle(tester);

    // La tarea vive en otra tabla que los eventos: el cronograma las junta al pintar.
    final card = find.ancestor(
      of: find.textContaining('CRONOGRAMA'),
      matching: find.byType(Column),
    );
    expect(card, findsWidgets);
    expect(find.text('Hacer merges de la rama principal'), findsWidgets);
    expect(find.text('TAREA'), findsWidgets);
  });
}
