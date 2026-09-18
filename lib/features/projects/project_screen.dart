import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app/router.dart';
import '../../data/db/database.dart';
import '../../data/providers.dart';
import '../../theme/kraft_colors.dart';
import '../../theme/kraft_tokens.dart';
import '../../theme/kraft_typography.dart';
import '../../widgets/entrance.dart';
import '../../widgets/kraft_top_bar.dart';
import '../../widgets/neo_box.dart';
import '../forms/entity_sheets.dart';
import '../home/quick_tasks.dart';
import '../home/project_card.dart';

enum _Tab { overview, notes, canvases, tasks }

final _tabProvider = StateProvider.autoDispose.family<_Tab, int>(
  (ref, id) => _Tab.overview,
);

/// El contenido de un proyecto: sus notas, lienzos y tareas, y botones para crear dentro.
class ProjectScreen extends ConsumerWidget {
  const ProjectScreen({super.key, required this.projectId});

  final int projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Theme.of(context); // Rebuild when the active palette changes.
    final projectData = ref.watch(projectProvider(projectId));
    final project = projectData.valueOrNull;
    final tab = ref.watch(_tabProvider(projectId));
    final notes =
        ref.watch(projectNotesProvider(projectId)).valueOrNull ?? const [];
    final canvases =
        ref.watch(projectCanvasesProvider(projectId)).valueOrNull ?? const [];
    final tasks =
        ref.watch(projectTasksProvider(projectId)).valueOrNull ?? const [];

    final work =
        ref.watch(projectWorkItemsProvider(projectId)).valueOrNull ??
        const <WorkItem>[];
    final activities = work.where((w) => w.kind == 'activity').toList();
    final requirements = work.where((w) => w.kind == 'requirement').toList();

