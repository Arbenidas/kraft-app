import 'package:flutter/material.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../data/db/database.dart';
import '../../data/providers.dart';
import '../../theme/kraft_colors.dart';
import '../../theme/kraft_motion.dart';
import '../../theme/kraft_tokens.dart';
import '../../theme/kraft_typography.dart';
import '../../widgets/neo_box.dart';
import '../../widgets/tech_badge.dart';
import '../ai/ai_providers.dart';
import '../forms/entity_sheets.dart';
import '../planning/kraft_deadline_picker.dart';
import '../voice/assistant_markdown.dart';

const workStatuses = {
  'todo': 'Por hacer',
  'doing': 'En curso',
  'done': 'Terminado',
};

IconData _statusIcon(String status) => switch (status) {
  'doing' => Symbols.timelapse,
  'done' => Symbols.check_circle,
  _ => Symbols.radio_button_unchecked,
};

Color _statusColor(String status) => switch (status) {
  'doing' => KraftColors.tertiaryContainer,
  'done' => KraftColors.secondaryContainer,
  _ => KraftColors.primaryContainer,
};

/// El tablero agrupa por columna. Los requerimientos antiguos sin columnId
/// se muestran en la columna que corresponde a su status, no se ocultan.
List<WorkItem> itemsInRequirementColumn(
  List<WorkItem> items,
  RequirementColumn column,
  List<RequirementColumn> columns,
) {
  int fallbackId(WorkItem item) => columns
      .firstWhere(
        (candidate) => candidate.category == item.status,
        orElse: () => columns.first,
      )
      .id;

  return [
    for (final item in items)
      if (item.columnId == column.id ||
          (item.columnId == null && fallbackId(item) == column.id))
        item,
  ];
}

class WorkItemsPanel extends ConsumerWidget {
  const WorkItemsPanel({
    super.key,
    required this.projectId,
    this.requirements = false,
    this.focusItemId,
  });
  final int projectId;
  final bool requirements;
  final int? focusItemId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(projectWorkItemsProvider(projectId));
    final columns = requirements
        ? ref.watch(requirementColumnsProvider(projectId))
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WorkToolbar(projectId: projectId, requirements: requirements),
        const SizedBox(height: KraftSpace.lg),
        data.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(
            'No se pudo cargar: $e',
            style: KraftText.bodyMd.copyWith(color: KraftColors.error),
          ),
          data: (all) {
            final items = all
                .where(
                  (w) => w.kind == (requirements ? 'requirement' : 'activity'),
                )
                .toList();
            if (!requirements) {
              if (items.isEmpty) return const _EmptyWork(requirements: false);
              return _ActivityList(projectId: projectId, items: items);
            }
            return columns!.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('No se pudo cargar el tablero: $e'),
              data: (states) => _RequirementsBoard(
                projectId: projectId,
                items: items,
                columns: states,
                focusItemId: focusItemId,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _WorkToolbar extends ConsumerWidget {
  const _WorkToolbar({required this.projectId, required this.requirements});

  final int projectId;
  final bool requirements;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Wrap(
    spacing: KraftSpace.sm,
    runSpacing: KraftSpace.sm,
    children: [
      FilledButton.icon(
        onPressed: () => showWorkItemEditor(
          context,
          ref,
          projectId: projectId,
          kind: requirements ? 'requirement' : 'activity',
        ),
        icon: const Icon(Symbols.add, size: 18),
        label: Text(requirements ? 'Nuevo requerimiento' : 'Nueva actividad'),
      ),
      OutlinedButton.icon(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) =>
              _PlanningChat(projectId: projectId, requirements: requirements),
        ),
        icon: const Icon(Symbols.auto_awesome, size: 18),
        label: Text(
          requirements ? 'Pensar requerimientos con IA' : 'Planificar con IA',
        ),
      ),
    ],
  );
}

class _EmptyWork extends StatelessWidget {
  const _EmptyWork({required this.requirements});

  final bool requirements;

  @override
  Widget build(BuildContext context) => NeoBox(
    color: KraftColors.surfaceContainerLow,
    borderColor: KraftColors.outlineVariant,
    borderWidth: 1,
    shadow: 0,
    radius: KraftRadius.lg,
    padding: const EdgeInsets.all(KraftSpace.xl),
    child: Row(
      children: [
        Icon(
          requirements ? Symbols.rule : Symbols.view_kanban,
          color: KraftColors.primary,
          size: 28,
        ),
        const SizedBox(width: KraftSpace.md),
        Expanded(
          child: Text(
            requirements
                ? 'Todavía no hay requerimientos. Añade uno o pídele a la IA que estructure el alcance.'
                : 'Todavía no hay actividades. Añade una o pídele a la IA que proponga el siguiente paso.',
            style: KraftText.bodyMd.copyWith(color: KraftColors.onSurface),
          ),
        ),
      ],
    ),
  );
}

class _ActivityList extends StatelessWidget {
  const _ActivityList({required this.projectId, required this.items});

