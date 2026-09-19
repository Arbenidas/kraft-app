import 'package:drift/drift.dart' show DatabaseConnection, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kraft/data/db/database.dart';
import 'package:kraft/data/enums.dart';
import 'package:kraft/data/repositories.dart';

void main() {
  test('un proyecto agrupa sus notas, lienzos y tareas', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
      seed: false,
    );
    addTearDown(db.close);
    final projects = ProjectsRepository(db);
    final id = await projects.create(
      title: 'Calculadora',
      kind: ProjectKind.lienzo,
    );
    final otherId = await projects.create(
      title: 'Otro',
      kind: ProjectKind.lienzo,
    );

    final notes = NotesRepository(db);
    final canvases = CanvasesRepository(db);
    final tasks = TasksRepository(db);

    final mine = await notes.create(projectId: id);
    await notes.create(projectId: otherId);
    await canvases.create(title: 'Arquitectura', projectId: id);
    await tasks.create(title: 'Repasar BLoC', projectId: id);
    await tasks.create(title: 'Suelta');

    expect((await notes.watchAll(projectId: id).first).map((n) => n.id), [
      mine,
    ]);
    expect((await canvases.watchAll(projectId: id).first).map((c) => c.title), [
      'Arquitectura',
    ]);
    expect((await tasks.watchAll(projectId: id).first).map((t) => t.title), [
      'Repasar BLoC',
    ]);

    // Sacar algo del proyecto lo deja suelto, no lo borra.
    await notes.setProject(mine, null);
    expect(await notes.watchAll(projectId: id).first, isEmpty);
    expect(await notes.get(mine), isNotNull);

    // Borrar el proyecto no arrastra su contenido (onDelete: setNull).
    await canvases.setProject(
      (await canvases.watchAll(projectId: id).first).single.id,
      id,
    );
    await projects.delete(id);
    final survivor = await canvases.watchAll().first;
    expect(survivor.any((c) => c.title == 'Arquitectura'), isTrue);
    expect(
      survivor.firstWhere((c) => c.title == 'Arquitectura').projectId,
      isNull,
    );
  });
}
