import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../enums.dart';
import 'seed.dart';
import 'tables.dart';

export 'tables.dart' show TagsConverter;

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Projects,
    Notes,
    ChecklistItems,
    Tasks,
    Events,
    Canvases,
    AppSettings,
    WorkItems,
    RequirementColumns,
    WorkItemLinks,
    RequirementHistory,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// [seed] rellena la base recién creada con el contenido de ejemplo.
  AppDatabase(super.executor, {this.seed = true});

  /// Base de datos persistente en el directorio de documentos de la app.
  factory AppDatabase.onDevice() => AppDatabase(driftDatabase(name: 'kraft'));

  final bool seed;

  @override
  // v2: tabla de lienzos. v3: ajustes. v4: contenido de notas. v5: recordatorios de tareas.
  // v6: las tareas también pueden pertenecer a un proyecto.
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      if (seed) await seedDatabase(this, DateTime.now());
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(canvases);
        // Las bases existentes también reciben el boceto de ejemplo.
        if (seed) await seedCanvas(this);
      }
      if (from < 3) await m.createTable(appSettings);
      if (from < 4) await m.addColumn(notes, notes.content);
      if (from < 5) {
        await m.addColumn(tasks, tasks.remindAt);
        await m.addColumn(tasks, tasks.appleReminderId);
      }
      if (from < 7) await m.createTable(workItems);
      if (from < 6) await m.addColumn(tasks, tasks.projectId);
      if (from < 8) {
        // En instalaciones antiguas WorkItems se acaba de crear con el esquema
        // nuevo; sólo añadimos columnas cuando la tabla ya existía en v7.
        if (from >= 7) {
          await m.addColumn(tasks, tasks.requirementId);
          await m.addColumn(workItems, workItems.columnId);
          await m.addColumn(workItems, workItems.position);
          await m.addColumn(workItems, workItems.labels);
          await m.addColumn(workItems, workItems.priority);
          await m.addColumn(workItems, workItems.dueDay);
        }
        await m.createTable(requirementColumns);
        await m.createTable(workItemLinks);
        await m.createTable(requirementHistory);
        // Antes no existía la distinción. Las medianoches heredadas se muestran
        // como vencimientos de todo el día; una medianoche explícita antigua no
        // se puede distinguir de ese caso.
        if (from >= 7) {
          final old = await select(workItems).get();
          for (final item in old) {
            final date = item.dueAt;
            if (date != null && date.hour == 0 && date.minute == 0) {
              await (update(workItems)..where((w) => w.id.equals(item.id))).write(
                WorkItemsCompanion(dueAt: const Value(null), dueDay: Value(
                  '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
                )),
              );
            }
          }
        }
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
