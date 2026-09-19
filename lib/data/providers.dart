import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme_controller.dart';
import '../utils/dates.dart';
import 'db/database.dart';
import 'enums.dart';
import 'repositories.dart';
import '../features/reminders/reminder_service.dart';

/// Se sobrescribe en `main` (y en los tests con una base en memoria).
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider sin inicializar'),
);

final projectsRepositoryProvider = Provider(
  (ref) => ProjectsRepository(ref.watch(databaseProvider)),
);
final notesRepositoryProvider = Provider(
  (ref) => NotesRepository(ref.watch(databaseProvider)),
);
final tasksRepositoryProvider = Provider(
  (ref) => TasksRepository(ref.watch(databaseProvider)),
);
final canvasesRepositoryProvider = Provider(
  (ref) => CanvasesRepository(ref.watch(databaseProvider)),
);
final eventsRepositoryProvider = Provider(
  (ref) => EventsRepository(ref.watch(databaseProvider)),
);
final settingsRepositoryProvider = Provider(
  (ref) => SettingsRepository(ref.watch(databaseProvider)),
);

/// Claro u oscuro (Gruvbox). Lo aplica `KraftApp`.
final themeProvider = ChangeNotifierProvider((ref) {
  final controller = ThemeController(ref.watch(settingsRepositoryProvider));
  controller.load();
  return controller;
});

