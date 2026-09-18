import 'package:drift/drift.dart';

import 'db/database.dart';
import 'enums.dart';

typedef NoteSnapshot = ({Note note, List<ChecklistItem> items});

class ProjectsRepository {
  ProjectsRepository(this._db);

  final AppDatabase _db;

  Stream<List<Project>> watchAll({ProjectKind? kind}) {
    final q = _db.select(_db.projects)
      ..orderBy([(p) => OrderingTerm.desc(p.updatedAt)]);
    if (kind != null) q.where((p) => p.kind.equalsValue(kind));
    return q.watch();
  }

  Stream<int> watchCount() => _count(_db, _db.projects).watchSingle();

  Stream<Project?> watchOne(int id) => (_db.select(
    _db.projects,
  )..where((p) => p.id.equals(id))).watchSingleOrNull();

  Future<int> create({
    required String title,
    required ProjectKind kind,
    String description = '',
    List<String> tags = const [],
    String? imageAsset,
  }) {
    return _db
        .into(_db.projects)
        .insert(
          ProjectsCompanion.insert(
            title: title,
            kind: kind,
            description: Value(description),
            tags: Value(tags),
            imageAsset: Value(imageAsset),
          ),
        );
  }

  Future<void> update(Project project) {
    return _db
        .update(_db.projects)
        .replace(project.copyWith(updatedAt: DateTime.now()));
  }

  Future<void> delete(int id) =>
      (_db.delete(_db.projects)..where((p) => p.id.equals(id))).go();
}

class NotesRepository {
  NotesRepository(this._db);

  final AppDatabase _db;