  final int projectId;
  final List<WorkItem> items;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final (index, item) in items.indexed) ...[
        if (index > 0) const SizedBox(height: KraftSpace.sm),
        _ActivityRow(projectId: projectId, item: item),
      ],
    ],
  );
}

class _ActivityRow extends ConsumerWidget {
  const _ActivityRow({required this.projectId, required this.item});

  final int projectId;
  final WorkItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completed = item.status == 'done';
    return NeoBox(
      onTap: () => showWorkItemEditor(
        context,
        ref,
        projectId: projectId,
        item: item,
        kind: item.kind,
      ),
      color: completed
          ? KraftColors.surfaceContainerLowest.withValues(alpha: 0.6)
          : KraftColors.surfaceContainerLowest,
      borderColor: completed
          ? KraftColors.secondaryContainer.withValues(alpha: 0.4)
          : KraftColors.outlineVariant,
      borderWidth: 1,
      shadow: 0,
      radius: KraftRadius.md,
      padding: const EdgeInsets.symmetric(
        horizontal: KraftSpace.md,
        vertical: KraftSpace.sm + 4,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: completed ? 'Marcar como pendiente' : 'Marcar como terminado',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: Icon(
              completed ? Symbols.check_circle : _statusIcon(item.status),
              color: completed
                  ? KraftColors.secondaryContainer
                  : _statusColor(item.status),
              size: 22,
            ),
            onPressed: () => ref
                .read(workItemsRepositoryProvider)
                .update(item.copyWith(status: completed ? 'todo' : 'done')),
          ),
          const SizedBox(width: KraftSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KraftText.bodyMd.copyWith(
                    color: completed
                        ? KraftColors.onSurfaceVariant
                        : KraftColors.onSurface,
                    fontWeight: FontWeight.w700,
                    decoration: completed ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (item.description.isNotEmpty)
                  Text(
                    item.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KraftText.bodySm.copyWith(
                      color: KraftColors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (item.dueAt != null || item.dueDay != null) ...[
            const SizedBox(width: KraftSpace.sm),
            Text(
              item.dueDay ?? '${item.dueAt!.day}/${item.dueAt!.month}',
              style: KraftText.labelCode.copyWith(
                color: KraftColors.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(width: KraftSpace.xs),
          _WorkItemMenu(projectId: projectId, item: item),
        ],
      ),
    );
  }
}

class _RequirementsBoard extends ConsumerWidget {
  const _RequirementsBoard({
    required this.projectId,
    required this.items,
    required this.columns,
    this.focusItemId,
  });
  final int projectId;
  final List<WorkItem> items;
  final List<RequirementColumn> columns;
  final int? focusItemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requirements = items
        .where((item) => item.kind == 'requirement')
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _createColumn(context, ref),
            icon: const Icon(Symbols.add),
            label: const Text('Añadir columna'),
          ),
        ),
        if (requirements.isEmpty)
          const _EmptyWork(requirements: true)
        else
          SizedBox(
            height: 560,
            child: _OpenFocusedRequirement(
              projectId: projectId,
              items: requirements,
              columns: columns,
              focusItemId: focusItemId,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: columns.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: KraftSpace.md),
                itemBuilder: (_, index) => _RequirementColumnView(
                  projectId: projectId,
                  column: columns[index],
                  columns: columns,
                  items: itemsInRequirementColumn(
                    requirements,
                    columns[index],
                    columns,
                  ),
                  focusItemId: focusItemId,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _createColumn(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Nueva columna'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Ej. En revisión'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, controller.text),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    if (title?.trim().isNotEmpty ?? false)
      await ref
          .read(workItemsRepositoryProvider)
          .createColumn(projectId: projectId, title: title!.trim());
    controller.dispose();
  }
}

class _OpenFocusedRequirement extends ConsumerStatefulWidget {
  const _OpenFocusedRequirement({
    required this.projectId,
    required this.items,
    required this.columns,
    required this.child,
    this.focusItemId,
  });

  final int projectId;
  final List<WorkItem> items;
  final List<RequirementColumn> columns;
  final Widget child;
  final int? focusItemId;

  @override
  ConsumerState<_OpenFocusedRequirement> createState() =>
      _OpenFocusedRequirementState();
}

class _OpenFocusedRequirementState
    extends ConsumerState<_OpenFocusedRequirement> {
  int? _opened;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  @override
  void didUpdateWidget(covariant _OpenFocusedRequirement oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusItemId != widget.focusItemId) {
      _opened = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _open());
    }
  }

  void _open() {
    final id = widget.focusItemId;
    if (!mounted || id == null || _opened == id) return;
    final item = widget.items
        .where((candidate) => candidate.id == id)
        .firstOrNull;
    if (item == null) return;
    _opened = id;
    showRequirementDetail(
      context,
      ref,
      projectId: widget.projectId,
      item: item,
      columns: widget.columns,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _RequirementColumnView extends ConsumerWidget {
  const _RequirementColumnView({
    required this.projectId,
    required this.column,
    required this.columns,
    required this.items,
    this.focusItemId,
  });
  final int projectId;
  final RequirementColumn column;
  final List<RequirementColumn> columns;
  final List<WorkItem> items;
  final int? focusItemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SizedBox(
    width: 300,
    child: ColoredBox(
      color: KraftColors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(KraftSpace.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  color: Color(
                    int.parse(column.color.replaceFirst('#', 'FF'), radix: 16),
                  ),
                ),
                const SizedBox(width: KraftSpace.sm),
                Expanded(
                  child: Text(
                    column.title,
                    style: KraftText.bodyMd.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text('${items.length}', style: KraftText.techBadge),
                PopupMenuButton<String>(
                  tooltip: 'Opciones de columna',
                  onSelected: (action) async {
                    if (action == 'delete' && columns.length > 1) {
                      final destination = columns.firstWhere(
                        (candidate) => candidate.id != column.id,
                      );
                      await ref
                          .read(workItemsRepositoryProvider)
                          .deleteColumn(
                            column.id,
                            moveToColumnId: destination.id,
                          );
                    }
                  },
                  itemBuilder: (_) => [
                    if (columns.length > 1)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Eliminar y mover tarjetas'),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: KraftSpace.sm),
            Expanded(
              child: DragTarget<WorkItem>(
                onAcceptWithDetails: (details) => ref
                    .read(workItemsRepositoryProvider)
                    .moveRequirement(details.data, column.id),
                builder: (_, candidate, __) => Container(
                  color: candidate.isEmpty
                      ? Colors.transparent
                      : KraftColors.primaryContainer.withValues(alpha: .35),
                  child: ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: KraftSpace.sm),
                    itemBuilder: (_, index) => LongPressDraggable<WorkItem>(
                      data: items[index],
                      feedback: Material(
                        child: SizedBox(
                          width: 280,
                          child: _RequirementBoardCard(
                            projectId: projectId,
                            item: items[index],
                            columns: columns,
                            focused: items[index].id == focusItemId,
                          ),
                        ),
                      ),
                      childWhenDragging: const SizedBox(height: 90),
                      child: _RequirementBoardCard(
                        projectId: projectId,
                        item: items[index],
                        columns: columns,
                        focused: items[index].id == focusItemId,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => showWorkItemEditor(
                context,
                ref,
                projectId: projectId,
                kind: 'requirement',
                initialColumnId: column.id,
              ),
              icon: const Icon(Symbols.add, size: 17),
              label: const Text('Añadir requerimiento'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RequirementBoardCard extends ConsumerWidget {
  const _RequirementBoardCard({
    required this.projectId,
    required this.item,
    required this.columns,
    this.focused = false,
  });
  final int projectId;
  final WorkItem item;
  final List<RequirementColumn> columns;
  final bool focused;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks =
        ref.watch(requirementTasksProvider(item.id)).valueOrNull ?? const [];
    return NeoBox(
      onTap: () => showRequirementDetail(
        context,
        ref,
        projectId: projectId,
        item: item,
        columns: columns,
      ),
      color: KraftColors.surfaceContainerLowest,
      borderColor: focused ? KraftColors.primary : KraftColors.outlineVariant,
      borderWidth: focused ? 2 : 1,
      shadow: focused ? 1 : 0,
      radius: KraftRadius.md,
      padding: const EdgeInsets.all(KraftSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'REQ-${item.id}',
                style: KraftText.techBadge.copyWith(color: KraftColors.primary),
              ),
              const Spacer(),
              PopupMenuButton<int>(
                tooltip: 'Mover a columna',
                icon: const Icon(Symbols.more_horiz, size: 20),
                onSelected: (id) => ref
                    .read(workItemsRepositoryProvider)
                    .moveRequirement(item, id),
                itemBuilder: (_) => [
                  for (final state in columns)
                    PopupMenuItem(
                      value: state.id,
                      child: Text('Mover a ${state.title}'),
                    ),
                ],
              ),
            ],
          ),
          Text(
            item.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: KraftText.bodyMd.copyWith(fontWeight: FontWeight.w700),
          ),
          if (item.labels.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 4,
                children: [
                  for (final label in item.labels.take(3)) TechBadge(label),
                ],
              ),
            ),
          const SizedBox(height: KraftSpace.sm),
          Row(
            children: [
              Icon(
                tasks.isNotEmpty && tasks.every((t) => t.done)
                    ? Symbols.check_circle
                    : Symbols.checklist,
                size: 14,
                color: tasks.isNotEmpty && tasks.every((t) => t.done)
                    ? KraftColors.secondaryContainer
                    : KraftColors.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                '${tasks.where((task) => task.done).length}/${tasks.length} tareas',
                style: KraftText.labelCode.copyWith(
                  fontSize: 11,
                  color: KraftColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (tasks.isNotEmpty) ...[
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: tasks.where((task) => task.done).length / tasks.length,
                minHeight: 4,
                backgroundColor: KraftColors.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(
                  tasks.every((task) => task.done)
                      ? KraftColors.secondaryContainer
                      : KraftColors.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> showRequirementDetail(
  BuildContext context,
  WidgetRef ref, {
  required int projectId,
  required WorkItem item,
  required List<RequirementColumn> columns,
}) => showDialog<void>(
  context: context,
  builder: (_) =>
      _RequirementDetail(projectId: projectId, item: item, columns: columns),
);

class _RequirementDetail extends ConsumerWidget {
  const _RequirementDetail({
    required this.projectId,
    required this.item,
    required this.columns,
  });
  final int projectId;
  final WorkItem item;
  final List<RequirementColumn> columns;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allItems = ref.watch(projectWorkItemsProvider(projectId)).valueOrNull;
    final currentItem =
        allItems?.firstWhere((w) => w.id == item.id, orElse: () => item) ??
        item;
    final tasks =
        ref.watch(requirementTasksProvider(currentItem.id)).valueOrNull ?? const [];
    final history =
        ref.watch(requirementHistoryProvider(currentItem.id)).valueOrNull ?? const [];
    final completed = tasks.where((task) => task.done).length;
    final progress = tasks.isEmpty ? 0.0 : completed / tasks.length;
    return Dialog(
      backgroundColor: KraftColors.surfaceContainerLow,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(KraftSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(KraftSpace.md),
                decoration: BoxDecoration(
                  color: KraftColors.primaryContainer,
                  borderRadius: BorderRadius.circular(KraftRadius.lg),
                  border: KraftBorder.ink(),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'REQUERIMIENTO · REQ-${currentItem.id}',
                            style: KraftText.techBadge.copyWith(
                              color: KraftColors.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            currentItem.title,
                            style: KraftText.headlineSm.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Symbols.close),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: KraftSpace.md),
              Expanded(
                child: ListView(
                  children: [
                    if (currentItem.description.isNotEmpty)
                      _DetailSection(
                        title: 'Descripción',
                        child: AssistantMarkdown(text: currentItem.description),
                      ),
                    if (currentItem.acceptance.isNotEmpty)
                      _DetailSection(
                        title: 'Criterios de aceptación',
                        child: AssistantMarkdown(text: currentItem.acceptance),
                      ),
                    _DetailSection(
                      title: 'Avance',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LinearProgressIndicator(
                            value: progress,
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          const SizedBox(height: KraftSpace.xs),
                          Text(
                            '$completed de ${tasks.length} tareas completadas',
                            style: KraftText.bodySm.copyWith(
                              color: KraftColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _DetailSection(
                      title: 'Estado',
                      child: Wrap(
                        spacing: KraftSpace.xs,
                        children: [
                          for (final column in columns)
                            ChoiceChip(
                              label: Text(column.title),
                              selected: currentItem.columnId == column.id,
                              onSelected: (_) => ref
                                  .read(workItemsRepositoryProvider)
                                  .moveRequirement(currentItem, column.id),
                            ),
                        ],
                      ),
                    ),
                    _DetailSection(
                      title:
                          'Tareas · ${tasks.where((task) => task.done).length}/${tasks.length}',
                      child: Column(
                        children: [
                          for (final task in tasks)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Checkbox(
                                value: task.done,
                                onChanged: (done) => ref
                                    .read(tasksRepositoryProvider)
                                    .setDone(task, done ?? false),
                              ),
                              title: Text(task.title),
                              subtitle: task.label == null
                                  ? null
                                  : Text(task.label!),
                              onTap: () =>
                                  showTaskSheet(context, ref, task: task),
                            ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => showTaskSheet(
                                context,
                                ref,
                                projectId: projectId,
                                requirementId: item.id,
                              ),
                              icon: const Icon(Symbols.add),
                              label: const Text('Añadir tarea'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _DetailSection(
                      title: 'Seguimiento',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final entry in history.take(8))
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: KraftSpace.sm,
                              ),
                              child: Text(
                                '${entry.message} · ${entry.createdAt.day}/${entry.createdAt.month}',
                                style: KraftText.bodySm,
                              ),
                            ),
                          TextButton.icon(
                            onPressed: () => _addComment(context, ref),
                            icon: const Icon(Symbols.add_comment),
                            label: const Text('Añadir comentario'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => showWorkItemEditor(
                    context,
                    ref,
                    projectId: projectId,
                    kind: 'requirement',
                    item: item,
                  ),
                  icon: const Icon(Symbols.edit),
                  label: const Text('Editar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addComment(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final message = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Añadir seguimiento'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, controller.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (message?.trim().isNotEmpty ?? false)
      await ref
          .read(workItemsRepositoryProvider)
          .addHistory(item.id, 'comment', message!.trim());
    controller.dispose();
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: KraftSpace.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: KraftText.labelCode.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: KraftSpace.sm),
        child,
      ],
    ),
  );
}

class _WorkItemMenu extends ConsumerWidget {
  const _WorkItemMenu({required this.projectId, required this.item});

  final int projectId;
  final WorkItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
    tooltip: 'Acciones',
    icon: const Icon(Symbols.more_horiz, size: 20),
    onSelected: (action) {
      if (action == 'child') {
        showWorkItemEditor(
          context,
          ref,
          projectId: projectId,
          kind: item.kind,
          parentId: item.id,
        );
      } else {
        ref
            .read(workItemsRepositoryProvider)
            .update(item.copyWith(status: action));
      }
    },
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'child', child: Text('Desglosar')),
      const PopupMenuDivider(),
      for (final entry in workStatuses.entries)
        PopupMenuItem(value: entry.key, child: Text('Mover a ${entry.value}')),
    ],
  );
}

Future<void> showWorkItemEditor(
  BuildContext context,
  WidgetRef ref, {
  required int projectId,
  String kind = 'activity',
  WorkItem? item,
  int? parentId,
  DateTime? initialDate,
  int? initialColumnId,
}) => showDialog<void>(
  context: context,
  builder: (_) => _WorkEditor(
    projectId: projectId,
    kind: kind,
    item: item,
    parentId: parentId,
    initialDate: initialDate,
    initialColumnId: initialColumnId,
  ),
);

class _WorkEditor extends ConsumerStatefulWidget {
  const _WorkEditor({
    required this.projectId,
    required this.kind,
    this.item,
    this.parentId,
    this.initialDate,
    this.initialColumnId,
  });
  final int projectId;
  final String kind;
  final WorkItem? item;
  final int? parentId;
  final DateTime? initialDate;
  final int? initialColumnId;
  @override
  ConsumerState<_WorkEditor> createState() => _WorkEditorState();
}

class _WorkEditorState extends ConsumerState<_WorkEditor> {
  late final title = TextEditingController(text: widget.item?.title);
  late final description = TextEditingController(
    text: widget.item?.description,
  );
  late final acceptance = TextEditingController(text: widget.item?.acceptance);
  late KraftDeadline? deadline = widget.item?.dueDay != null
      ? KraftDeadline(day: DateTime.parse(widget.item!.dueDay!))
      : widget.item?.dueAt != null
      ? KraftDeadline(
          day: widget.item!.dueAt!,
          time: TimeOfDay.fromDateTime(widget.item!.dueAt!),
        )
      : widget.initialDate == null
      ? null
      : KraftDeadline(day: widget.initialDate!);
  late String status = widget.item?.status ?? 'todo';
  String? error;
  bool saving = false;
  @override
  void dispose() {
    title.dispose();
    description.dispose();
    acceptance.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (title.text.trim().isEmpty) {
      setState(() => error = 'Escribe un título.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final repo = ref.read(workItemsRepositoryProvider);
      if (widget.item case final item?) {
        await repo.update(
          item.copyWith(
            title: title.text.trim(),
            description: description.text,
            acceptance: acceptance.text,
            dueAt: Value(deadline?.dateTime),
            dueDay: Value(deadline?.time == null ? deadline?.dayKey : null),
            status: status,
          ),
        );
      } else {
        await repo.create(
          projectId: widget.projectId,
          title: title.text,
          description: description.text,
          acceptance: acceptance.text,
          kind: widget.kind,
          status: status,
          parentId: widget.parentId,
          dueAt: deadline?.dateTime,
          dueDay: deadline?.time == null ? deadline?.dayKey : null,
          columnId: widget.initialColumnId,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRequirement = widget.kind == 'requirement';
    final editing = widget.item != null;
    final screen = MediaQuery.sizeOf(context);
    final dialogWidth = screen.width < 600 ? screen.width - 32 : 720.0;
    final inputDecoration = (String label, {String? hint}) => InputDecoration(
      labelText: label,
      hintText: hint,
      alignLabelWithHint: true,
      filled: true,
      fillColor: KraftColors.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: KraftSpace.md,
        vertical: 14,
      ),
      labelStyle: KraftText.labelCode.copyWith(
        color: KraftColors.onSurfaceVariant,
      ),
      floatingLabelStyle: KraftText.labelCode.copyWith(
        color: KraftColors.primary,
        fontWeight: FontWeight.w700,
      ),
      hintStyle: KraftText.bodySm.copyWith(color: KraftColors.onSurfaceVariant),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KraftRadius.md),
        borderSide: BorderSide(color: KraftColors.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KraftRadius.md),
        borderSide: BorderSide(color: KraftColors.primary, width: 2),
      ),
      counterStyle: KraftText.labelCode.copyWith(
        color: KraftColors.onSurfaceVariant,
      ),
    );

    Future<void> pickDate() async {
      final picked = await showKraftDeadlinePicker(context, initial: deadline);
      if (picked != null && mounted) setState(() => deadline = picked);
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(KraftSpace.md),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: screen.height * 0.86,
        ),
        child: Material(
          color: KraftColors.surfaceContainerLow,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KraftRadius.xl),
            side: BorderSide(color: KraftColors.border, width: 1.5),
          ),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(
                  KraftSpace.lg,
                  KraftSpace.md,
                  KraftSpace.md,
                  KraftSpace.md,
                ),
                color: isRequirement
                    ? KraftColors.tertiaryContainer
                    : KraftColors.primaryContainer,
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: KraftColors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(KraftRadius.md),
                        border: Border.all(color: KraftColors.border),
                      ),
                      child: Icon(
                        isRequirement ? Symbols.rule : Symbols.calendar_month,
                        color: KraftColors.onSurface,
                      ),
                    ),
                    const SizedBox(width: KraftSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            editing ? 'Editar' : 'Nuevo',
                            style: KraftText.techBadge.copyWith(
                              color: KraftColors.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            isRequirement ? 'Requerimiento' : 'Actividad',
                            style: KraftText.headlineSm.copyWith(
                              color: KraftColors.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: saving ? null : () => Navigator.pop(context),
                      icon: const Icon(Symbols.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(KraftSpace.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: title,
                        maxLength: 200,
                        textCapitalization: TextCapitalization.sentences,
                        style: KraftText.bodyMd.copyWith(
                          color: KraftColors.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: inputDecoration(
                          'Título',
                          hint: isRequirement
                              ? 'Qué debe resolver el producto'
                              : 'Qué se necesita hacer',
                        ),
                      ),
                      const SizedBox(height: KraftSpace.sm),
                      TextField(
                        controller: description,
                        minLines: 3,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        style: KraftText.bodyMd.copyWith(
                          color: KraftColors.onSurface,
                        ),
                        decoration: inputDecoration(
                          'Descripción',
                          hint: isRequirement
                              ? 'Contexto, alcance y comportamiento esperado'
                              : 'Resultado esperado o contexto de la actividad',
                        ),
                      ),
                      if (isRequirement) ...[
                        const SizedBox(height: KraftSpace.md),
                        Container(
                          padding: const EdgeInsets.all(KraftSpace.sm),
                          decoration: BoxDecoration(
                            color: KraftColors.surfaceContainer,
                            borderRadius: BorderRadius.circular(KraftRadius.md),
                            border: Border.all(
                              color: KraftColors.outlineVariant,
                            ),
                          ),
                          child: TextField(
                            controller: acceptance,
                            minLines: 3,
                            maxLines: 5,
                            textCapitalization: TextCapitalization.sentences,
                            style: KraftText.bodyMd.copyWith(
                              color: KraftColors.onSurface,
                            ),
                            decoration: inputDecoration(
                              'Criterios de aceptación',
                              hint:
                                  'Cómo sabremos que el requerimiento está terminado',
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: KraftSpace.lg),
                      Text(
                        'Seguimiento',
                        style: KraftText.labelCode.copyWith(
                          color: KraftColors.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: KraftSpace.sm),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final stacked = constraints.maxWidth < 500;
                          final statusPicker = _WorkStatusPicker(
                            value: status,
                            onChanged: (value) =>
                                setState(() => status = value),
                          );
                          final datePicker = KraftDeadlineButton(
                            value: deadline,
                            onPick: pickDate,
                            onClear: deadline == null
                                ? null
                                : () => setState(() => deadline = null),
                          );
                          if (stacked) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                statusPicker,
                                const SizedBox(height: KraftSpace.md),
                                datePicker,
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 3, child: statusPicker),
                              const SizedBox(width: KraftSpace.md),
                              Expanded(flex: 2, child: datePicker),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(KraftSpace.md),
                decoration: BoxDecoration(
                  color: KraftColors.surfaceContainerHigh,
                  border: Border(
                    top: BorderSide(color: KraftColors.outlineVariant),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (error != null) ...[
                      Text(
                        error!,
                        style: KraftText.bodySm.copyWith(
                          color: KraftColors.error,
                        ),
                      ),
                      const SizedBox(height: KraftSpace.sm),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: saving
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: KraftSpace.sm),
                        FilledButton.icon(
                          onPressed: saving ? null : save,
                          icon: Icon(
                            saving ? Symbols.progress_activity : Symbols.save,
                          ),
                          label: Text(
                            saving ? 'Guardando…' : 'Guardar cambios',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkStatusPicker extends StatelessWidget {
  const _WorkStatusPicker({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Estado', style: KraftText.labelCode),
      const SizedBox(height: KraftSpace.xs),
      Wrap(
        spacing: KraftSpace.xs,
        runSpacing: KraftSpace.xs,
        children: [
          for (final entry in workStatuses.entries)
            ChoiceChip(
              label: Text(entry.value),
              selected: value == entry.key,
              onSelected: (_) => onChanged(entry.key),
              selectedColor: _statusColor(entry.key),
              backgroundColor: KraftColors.surfaceContainerLowest,
              labelStyle: KraftText.labelCode.copyWith(
                color: value == entry.key
                    ? KraftColors.onColor(_statusColor(entry.key))
                    : KraftColors.onSurface,
                fontWeight: FontWeight.w700,
              ),
              side: BorderSide(
                color: value == entry.key
                    ? KraftColors.border
                    : KraftColors.outlineVariant,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(KraftRadius.sm),
              ),
            ),
        ],
      ),
    ],
  );
}

class _PlanningChat extends ConsumerStatefulWidget {
  const _PlanningChat({required this.projectId, required this.requirements});
  final int projectId;
  final bool requirements;
  @override
  ConsumerState<_PlanningChat> createState() => _PlanningChatState();
}

class _PlanningChatState extends ConsumerState<_PlanningChat> {
  final input = TextEditingController();
  final List<({bool isUser, String text, DateTime time})> _sessionTurns = [];
  int _lastKnownTurnsCount = 0;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final voice = ref.read(voiceControllerProvider);
    _lastKnownTurnsCount = voice.turns.length;
  }

  @override
  void dispose() {
    input.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send(String message) {
    if (message.trim().isEmpty) return;
    final voice = ref.read(voiceControllerProvider);
    if (voice.thinking) return;

    setState(() {
      _sessionTurns.add((
        isUser: true,
        text: message.trim(),
        time: DateTime.now(),
      ));
    });
    input.clear();

    _scrollToBottom();

    voice.ask(
      message.trim(),
      instruction:
          'Modo ${widget.requirements ? 'requerimientos' : 'planificación de actividades'} del proyecto ${widget.projectId}. '
          'Consulta list_project_work antes de escribir para evitar duplicados. Usa save_project_work para guardar cada '
          '${widget.requirements ? 'requirement con descripción y criterios de aceptación' : 'activity con descripción y fecha si se conoce'}. '
          'Para mover un requerimiento a En curso o Terminado llama save_project_work con su id y status doing o done. '
          'Las casillas de un requerimiento se crean con save_task (requirement_id) y se marcan hechas con save_task id + done=true; '
          'no las escribas en acceptance. Usa parent_id para desglosar. Pregunta por ambigüedades; no inventes decisiones. '
          'Explica brevemente lo realmente guardado.',
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: KraftMotion.base,
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final voice = ref.watch(voiceControllerProvider);

    // Capturar solo los nuevos turnos generados durante esta sesión
    if (voice.turns.length > _lastKnownTurnsCount) {
      for (var i = _lastKnownTurnsCount; i < voice.turns.length; i++) {
        final t = voice.turns[i];
        if (!t.user) {
          _sessionTurns.add((
            isUser: false,
            text: t.text,
            time: DateTime.now(),
          ));
        }
      }
      _lastKnownTurnsCount = voice.turns.length;
      _scrollToBottom();
    }

    final suggestions = widget.requirements
        ? [
            'Estructurar alcance completo del sistema',
            'Definir criterios de aceptación (estilo Gherkin)',
            'Desglosar en módulos técnicos prioritarios',
            'Identificar requerimientos no funcionales',
          ]
        : [
            'Planificar actividades del sprint',
            'Estimar entregables y fechas límite',
            'Desglosar siguientes pasos de desarrollo',
            'Organizar pruebas y validaciones',
          ];

    return Dialog(
      backgroundColor: KraftColors.surfaceContainerLow,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KraftRadius.xl),
        side: BorderSide(color: KraftColors.outlineVariant),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 620),
        child: Column(
          children: [
            // Cabecera moderna
            Container(
              padding: const EdgeInsets.all(KraftSpace.md),
              decoration: BoxDecoration(
                color: KraftColors.surfaceContainerLowest,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(KraftRadius.xl),
                ),
                border: Border(
                  bottom: BorderSide(color: KraftColors.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          KraftColors.primaryContainer,
                          KraftColors.tertiaryContainer,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(KraftRadius.md),
                    ),
                    child: Icon(
                      Symbols.auto_awesome,
                      color: KraftColors.onPrimaryContainer,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: KraftSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.requirements
                              ? 'Pensar requerimientos con IA'
                              : 'Planificar actividades con IA',
                          style: KraftText.headlineSm.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Proyecto #${widget.projectId} · Asistente contextual',
                          style: KraftText.labelCode.copyWith(
                            color: KraftColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    icon: const Icon(Symbols.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Contenido central: bienvenida / sugerencias o historial de la sesión
            Expanded(
              child: _sessionTurns.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(KraftSpace.lg),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: KraftColors.surfaceContainerHigh,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              widget.requirements
                                  ? Symbols.rule
                                  : Symbols.calendar_month,
                              size: 32,
                              color: KraftColors.primary,
                            ),
                          ),
                          const SizedBox(height: KraftSpace.md),
                          Text(
                            widget.requirements
                                ? 'Estructura los requerimientos con IA'
                                : 'Planifica las actividades de tu proyecto',
                            textAlign: TextAlign.center,
                            style: KraftText.headlineSm.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: KraftSpace.xs),
                          Text(
                            'Elige una sugerencia o describe qué necesitas que el asistente organice.',
                            textAlign: TextAlign.center,
                            style: KraftText.bodySm.copyWith(
                              color: KraftColors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: KraftSpace.lg),
                          Wrap(
                            spacing: KraftSpace.sm,
                            runSpacing: KraftSpace.sm,
                            alignment: WrapAlignment.center,
                            children: [
                              for (final s in suggestions)
                                ActionChip(
                                  avatar: const Icon(
                                    Symbols.auto_awesome,
                                    size: 14,
                                  ),
                                  label: Text(s),
                                  backgroundColor:
                                      KraftColors.surfaceContainerLowest,
                                  side: BorderSide(
                                    color: KraftColors.outlineVariant,
                                  ),
                                  labelStyle: KraftText.bodySm.copyWith(
                                    fontSize: 12,
                                  ),
                                  onPressed: () => _send(s),
                                ),
                            ],
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(KraftSpace.md),
                      itemCount: _sessionTurns.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: KraftSpace.md),
                      itemBuilder: (context, index) {
                        final turn = _sessionTurns[index];
                        if (turn.isUser) {
                          return Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 480),
                              padding: const EdgeInsets.symmetric(
                                horizontal: KraftSpace.md,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: KraftColors.primaryContainer,
                                borderRadius:
                                    BorderRadius.circular(KraftRadius.lg),
                              ),
                              child: Text(
                                turn.text,
                                style: KraftText.bodyMd.copyWith(
                                  color: KraftColors.onPrimaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          );
                        }
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 540),
                            padding: const EdgeInsets.all(KraftSpace.md),
                            decoration: BoxDecoration(
                              color: KraftColors.surfaceContainerLowest,
                              borderRadius:
                                  BorderRadius.circular(KraftRadius.lg),
                              border: Border.all(
                                color: KraftColors.outlineVariant,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Symbols.auto_awesome,
                                      size: 14,
                                      color: KraftColors.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'ASISTENTE KRAFT',
                                      style: KraftText.techBadge.copyWith(
                                        fontSize: 9,
                                        color: KraftColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                AssistantMarkdown(text: turn.text),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Estado de pensamiento animado
            if (voice.thinking)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: KraftSpace.md,
                  vertical: 8,
                ),
                color: KraftColors.surfaceContainerHighest.withValues(alpha: 0.3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(KraftColors.primary),
                      ),
                    ),
                    const SizedBox(width: KraftSpace.sm),
                    Text(
                      widget.requirements
                          ? 'Estructurando requerimientos y criterios…'
                          : 'Planificando actividades y cronograma…',
                      style: KraftText.labelCode.copyWith(
                        fontSize: 11,
                        color: KraftColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

            // Mensaje de error si ocurre
            if (voice.error != null)
              Container(
                padding: const EdgeInsets.all(KraftSpace.sm),
                color: KraftColors.errorContainer.withValues(alpha: 0.2),
                child: Text(
                  voice.error!,
                  style: KraftText.bodySm.copyWith(color: KraftColors.error),
                ),
              ),

            // Barra de entrada inferior
            Container(
              padding: const EdgeInsets.all(KraftSpace.sm + 4),
              decoration: BoxDecoration(
                color: KraftColors.surfaceContainerLowest,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(KraftRadius.xl),
                ),
                border: Border(
                  top: BorderSide(color: KraftColors.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: input,
                      minLines: 1,
                      maxLines: 4,
                      onSubmitted: voice.thinking ? null : _send,
                      decoration: InputDecoration(
                        hintText: widget.requirements
                            ? 'Ej. Desglosa los módulos de la app y define sus criterios…'
                            : 'Ej. Planifica las actividades para la entrega del viernes…',
                        hintStyle: KraftText.bodySm.copyWith(
                          color: KraftColors.outline,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: KraftSpace.sm,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: KraftSpace.xs),
                  IconButton.filled(
                    tooltip: 'Enviar a la IA',
                    icon: Icon(
                      voice.thinking
                          ? Symbols.hourglass_empty
                          : Symbols.send,
                      size: 18,
                    ),
                    onPressed: voice.thinking ? null : () => _send(input.text),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
