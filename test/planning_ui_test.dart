import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart'
    show DatabaseConnection, Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:kraft/data/providers.dart';
import 'package:kraft/data/repositories.dart';
import 'package:kraft/data/enums.dart';
import 'package:kraft/data/db/database.dart';
import 'package:kraft/features/projects/work_items_panel.dart';
import 'package:kraft/features/notes/note_sketch.dart';
import 'package:kraft/features/canvas/canvas_codec.dart';
import 'package:kraft/theme/kraft_colors.dart';
import 'package:kraft/widgets/filter_pill.dart';
import 'helpers.dart';
import 'package:kraft/features/projects/project_screen.dart';
import 'package:kraft/app/animated_branch_container.dart';

AppDatabase _memoryDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final db = AppDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
    seed: false,
  );
  addTearDown(db.close);
  return db;
}

Future<void> _pumpRequirementsBoard(
  WidgetTester tester,
  AppDatabase db,
  int project,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WorkItemsPanel(projectId: project, requirements: true),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

void main() {
  testWidgets(
    'project bento exposes all sections and fits narrow and wide screens',
    (tester) async {
      final db = await pumpKraft(tester, seed: false);
      late int id;
      await tester.runAsync(() async {
        id = await ProjectsRepository(
          db,
        ).create(title: 'Arquitectura de App', kind: ProjectKind.lienzo);
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            home: Scaffold(body: ProjectScreen(projectId: id)),
          ),
        ),
      );
      await settle(tester);
      for (final label in [
        'Actividades',
        'Requerimientos',
        'Notas',
        'Lienzos',
        'Tareas',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('Notas'));
      await settle(tester);
      expect(find.text('NUEVA NOTA AQUÍ'), findsOneWidget);
      tester.view.physicalSize = const Size(390, 844);
      await settle(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('la vista de tareas agrupa subtareas bajo su requerimiento', (
    tester,
  ) async {
    final db = _memoryDb();
    late int projectId;
    late int requirementId;
    await tester.runAsync(() async {
      final projects = ProjectsRepository(db);
      projectId = await projects.create(
        title: 'Entrega',
        kind: ProjectKind.lienzo,
      );
      final work = WorkItemsRepository(db);
      await work.ensureDefaultColumns(projectId);
      requirementId = await work.create(
        projectId: projectId,
        title: 'Tarea principal',
        kind: 'requirement',
      );
      await TasksRepository(db).create(
        title: 'Primera mini tarea',
        projectId: projectId,
        requirementId: requirementId,
      );
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(body: ProjectScreen(projectId: projectId)),
        ),
      ),
    );
    await settle(tester);
    await tester.ensureVisible(find.text('Tareas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tareas'));
    await settle(tester);
    await tester.ensureVisible(find.text('0/1 subtareas'));
    await tester.pumpAndSettle();

    expect(find.text('Tarea principal'), findsNWidgets(2));
    expect(find.text('Primera mini tarea'), findsNWidgets(2));
    expect(find.text('0/1 subtareas'), findsOneWidget);
    expect(find.text('Añadir subtarea'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'calendar ink stays inside its branch and hidden branches exclude focus',
    (tester) async {
      await pumpKraft(tester);
      final filter = find.byKey(const ValueKey('calendar-project-filter'));
      expect(filter, findsOneWidget);
      final material = tester.widget<Material>(filter);
      expect(material.clipBehavior, Clip.antiAlias);
      final dropdown = find.descendant(
        of: filter,
        matching: find.byType(DropdownButton<int?>),
      );
      expect(
        tester.widget<DropdownButton<int?>>(dropdown).focusColor,
        KraftColors.surfaceContainerHighest,
      );
      await tapNav(tester, 'Lienzo');
      final branches = find.descendant(
        of: find.byType(AnimatedBranchContainer),
        matching: find.byType(ExcludeFocus, skipOffstage: false),
        skipOffstage: false,
      );
      expect(
        tester.widgetList<ExcludeFocus>(branches).any((w) => w.excluding),
        isTrue,
      );
      expect(filter, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('planning form persists requirements and decomposes them', (
    tester,
  ) async {
    final db = _memoryDb();
    late int project;
    await tester.runAsync(() async {
      project = await ProjectsRepository(
        db,
      ).create(title: 'Demo', kind: ProjectKind.nota);
      await WorkItemsRepository(db).ensureDefaultColumns(project);
    });
    await _pumpRequirementsBoard(tester, db, project);
    await tester.tap(find.text('Nuevo requerimiento'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(0), 'Autenticación');
    await tester.enterText(find.byType(TextField).at(1), 'Acceso con correo');
    await tester.enterText(
      find.byType(TextField).at(2),
      'Rechaza contraseña incorrecta',
    );
    await tester.tap(find.text('Guardar cambios'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
    expect(find.textContaining('Autenticación'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy requirements without a column appear on the board', (
    tester,
  ) async {
    final db = _memoryDb();
    late int project;
    await tester.runAsync(() async {
      project = await ProjectsRepository(
        db,
      ).create(title: 'Demo', kind: ProjectKind.nota);
      await db
          .into(db.workItems)
          .insert(
            WorkItemsCompanion.insert(
              projectId: project,
              title: 'Login legado',
              kind: const Value('requirement'),
            ),
          );
      await WorkItemsRepository(db).ensureDefaultColumns(project);
    });
    await _pumpRequirementsBoard(tester, db, project);
    expect(find.text('Login legado'), findsOneWidget);
    expect(find.text('0/0 tareas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'bounded sketch dialog inserts a diagram block and returns its document',
    (tester) async {
      CanvasData? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  saved = await editNoteSketch(context, const CanvasData());
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Añadir bloque'));
      await tester.pumpAndSettle();
      final surface = find.byKey(const ValueKey('note-sketch-surface'));
      final rect = tester.getRect(surface);
      await tester.tapAt(rect.topLeft + const Offset(50, 50));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar boceto'));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!.items, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'constant widgets recolor across dark and light without remounting',
    (tester) async {
      await pumpKraft(tester);
      final context = tester.element(find.byType(Scaffold).first);
      final container = ProviderScope.containerOf(context);
      final theme = container.read(themeProvider);
      await tester.runAsync(() => theme.set(ThemeMode.dark));
      await settle(tester);
      expect(KraftColors.isDark, true);
      final dark = tester
          .widgetList<Text>(find.byType(Text))
          .firstWhere((w) => w.data == 'Hola, Alex')
          .style!
          .color;
      await tester.runAsync(() => theme.set(ThemeMode.light));
      await settle(tester);
      final light = tester
          .widgetList<Text>(find.byType(Text))
          .firstWhere((w) => w.data == 'Hola, Alex')
          .style!
          .color;
      expect(light, isNot(dark));
      expect(KraftColors.isDark, false);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('selected filter uses dark text on dark-theme accent', (
    tester,
  ) async {
    KraftColors.use(Brightness.dark);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: FilterPill(label: 'ACTIVE', selected: true)),
      ),
    );
    expect(
      tester.widget<Text>(find.text('ACTIVE')).style!.color,
      KraftColors.onPrimaryContainer,
    );
    KraftColors.use(Brightness.light);
  });
}