  /// Notas más recientes primero, filtradas por categoría y texto.
  Stream<List<Note>> watchAll({
    NoteCategory? category,
    String query = '',
    int? projectId,
  }) {
    final q = _db.select(_db.notes)
      ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)]);
    if (category != null) q.where((n) => n.category.equalsValue(category));
    if (projectId != null) q.where((n) => n.projectId.equals(projectId));
    final text = query.trim();
    if (text.isNotEmpty) {
      q.where(
        (n) =>
            n.title.contains(text) |
            n.body.contains(text) |
            n.keyIdea.contains(text),
      );
    }
    return q.watch();
  }

  Stream<Note?> watchOne(int id) => (_db.select(
    _db.notes,
  )..where((n) => n.id.equals(id))).watchSingleOrNull();

  Stream<int> watchCount() => _count(_db, _db.notes).watchSingle();

  Future<int> create({
    NoteCategory category = NoteCategory.idea,
    int? projectId,
  }) {
    return _db
        .into(_db.notes)
        .insert(
          NotesCompanion.insert(
            category: category,
            projectId: Value(projectId),
          ),
        );
  }

  /// Guarda sólo los campos indicados y marca la nota como editada.
  Future<void> patch(
    int id, {
    String? title,
    String? keyIdea,
    String? body,
    NoteCategory? category,
    Value<int?> projectId = const Value.absent(),
  }) {
    return (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        title: Value.absentIfNull(title),
        keyIdea: Value.absentIfNull(keyIdea),
        body: Value.absentIfNull(body),
        category: Value.absentIfNull(category),
        projectId: projectId,
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Mueve la nota a un proyecto (o la saca, con `null`).
  Future<void> setProject(int id, int? projectId) =>
      (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
        NotesCompanion(projectId: Value(projectId)),
      );

  Future<Note?> get(int id) =>
      (_db.select(_db.notes)..where((n) => n.id.equals(id))).getSingleOrNull();

  Future<List<ChecklistItem>> checklist(int noteId) =>
      (_db.select(_db.checklistItems)
            ..where((c) => c.noteId.equals(noteId))
            ..orderBy([(c) => OrderingTerm.asc(c.position)]))
          .get();

  /// Guarda la página de la nota y su texto plano.
  Future<void> saveContent(
    int id, {
    required String title,
    required String content,
    required String body,
  }) {
    return (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        title: Value(title),
        content: Value(content),
        body: Value(body),
        keyIdea: const Value(''),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> delete(int id) =>
      (_db.delete(_db.notes)..where((n) => n.id.equals(id))).go();

  /// Borra la nota y devuelve lo necesario para [restore]la con su checklist.
  Future<NoteSnapshot> deleteWithSnapshot(int id) {
    return _db.transaction(() async {
      final note = await (_db.select(
        _db.notes,
      )..where((n) => n.id.equals(id))).getSingle();
      final items = await (_db.select(
        _db.checklistItems,
      )..where((c) => c.noteId.equals(id))).get();
      await delete(id);
      return (note: note, items: items);
    });
  }

  Future<void> restore(NoteSnapshot snapshot) {
    return _db.transaction(() async {
      await _db.into(_db.notes).insert(snapshot.note);
      for (final item in snapshot.items) {
        await _db.into(_db.checklistItems).insert(item);
      }
    });
  }

  // ---- Checklist ----

  Stream<List<ChecklistItem>> watchChecklist(int noteId) {
    return (_db.select(_db.checklistItems)
          ..where((c) => c.noteId.equals(noteId))
          ..orderBy([(c) => OrderingTerm.asc(c.position)]))
        .watch();
  }

  Future<void> addChecklistItem(int noteId, String content) async {
    final maxPos = _db.checklistItems.position.max();
    final row =
        await (_db.selectOnly(_db.checklistItems)
              ..addColumns([maxPos])
              ..where(_db.checklistItems.noteId.equals(noteId)))
            .getSingle();
    await _db
        .into(_db.checklistItems)
        .insert(
          ChecklistItemsCompanion.insert(
            noteId: noteId,
            content: content,
            position: (row.read(maxPos) ?? -1) + 1,
          ),
        );
    await _touch(noteId);
  }

  Future<void> setChecklistDone(ChecklistItem item, bool done) async {
    await (_db.update(_db.checklistItems)..where((c) => c.id.equals(item.id)))
        .write(ChecklistItemsCompanion(done: Value(done)));
    await _touch(item.noteId);
  }

  Future<void> deleteChecklistItem(ChecklistItem item) async {
    await (_db.delete(
      _db.checklistItems,
    )..where((c) => c.id.equals(item.id))).go();
    await _touch(item.noteId);
  }

  Future<void> _touch(int noteId) {
    return (_db.update(_db.notes)..where((n) => n.id.equals(noteId))).write(
      NotesCompanion(updatedAt: Value(DateTime.now())),
    );
  }
}

class TasksRepository {
  TasksRepository(this._db);

  final AppDatabase _db;

  /// Pendientes primero (prioridad alta arriba), luego completadas.
  Stream<List<QuickTask>> watchAll({int? projectId}) {
    return (_db.select(_db.tasks)
          ..where(
            (t) => projectId == null
                ? const Constant(true)
                : t.projectId.equals(projectId),
          )
          ..orderBy([
            (t) => OrderingTerm.asc(t.done),
            (t) => OrderingTerm.desc(t.highPriority),
            (t) => OrderingTerm.desc(t.createdAt),
          ]))
        .watch();
  }

  Future<int> create({
    required String title,
    String detail = '',
    String? label,
    bool highPriority = false,
    int? projectId,
    int? requirementId,
    DateTime? remindAt,
  }) async {
    await _validateRequirement(projectId, requirementId);
    return _db
        .into(_db.tasks)
        .insert(
          TasksCompanion.insert(
            title: title,
            detail: Value(detail),
            label: Value(label),
            highPriority: Value(highPriority),
            remindAt: Value(remindAt),
            projectId: Value(projectId),
            requirementId: Value(requirementId),
          ),
        );
  }

  Future<List<QuickTask>> all() => _db.select(_db.tasks).get();

  Future<QuickTask?> get(int id) =>
      (_db.select(_db.tasks)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Guarda el identificador del recordatorio de Apple sin tocar nada más.
  Future<void> setAppleReminderId(int id, String? identifier) =>
      (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
        TasksCompanion(appleReminderId: Value(identifier)),
      );

  Future<void> update(QuickTask task) async {
    await _validateRequirement(task.projectId, task.requirementId);
    await _db.update(_db.tasks).replace(task);
  }

  /// Mueve la tarea a un proyecto (o la saca, con `null`).
  Future<void> setProject(int id, int? projectId) async {
    final task = await get(id);
    if (task == null) return;
    // Una tarea nunca conserva un vínculo incompatible al cambiar de proyecto.
    final keepLink =
        task.requirementId != null &&
        await _isCompatibleRequirement(projectId, task.requirementId!);
    await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        projectId: Value(projectId),
        requirementId: Value(keepLink ? task.requirementId : null),
      ),
    );
  }

  Future<void> setRequirement(int id, int? requirementId) async {
    final task = await get(id);
    if (task == null) return;
    await _validateRequirement(task.projectId, requirementId);
    await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(requirementId: Value(requirementId)),
    );
  }

  Stream<List<QuickTask>> watchForRequirement(int requirementId) =>
      (_db.select(_db.tasks)
            ..where((t) => t.requirementId.equals(requirementId))
            ..orderBy([
              (t) => OrderingTerm.asc(t.done),
              (t) => OrderingTerm.desc(t.createdAt),
            ]))
          .watch();

  Future<void> _validateRequirement(int? projectId, int? requirementId) async {
    if (requirementId == null) return;
    if (!await _isCompatibleRequirement(projectId, requirementId)) {
      throw ArgumentError(
        'La tarea debe enlazarse a un requerimiento del mismo proyecto.',
      );
    }
  }

  Future<bool> _isCompatibleRequirement(int? projectId, int id) async {
    if (projectId == null) return false;
    final requirement = await (_db.select(
      _db.workItems,
    )..where((w) => w.id.equals(id))).getSingleOrNull();
    return requirement != null &&
        requirement.kind == 'requirement' &&
        requirement.projectId == projectId;
  }

  Future<void> setDone(QuickTask task, bool done) {
    return (_db.update(_db.tasks)..where((t) => t.id.equals(task.id))).write(
      TasksCompanion(
        done: Value(done),
        completedAt: Value(done ? DateTime.now() : null),
      ),
    );
  }

  Future<void> delete(int id) =>
      (_db.delete(_db.tasks)..where((t) => t.id.equals(id))).go();

  /// Reinserta una tarea borrada (para "Deshacer").
  Future<void> restore(QuickTask task) => _db.into(_db.tasks).insert(task);
}

class EventsRepository {
  EventsRepository(this._db);

  final AppDatabase _db;

  /// Eventos con inicio en [from, to).
  Stream<List<CalendarEvent>> watchRange(DateTime from, DateTime to) {
    return (_db.select(_db.events)
          ..where(
            (e) =>
                e.startsAt.isBiggerOrEqualValue(from) &
                e.startsAt.isSmallerThanValue(to),
          )
          ..orderBy([(e) => OrderingTerm.asc(e.startsAt)]))
        .watch();
  }

  Future<int> create({
    required String title,
    required DateTime startsAt,
    required EventTag tag,
    String detail = '',
    int? projectId,
  }) {
    return _db
        .into(_db.events)
        .insert(
          EventsCompanion.insert(
            title: title,
            startsAt: startsAt,
            tag: tag,
            detail: Value(detail),
            projectId: Value(projectId),
          ),
        );
  }

  Future<void> update(CalendarEvent event) =>
      _db.update(_db.events).replace(event);

  Future<void> delete(int id) =>
      (_db.delete(_db.events)..where((e) => e.id.equals(id))).go();

  Future<void> restore(CalendarEvent event) =>
      _db.into(_db.events).insert(event);
}

class CanvasesRepository {
  CanvasesRepository(this._db);

  final AppDatabase _db;

  Stream<List<CanvasRecord>> watchAll({int? projectId}) {
    final q = _db.select(_db.canvases)
      ..orderBy([(c) => OrderingTerm.desc(c.updatedAt)]);
    if (projectId != null) q.where((c) => c.projectId.equals(projectId));
    return q.watch();
  }

  /// Mueve el lienzo a un proyecto (o lo saca, con `null`).
  Future<void> setProject(int id, int? projectId) =>
      (_db.update(_db.canvases)..where((c) => c.id.equals(id))).write(
        CanvasesCompanion(projectId: Value(projectId)),
      );

  Future<CanvasRecord?> get(int id) => (_db.select(
    _db.canvases,
  )..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<int> create({
    String title = 'Lienzo sin título',
    String data = '',
    int? projectId,
  }) async {
    if (projectId != null &&
        await (_db.select(
              _db.projects,
            )..where((p) => p.id.equals(projectId))).getSingleOrNull() ==
            null) {
      throw ArgumentError('El proyecto de destino no existe.');
    }
    return _db
        .into(_db.canvases)
        .insert(
          CanvasesCompanion.insert(
            title: title,
            data: Value(data),
            projectId: Value(projectId),
          ),
        );
  }

  Future<void> save(int id, {required String title, required String data}) {
    return (_db.update(_db.canvases)..where((c) => c.id.equals(id))).write(
      CanvasesCompanion(
        title: Value(title),
        data: Value(data),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> rename(int id, String title) =>
      (_db.update(_db.canvases)..where((c) => c.id.equals(id))).write(
        CanvasesCompanion(
          title: Value(title),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<void> delete(int id) =>
      (_db.delete(_db.canvases)..where((c) => c.id.equals(id))).go();

  Future<void> restore(CanvasRecord record) =>
      _db.into(_db.canvases).insert(record);
}

class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  Future<String?> get(String key) async => (await (_db.select(
    _db.appSettings,
  )..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  Future<void> set(String key, String value) => _db
      .into(_db.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: key, value: value),
      );
}

Selectable<int> _count(AppDatabase db, TableInfo<Table, dynamic> table) {
  final count = countAll();
  return (db.selectOnly(
    table,
  )..addColumns([count])).map((row) => row.read(count)!);
}

class WorkItemsRepository {
  WorkItemsRepository(this._db);
  final AppDatabase _db;
  Stream<List<WorkItem>> watchAll({int? projectId}) =>
      (_db.select(_db.workItems)
            ..where(
              (w) => projectId == null
                  ? const Constant(true)
                  : w.projectId.equals(projectId),
            )
            ..orderBy([(w) => OrderingTerm.asc(w.id)]))
          .watch();
  Stream<List<RequirementColumn>> watchColumns(int projectId) =>
      (_db.select(_db.requirementColumns)
            ..where((c) => c.projectId.equals(projectId))
            ..orderBy([(c) => OrderingTerm.asc(c.position)]))
          .watch();
  Stream<List<RequirementHistoryData>> watchHistory(int requirementId) =>
      (_db.select(_db.requirementHistory)
            ..where((h) => h.requirementId.equals(requirementId))
            ..orderBy([(h) => OrderingTerm.desc(h.createdAt)]))
          .watch();
  Future<WorkItem?> get(int id) => (_db.select(
    _db.workItems,
  )..where((w) => w.id.equals(id))).getSingleOrNull();
  Future<int> create({
    required int projectId,
    required String title,
    String description = '',
    String acceptance = '',
    String kind = 'activity',
    String status = 'todo',
    int? parentId,
    DateTime? dueAt,
    String? dueDay,
    int? columnId,
    int position = 0,
    List<String> labels = const [],
    String priority = 'normal',
  }) async {
    if (title.trim().isEmpty || title.trim().length > 200)
      throw ArgumentError('El título debe tener entre 1 y 200 caracteres.');
    if (!['todo', 'doing', 'done'].contains(status))
      throw ArgumentError('Estado desconocido.');
    if (!['activity', 'requirement'].contains(kind))
      throw ArgumentError('Tipo desconocido.');
    if (parentId != null) {
      final parent = await get(parentId);
      if (parent == null ||
          parent.projectId != projectId ||
          parent.kind != kind) {
        throw ArgumentError(
          'El elemento padre debe pertenecer al mismo proyecto y tipo.',
        );
      }
    }
    if (dueAt != null && dueDay != null) {
      throw ArgumentError(
        'Un vencimiento no puede tener hora y todo el día a la vez.',
      );
    }
    int? resolvedColumn = columnId;
    if (kind == 'requirement') {
      final columns = await ensureDefaultColumns(projectId);
      resolvedColumn ??= columns
          .firstWhere((c) => c.category == status, orElse: () => columns.first)
          .id;
      await _validateColumn(projectId, resolvedColumn);
    }
    final id = await _db
        .into(_db.workItems)
        .insert(
          WorkItemsCompanion.insert(
            projectId: projectId,
            title: title.trim(),
            description: Value(description),
            acceptance: Value(acceptance),
            kind: Value(kind),
            status: Value(status),
            parentId: Value(parentId),
            dueAt: Value(dueAt),
            dueDay: Value(dueDay),
            columnId: Value(resolvedColumn),
            position: Value(position),
            labels: Value(labels),
            priority: Value(priority),
          ),
        );
    if (kind == 'requirement') {
      await addHistory(id, 'created', 'Requerimiento creado');
    }
    return id;
  }

  Future<void> update(WorkItem item) async {
    if (!['todo', 'doing', 'done'].contains(item.status))
      throw ArgumentError('Estado desconocido.');
    if (item.title.trim().isEmpty || item.title.length > 200)
      throw ArgumentError('Título inválido.');
    if (item.dueAt != null && item.dueDay != null) {
      throw ArgumentError(
        'Un vencimiento no puede tener hora y todo el día a la vez.',
      );
    }
    if (item.parentId != null) await _validateParent(item, item.parentId!);
    final saved = item.kind == 'requirement'
        ? await _requirementWithColumn(item)
        : item;
    if (saved.kind == 'requirement') {
      await _validateColumn(saved.projectId, saved.columnId);
    }
    await _db.update(_db.workItems).replace(saved);
    if (item.kind == 'requirement' && saved.columnId != item.columnId) {
      await addHistory(saved.id, 'moved', 'Movido de estado');
    }
  }

  /// Programa un elemento en una fecha civil. El calendario no inventa una
  /// hora: deja esa decisión para el editor del elemento.
  Future<void> scheduleAllDay(WorkItem item, DateTime day) async {
    final value =
        '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    await (_db.update(_db.workItems)..where((w) => w.id.equals(item.id))).write(
      WorkItemsCompanion(dueAt: const Value(null), dueDay: Value(value)),
    );
    if (item.kind == 'requirement') {
      await addHistory(item.id, 'scheduled', 'Programado para $value');
    }
  }

  Future<void> delete(int id) =>
      (_db.delete(_db.workItems)..where((w) => w.id.equals(id))).go();

  Future<List<RequirementColumn>> ensureDefaultColumns(int projectId) async {
    var existing = await _columnsOf(projectId);
    if (existing.isEmpty) {
      await _db.batch((batch) {
        for (final (index, definition) in const [
          ('Por hacer', '#6C8CFF', 'todo'),
          ('En curso', '#E0A458', 'doing'),
          ('Terminado', '#76B798', 'done'),
        ].indexed) {
          batch.insert(
            _db.requirementColumns,
            RequirementColumnsCompanion.insert(
              projectId: projectId,
              title: definition.$1,
              color: Value(definition.$2),
              category: Value(definition.$3),
              position: Value(index),
            ),
          );
        }
      });
      existing = await _columnsOf(projectId);
    }
    await _placeOrphanRequirements(projectId, existing);
    return existing;
  }

  Future<int> createColumn({
    required int projectId,
    required String title,
    String color = '#6C8CFF',
    String category = 'todo',
  }) async {
    final columns = await ensureDefaultColumns(projectId);
    return _db
        .into(_db.requirementColumns)
        .insert(
          RequirementColumnsCompanion.insert(
            projectId: projectId,
            title: title.trim(),
            color: Value(color),
            category: Value(category),
            position: Value(columns.length),
          ),
        );
  }

  Future<void> updateColumn(RequirementColumn column) =>
      _db.update(_db.requirementColumns).replace(column);

  Future<void> moveRequirement(
    WorkItem item,
    int columnId, {
    int? position,
  }) async {
    await _validateColumn(item.projectId, columnId);
    final column = await (_db.select(
      _db.requirementColumns,
    )..where((c) => c.id.equals(columnId))).getSingle();
    await (_db.update(_db.workItems)..where((w) => w.id.equals(item.id))).write(
      WorkItemsCompanion(
        columnId: Value(columnId),
        status: Value(_statusFromColumn(column.category, item.status)),
        position: Value(position ?? item.position),
      ),
    );
    await addHistory(item.id, 'moved', 'Movido de estado');
  }

  Future<void> deleteColumn(int columnId, {required int moveToColumnId}) async {
    if (columnId == moveToColumnId)
      throw ArgumentError('Elige otra columna de destino.');
    await _db.transaction(() async {
      final source = await (_db.select(
        _db.requirementColumns,
      )..where((c) => c.id.equals(columnId))).getSingleOrNull();
      if (source == null) return;
      await _validateColumn(source.projectId, moveToColumnId);
      final destination = await (_db.select(
        _db.requirementColumns,
      )..where((c) => c.id.equals(moveToColumnId))).getSingle();
      await (_db.update(
        _db.workItems,
      )..where((w) => w.columnId.equals(columnId))).write(
        WorkItemsCompanion(
          columnId: Value(moveToColumnId),
          status: Value(_statusFromColumn(destination.category, 'todo')),
        ),
      );
      await (_db.delete(
        _db.requirementColumns,
      )..where((c) => c.id.equals(columnId))).go();
    });
  }

  Future<void> addHistory(int requirementId, String kind, String message) => _db
      .into(_db.requirementHistory)
      .insert(
        RequirementHistoryCompanion.insert(
          requirementId: requirementId,
          kind: Value(kind),
          message: message.trim(),
        ),
      );

  Future<List<RequirementColumn>> _columnsOf(int projectId) =>
      (_db.select(_db.requirementColumns)
            ..where((c) => c.projectId.equals(projectId))
            ..orderBy([(c) => OrderingTerm.asc(c.position)]))
          .get();

  Future<void> _placeOrphanRequirements(
    int projectId,
    List<RequirementColumn> columns,
  ) async {
    if (columns.isEmpty) return;
    final valid = {for (final column in columns) column.id};
    final items =
        await (_db.select(_db.workItems)..where(
              (w) =>
                  w.projectId.equals(projectId) & w.kind.equals('requirement'),
            ))
            .get();
    for (final item in items) {
      if (item.columnId != null && valid.contains(item.columnId)) continue;
      final column = columns.firstWhere(
        (c) => c.category == item.status,
        orElse: () => columns.first,
      );
      await (_db.update(_db.workItems)..where((w) => w.id.equals(item.id)))
          .write(WorkItemsCompanion(columnId: Value(column.id)));
    }
  }

  Future<WorkItem> _requirementWithColumn(WorkItem item) async {
    final columns = await ensureDefaultColumns(item.projectId);
    final current = columns.where((c) => c.id == item.columnId).firstOrNull;
    if (current != null && current.category == item.status) return item;
    final match = columns.firstWhere(
      (c) => c.category == item.status,
      orElse: () => columns.first,
    );
    return item.copyWith(columnId: Value(match.id));
  }

  static String _statusFromColumn(String category, String fallback) =>
      ['todo', 'doing', 'done'].contains(category) ? category : fallback;

  Future<void> _validateColumn(int projectId, int? columnId) async {
    if (columnId == null)
      throw ArgumentError('El requerimiento necesita una columna.');
    final column = await (_db.select(
      _db.requirementColumns,
    )..where((c) => c.id.equals(columnId))).getSingleOrNull();
    if (column == null || column.projectId != projectId)
      throw ArgumentError('La columna no pertenece al proyecto.');
  }

  Future<void> _validateParent(WorkItem item, int parentId) async {
    if (parentId == item.id)
      throw ArgumentError('Un elemento no puede ser su propio padre.');
    var cursor = await get(parentId);
    while (cursor != null) {
      if (cursor.projectId != item.projectId || cursor.kind != item.kind) {
        throw ArgumentError(
          'El padre debe pertenecer al mismo proyecto y tipo.',
        );
      }
      if (cursor.id == item.id) throw ArgumentError('El cambio crea un ciclo.');
      cursor = cursor.parentId == null ? null : await get(cursor.parentId!);
    }
  }
}
