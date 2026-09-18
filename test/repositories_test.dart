import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kraft/data/db/database.dart';
import 'package:kraft/data/enums.dart';
import 'package:kraft/data/repositories.dart';
import 'package:kraft/utils/dates.dart';

void main() {
  late AppDatabase db;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  setUp(() => db = AppDatabase(NativeDatabase.memory(), seed: false));
  tearDown(() => db.close());

  test('la base sembrada tiene el contenido de ejemplo', () async {
    final seeded = AppDatabase(NativeDatabase.memory());
    addTearDown(seeded.close);
    expect(await ProjectsRepository(seeded).watchCount().first, 3);
    expect(await NotesRepository(seeded).watchCount().first, 2);
    final today = dateOnly(DateTime.now());
    final events = await EventsRepository(
      seeded,
    ).watchRange(today, addDays(today, 1)).first;
    expect(events.map((e) => e.title), [
      'Review Arquitectura iPad',
      'Entrega de Wireframes V2',
    ]);
  });

  test('proyectos: crear, filtrar por tipo, editar y borrar', () async {
    final repo = ProjectsRepository(db);
    final id = await repo.create(
      title: 'Portada',
      kind: ProjectKind.stylus,
      tags: ['#UI'],
    );
    await repo.create(title: 'Notas sueltas', kind: ProjectKind.nota);

    final stylus = await repo.watchAll(kind: ProjectKind.stylus).first;
    expect(stylus.single.tags, ['#UI']);

    await repo.update(stylus.single.copyWith(title: 'Portada v2'));
    expect((await repo.watchAll().first).first.title, 'Portada v2');

    await repo.delete(id);
    expect(await repo.watchCount().first, 1);
  });

  test('notas: búsqueda, checklist ordenada y borrado en cascada', () async {
    final notes = NotesRepository(db);
    final id = await notes.create(category: NoteCategory.reunion);
    await notes.patch(id, title: 'Kickoff', body: 'Paleta de marca');
    await notes.create();

    expect((await notes.watchAll(query: 'paleta').first).single.id, id);
    expect((await notes.watchAll(category: NoteCategory.idea).first).length, 1);

    await notes.addChecklistItem(id, 'Primero');
    await notes.addChecklistItem(id, 'Segundo');
    final items = await notes.watchChecklist(id).first;
    expect(items.map((i) => i.content), ['Primero', 'Segundo']);

    await notes.setChecklistDone(items.first, true);
    expect((await notes.watchChecklist(id).first).first.done, isTrue);

    await notes.delete(id);
    expect(await db.select(db.checklistItems).get(), isEmpty);
  });

  test('borrar un proyecto desvincula sus notas', () async {
    final projectId = await ProjectsRepository(
      db,
    ).create(title: 'P', kind: ProjectKind.lienzo);
    final notes = NotesRepository(db);
    final noteId = await notes.create(projectId: projectId);
    await ProjectsRepository(db).delete(projectId);
    expect((await notes.watchOne(noteId).first)!.projectId, isNull);
  });

  test('programar trabajo lo deja como evento de todo el día', () async {
    final project = await ProjectsRepository(
      db,
    ).create(title: 'Calendario', kind: ProjectKind.lienzo);
    final work = WorkItemsRepository(db);
    final id = await work.create(projectId: project, title: 'Preparar demo');
    final item = (await work.watchAll(projectId: project).first).single;
    await work.scheduleAllDay(item, DateTime(2026, 9, 22));
    final scheduled = await work.get(id);
    expect(scheduled!.dueAt, isNull);
    expect(scheduled.dueDay, '2026-09-22');
  });

  test(
    'tareas: pendientes con prioridad primero y restaurar tras borrar',
    () async {
      final tasks = TasksRepository(db);
      await tasks.create(title: 'Normal');
      await tasks.create(title: 'Urgente', highPriority: true);
      final doneId = await tasks.create(title: 'Hecha');
      final hecha = (await tasks.watchAll().first).firstWhere(
        (t) => t.id == doneId,
      );
      await tasks.setDone(hecha, true);

      final ordered = await tasks.watchAll().first;
      expect(ordered.map((t) => t.title), ['Urgente', 'Normal', 'Hecha']);
      expect(ordered.last.completedAt, isNotNull);

      await tasks.delete(ordered.first.id);
      await tasks.restore(ordered.first);
      expect((await tasks.watchAll().first).first.title, 'Urgente');
    },
  );

  test('eventos: rango semiabierto', () async {
    final events = EventsRepository(db);
    final day = DateTime(2026, 9, 14);
    await events.create(
      title: 'A',
      startsAt: day.add(const Duration(hours: 9)),
      tag: EventTag.nota,
    );
    await events.create(
      title: 'B',
      startsAt: addDays(day, 1),
      tag: EventTag.nota,
    );
    expect(
      (await events.watchRange(day, addDays(day, 1)).first).map((e) => e.title),
      ['A'],
    );
  });

  test('las fechas relativas se leen en español', () {
    final now = DateTime(2026, 9, 14, 18);
    expect(
      relativeTime(now.subtract(const Duration(minutes: 15)), now: now),
      'Hace 15 min',
    );
    expect(
      relativeTime(now.subtract(const Duration(hours: 1)), now: now),
      'Hace 1 hora',
    );
    expect(relativeTime(DateTime(2026, 9, 13, 23), now: now), 'Ayer');
    expect(relativeTime(DateTime(2026, 9, 1), now: now), '1 Septiembre');
    expect(longDay(DateTime(2026, 9, 14)), 'Lunes, 14 Septiembre');
    expect(startOfWeek(DateTime(2026, 9, 17)), DateTime(2026, 9, 14));
  });
}