    if (project == null && projectData.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (projectData.hasError) {
      return Center(
        child: Text('No se pudo cargar el proyecto: ${projectData.error}'),
      );
    }
    if (project == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(Routes.home);
      });
      return const SizedBox.shrink();
    }

    return ColoredBox(
      color: KraftColors.surface,
      child: Column(
        children: [
          KraftTopBar(
            leading: Row(
              children: [
                TopBarIconButton(
                  icon: Symbols.arrow_back,
                  tooltip: 'Volver',
                  onTap: () => context.canPop()
                      ? context.pop()
                      : context.go(Routes.projects),
                ),
                const SizedBox(width: KraftSpace.sm + 4),
                Flexible(
                  child: KraftBrand(breadcrumb: project.title, showLogo: false),
                ),
              ],
            ),
            actions: [
              TopBarIconButton(
                icon: Symbols.edit,
                tooltip: 'Editar proyecto',
                onTap: () async {
                  final result = await showProjectSheet(
                    context,
                    ref,
                    project: project,
                  );
                  if (result == ProjectSheetResult.deleted && context.mounted) {
                    context.go(Routes.home);
                  }
                },
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(KraftSpace.xl),
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 120,
                      height: 72,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(KraftRadius.md),
                        child: ProjectCover(project: project),
                      ),
                    ),
                    const SizedBox(width: KraftSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            project.title,
                            style: KraftText.headlineLg.copyWith(fontSize: 28),
                          ),
                          if (project.description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              project.description,
                              style: KraftText.bodyMd.copyWith(
                                color: KraftColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: KraftSpace.lg),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    final columns = constraints.maxWidth < 540
                        ? 1
                        : (wide ? 6 : 2);
                    final unit =
                        (constraints.maxWidth - 16 * (columns - 1)) / columns;
                    Widget tile(
                      _Tab value,
                      String title,
                      IconData icon,
                      int count,
                      String summary,
                      List<String> previews, {
                      bool featured = false,
                      VoidCallback? onTap,
                    }) {
                      final span = wide ? (featured ? 3 : 2) : 1;
                      return SizedBox(
                        width: unit * span + 16 * (span - 1),
                        child: _ProjectTile(
                          title: title,
                          icon: icon,
                          count: count,
                          summary: summary,
                          previews: previews,
                          selected: tab == value,
                          onTap:
                              onTap ??
                              () =>
                                  ref
                                          .read(
                                            _tabProvider(projectId).notifier,
                                          )
                                          .state =
                                      value,
                        ),
                      );
                    }

                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        tile(
                          _Tab.overview,
                          'Actividades',
                          Symbols.calendar_month,
                          activities.length,
                          '${activities.where((w) => w.status == 'done').length} completadas · Planifica el siguiente paso',
                          activities.take(2).map((w) => w.title).toList(),
                          featured: true,
                          onTap: () =>
                              context.go(Routes.projectActivities(projectId)),
                        ),
                        tile(
                          _Tab.overview,
                          'Requerimientos',
                          Symbols.rule,
                          requirements.length,
                          'Alcance, criterios y desglose del proyecto',
                          requirements.take(2).map((w) => w.title).toList(),
                          featured: true,
                          onTap: () =>
                              context.go(Routes.projectRequirements(projectId)),
                        ),
                        tile(
                          _Tab.notes,
                          'Notas',
                          Symbols.description,
                          notes.length,
                          'Ideas y documentación',
                          notes
                              .take(2)
                              .map(
                                (n) => n.title.isEmpty ? 'Sin título' : n.title,
                              )
                              .toList(),
                        ),
                        tile(
                          _Tab.canvases,
                          'Lienzos',
                          Symbols.draw,
                          canvases.length,
                          'Diagramas y arquitecturas',
                          canvases.take(2).map((c) => c.title).toList(),
                        ),
                        tile(
                          _Tab.tasks,
                          'Tareas',
                          Symbols.check_circle,
                          tasks.length,
                          '${tasks.where((t) => !t.done).length} pendientes',
                          tasks.take(2).map((t) => t.title).toList(),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: KraftSpace.lg),
                switch (tab) {
                  _Tab.overview => const SizedBox.shrink(),
                  _Tab.notes => _NoteList(projectId: projectId, notes: notes),
                  _Tab.canvases => _CanvasList(
                    projectId: projectId,
                    canvases: canvases,
                  ),
                  _Tab.tasks => _TaskList(projectId: projectId, tasks: tasks),
                },
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({
    required this.title,
    required this.icon,
    required this.count,
    required this.summary,
    required this.previews,
    required this.selected,
    required this.onTap,
  });
  final String title, summary;
  final IconData icon;
  final int count;
  final List<String> previews;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: NeoBox(
      onTap: onTap,
      radius: 16,
      shadow: selected ? 3 : 0,
      color: selected
          ? KraftColors.surfaceContainerHigh
          : KraftColors.surfaceContainerLow,
      borderColor: selected ? KraftColors.primary : KraftColors.outlineVariant,
      borderWidth: selected ? 2 : 1,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 22, color: KraftColors.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: KraftText.headlineSm)),
              Text(
                '$count',
                style: KraftText.headlineLg.copyWith(fontSize: 28),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: KraftText.bodySm.copyWith(
              color: KraftColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          for (final text in previews)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: KraftText.bodySm,
              ),
            ),
          if (previews.isEmpty)
            Text(
              'Todo empieza con una idea.',
              style: KraftText.bodySm.copyWith(
                color: KraftColors.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                selected ? 'SECCIÓN ABIERTA' : 'EXPLORAR',
                style: KraftText.labelCode.copyWith(
                  fontSize: 11,
                  color: KraftColors.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Icon(
                selected ? Symbols.expand_more : Symbols.arrow_forward,
                size: 18,
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: KraftSpace.xl),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: KraftText.bodyMd.copyWith(color: KraftColors.onSurfaceVariant),
    ),
  );
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: NeoBox(
      onTap: onTap,
      color: KraftColors.primaryContainer,
      borderWidth: 1.5,
      shadow: 2,
      radius: KraftRadius.lg,
      padding: const EdgeInsets.symmetric(
        horizontal: KraftSpace.md,
        vertical: 10,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Symbols.add, size: 20),
          const SizedBox(width: 4),
          Text(
            label,
            style: KraftText.labelCode.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

class _NoteList extends ConsumerWidget {
  const _NoteList({required this.projectId, required this.notes});
  final int projectId;
  final List<Note> notes;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _AddButton(
        label: 'NUEVA NOTA AQUÍ',
        onTap: () async {
          final id = await ref
              .read(notesRepositoryProvider)
              .create(projectId: projectId);
          if (context.mounted) context.go('${Routes.notes}/$id');
        },
      ),
      const SizedBox(height: KraftSpace.md),
      if (notes.isEmpty)
        const _Empty('Todavía no hay notas en este proyecto.')
      else
        for (final (i, note) in notes.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: KraftSpace.sm),
            child: Entrance(
              index: i,
              child: NeoBox(
                onTap: () => context.go('${Routes.notes}/${note.id}'),
                color: KraftColors.surfaceContainerLowest,
                borderWidth: 1.5,
                radius: KraftRadius.md,
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Symbols.description, size: 20),
                    const SizedBox(width: KraftSpace.sm),
                    Expanded(
                      child: Text(
                        note.title.isEmpty ? 'Nota sin título' : note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KraftText.bodyMd.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TopBarIconButton(
                      icon: Symbols.link_off,
                      tooltip: 'Sacar del proyecto',
                      onTap: () => ref
                          .read(notesRepositoryProvider)
                          .setProject(note.id, null),
                    ),
                  ],
                ),
              ),
            ),
          ),
    ],
  );
}

class _CanvasList extends ConsumerWidget {
  const _CanvasList({required this.projectId, required this.canvases});
  final int projectId;
  final List<CanvasRecord> canvases;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _AddButton(
        label: 'NUEVO LIENZO AQUÍ',
        onTap: () async {
          final id = await ref
              .read(canvasesRepositoryProvider)
              .create(projectId: projectId);
          if (context.mounted) context.go('${Routes.canvas}/$id');
        },
      ),
      const SizedBox(height: KraftSpace.md),
      if (canvases.isEmpty)
        const _Empty('Todavía no hay lienzos en este proyecto.')
      else
        for (final (i, canvas) in canvases.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: KraftSpace.sm),
            child: Entrance(
              index: i,
              child: NeoBox(
                onTap: () => context.go('${Routes.canvas}/${canvas.id}'),
                color: KraftColors.surfaceContainerLowest,
                borderWidth: 1.5,
                radius: KraftRadius.md,
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Symbols.draw, size: 20),
                    const SizedBox(width: KraftSpace.sm),
                    Expanded(
                      child: Text(
                        canvas.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KraftText.bodyMd.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TopBarIconButton(
                      icon: Symbols.link_off,
                      tooltip: 'Sacar del proyecto',
                      onTap: () => ref
                          .read(canvasesRepositoryProvider)
                          .setProject(canvas.id, null),
                    ),
                  ],
                ),
              ),
            ),
          ),
    ],
  );
}