/// Avisos de tareas con hora. Se arranca con la app (ver `KraftApp`).
final reminderServiceProvider = ChangeNotifierProvider((ref) {
  final service = ReminderService(
    tasks: ref.watch(tasksRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
  );
  service.start();
  return service;
});

// ---- Proyectos ----

final projectsProvider = StreamProvider.family<List<Project>, ProjectKind?>(
  (ref, kind) => ref.watch(projectsRepositoryProvider).watchAll(kind: kind),
);
final projectCountProvider = StreamProvider(
  (ref) => ref.watch(projectsRepositoryProvider).watchCount(),
);

// ---- Notas ----

final noteCategoryFilterProvider = StateProvider<NoteCategory?>((ref) => null);
final noteQueryProvider = StateProvider<String>((ref) => '');

final notesProvider = StreamProvider((ref) {
  return ref
      .watch(notesRepositoryProvider)
      .watchAll(
        category: ref.watch(noteCategoryFilterProvider),
        query: ref.watch(noteQueryProvider),
      );
});
final allNotesProvider = StreamProvider(
  (ref) => ref.watch(notesRepositoryProvider).watchAll(),
);
final noteCountProvider = StreamProvider(
  (ref) => ref.watch(notesRepositoryProvider).watchCount(),
);

// ---- Lienzos ----

final canvasesProvider = StreamProvider(
  (ref) => ref.watch(canvasesRepositoryProvider).watchAll(),
);

// ---- Contenido de un proyecto ----

/// Lo que hay dentro de un proyecto. Las tres tablas guardan `projectId`, así que
/// un proyecto es de verdad una carpeta, no una etiqueta suelta.
final projectProvider = StreamProvider.family<Project?, int>(
  (ref, id) => ref.watch(projectsRepositoryProvider).watchOne(id),
);

final projectNotesProvider = StreamProvider.family<List<Note>, int>(
  (ref, id) => ref.watch(notesRepositoryProvider).watchAll(projectId: id),
);

final projectCanvasesProvider = StreamProvider.family<List<CanvasRecord>, int>(
  (ref, id) => ref.watch(canvasesRepositoryProvider).watchAll(projectId: id),
);

final projectTasksProvider = StreamProvider.family<List<QuickTask>, int>(
  (ref, id) => ref.watch(tasksRepositoryProvider).watchAll(projectId: id),
);
final requirementTasksProvider = StreamProvider.family<List<QuickTask>, int>(
  (ref, id) => ref.watch(tasksRepositoryProvider).watchForRequirement(id),
);

/// Cuántas cosas tiene cada proyecto, para las tarjetas.
typedef ProjectCounts = ({int notes, int canvases, int tasks});

final projectCountsProvider = Provider<Map<int, ProjectCounts>>((ref) {
  final notes = ref.watch(allNotesProvider).valueOrNull ?? const [];
  final canvases = ref.watch(canvasesProvider).valueOrNull ?? const [];
  final tasks = ref.watch(tasksProvider).valueOrNull ?? const [];
  final counts = <int, ProjectCounts>{};
  void bump(int? id, {int n = 0, int c = 0, int t = 0}) {
    if (id == null) return;
    final now = counts[id] ?? (notes: 0, canvases: 0, tasks: 0);
    counts[id] = (
      notes: now.notes + n,
      canvases: now.canvases + c,
      tasks: now.tasks + t,
    );
  }

  for (final x in notes) {
    bump(x.projectId, n: 1);
  }
  for (final x in canvases) {
    bump(x.projectId, c: 1);
  }
  for (final x in tasks) {
    bump(x.projectId, t: 1);
  }
  return counts;
});

// ---- Tareas ----

final tasksProvider = StreamProvider(
  (ref) => ref.watch(tasksRepositoryProvider).watchAll(),
);

// ---- Calendario ----

enum CalendarMode { week, month }

final calendarModeProvider = StateProvider((ref) => CalendarMode.week);
final selectedDayProvider = StateProvider((ref) => dateOnly(DateTime.now()));

/// Rango que se ve en el cronograma: la semana o el mes del día seleccionado.
final visibleRangeProvider = Provider<(DateTime, DateTime)>((ref) {
  final day = ref.watch(selectedDayProvider);
  final mode = ref.watch(calendarModeProvider);
  return switch (mode) {
    CalendarMode.week => (startOfWeek(day), addDays(startOfWeek(day), 7)),
    CalendarMode.month => (
      startOfWeek(startOfMonth(day)),
      addDays(startOfWeek(startOfMonth(day)), 42),
    ),
  };
});

/// Eventos del rango visible (semana o mes que contiene el día seleccionado).
final visibleEventsProvider = StreamProvider((ref) {
  final (from, to) = ref.watch(visibleRangeProvider);
  return ref.watch(eventsRepositoryProvider).watchRange(from, to);
});

/// Una fila del cronograma. Las citas viven en `calendarEvents` y los recordatorios en `tasks`:
/// aquí se juntan sólo para pintarlos, sin copiar nada. Cada uno se sigue editando en su hoja.
sealed class ScheduleEntry {
  const ScheduleEntry();

  DateTime get startsAt;
  String get title;
  String get detail;

  /// Clave estable para las animaciones de lista (los ids se repiten entre tablas).
  String get key;
  bool get allDay => false;
}

class EventEntry extends ScheduleEntry {
  const EventEntry(this.event);
  final CalendarEvent event;

  @override
  DateTime get startsAt => event.startsAt;
  @override
  String get title => event.title;
  @override
  String get detail => event.detail;
  @override
  String get key => 'event-${event.id}';
}

class TaskEntry extends ScheduleEntry {
  const TaskEntry(this.task);
  final QuickTask task;

  @override
  DateTime get startsAt => task.remindAt!;
  @override
  String get title => task.title;
  @override
  String get detail => task.detail;
  @override
  String get key => 'task-${task.id}';
}

class WorkEntry extends ScheduleEntry {
  const WorkEntry(this.item);
  final WorkItem item;
  @override
  DateTime get startsAt => item.dueAt ?? DateTime.parse(item.dueDay!);
  @override
  bool get allDay => item.dueDay != null;
  @override
  String get title => item.title;
  @override
  String get detail => item.description;
  @override
  String get key => 'work-${item.id}';
}

final calendarProjectFilterProvider = StateProvider<int?>((ref) => null);

/// Citas y recordatorios del rango visible, ordenados por hora.
final visibleScheduleProvider = Provider<List<ScheduleEntry>>((ref) {
  final (from, to) = ref.watch(visibleRangeProvider);
  final events = ref.watch(visibleEventsProvider).valueOrNull ?? const [];
  final tasks = ref.watch(tasksProvider).valueOrNull ?? const [];
  final work = ref.watch(allWorkItemsProvider).valueOrNull ?? const [];
  final project = ref.watch(calendarProjectFilterProvider);
  return [
    for (final w in work)
      if ((w.dueAt != null || w.dueDay != null) &&
          !WorkEntry(w).startsAt.isBefore(from) &&
          WorkEntry(w).startsAt.isBefore(to) &&
          (project == null || w.projectId == project))
        WorkEntry(w),
    for (final e in events)
      if (project == null || e.projectId == project) EventEntry(e),
    for (final t in tasks)
      if (t.remindAt case final at?
          when !at.isBefore(from) &&
              at.isBefore(to) &&
              (project == null || t.projectId == project))
        TaskEntry(t),
  ]..sort(
    (a, b) => a.allDay == b.allDay
        ? a.startsAt.compareTo(b.startsAt)
        : a.allDay
        ? -1
        : 1,
  );
});

final workItemsRepositoryProvider = Provider(
  (ref) => WorkItemsRepository(ref.watch(databaseProvider)),
);
final projectWorkItemsProvider = StreamProvider.family<List<WorkItem>, int>(
  (ref, id) => ref.watch(workItemsRepositoryProvider).watchAll(projectId: id),
);
final requirementColumnsProvider =
    StreamProvider.family<List<RequirementColumn>, int>((ref, id) async* {
      await ref.read(workItemsRepositoryProvider).ensureDefaultColumns(id);
      yield* ref.watch(workItemsRepositoryProvider).watchColumns(id);
    });
final requirementHistoryProvider =
    StreamProvider.family<List<RequirementHistoryData>, int>(
      (ref, id) => ref.watch(workItemsRepositoryProvider).watchHistory(id),
    );
final allWorkItemsProvider = StreamProvider(
  (ref) => ref.watch(workItemsRepositoryProvider).watchAll(),
);