class _TaskList extends ConsumerWidget {
  const _TaskList({required this.projectId, required this.tasks});
  final int projectId;
  final List<QuickTask> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requirements =
        (ref.watch(projectWorkItemsProvider(projectId)).valueOrNull ??
                const <WorkItem>[])
            .where((item) => item.kind == 'requirement')
            .toList();
    final loose = tasks.where((task) => task.requirementId == null).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AddButton(
          label: 'NUEVA TAREA AQUÍ',
          onTap: () => showTaskSheet(context, ref, projectId: projectId),
        ),
        const SizedBox(height: KraftSpace.md),
        if (requirements.isEmpty && tasks.isEmpty)
          const _Empty('Todavía no hay tareas en este proyecto.')
        else ...[
          for (final requirement in requirements) ...[
            _TaskGroup(
              projectId: projectId,
              requirement: requirement,
              tasks: tasks
                  .where((task) => task.requirementId == requirement.id)
                  .toList(),
            ),
            const SizedBox(height: KraftSpace.md),
          ],
          if (loose.isNotEmpty) ...[
            Text('TAREAS SIN AGRUPAR', style: KraftText.labelCode),
            const SizedBox(height: KraftSpace.xs),
            QuickTaskList(tasks: loose),
          ],
        ],
      ],
    );
  }
}

class _TaskGroup extends ConsumerWidget {
  const _TaskGroup({
    required this.projectId,
    required this.requirement,
    required this.tasks,
  });
  final int projectId;
  final WorkItem requirement;
  final List<QuickTask> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) => NeoBox(
    color: KraftColors.surfaceContainerLow,
    borderColor: KraftColors.outlineVariant,
    borderWidth: 1,
    shadow: 1,
    radius: KraftRadius.lg,
    padding: const EdgeInsets.all(KraftSpace.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () =>
              context.go(Routes.projectRequirement(projectId, requirement.id)),
          child: Row(
            children: [
              const Icon(Symbols.account_tree, size: 20),
              const SizedBox(width: KraftSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      requirement.title,
                      style: KraftText.bodyLg.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${tasks.where((task) => task.done).length}/${tasks.length} subtareas',
                      style: KraftText.labelCode.copyWith(
                        color: KraftColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Symbols.open_in_new, size: 18),
            ],
          ),
        ),
        const SizedBox(height: KraftSpace.sm),
        if (tasks.isEmpty)
          Text(
            'Sin subtareas todavía.',
            style: KraftText.bodySm.copyWith(
              color: KraftColors.onSurfaceVariant,
            ),
          )
        else
          QuickTaskList(tasks: tasks),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => showTaskSheet(
              context,
              ref,
              projectId: projectId,
              requirementId: requirement.id,
            ),
            icon: const Icon(Symbols.add, size: 18),
            label: const Text('Añadir subtarea'),
          ),
        ),
      ],
    ),
  );
}
