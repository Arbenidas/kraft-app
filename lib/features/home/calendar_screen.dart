import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app/router.dart';
import '../../data/db/database.dart';
import '../../data/providers.dart';
import '../../theme/kraft_colors.dart';
import '../../theme/kraft_motion.dart';
import '../../theme/kraft_tokens.dart';
import '../../theme/kraft_typography.dart';
import '../../widgets/kraft_top_bar.dart';
import '../../widgets/neo_box.dart';
import '../projects/work_items_panel.dart';
import 'calendar_card.dart';

enum _WorkFilter { all, pending, done }

final _calendarWorkFilterProvider = StateProvider.autoDispose<_WorkFilter>(
  (ref) => _WorkFilter.all,
);

/// Agenda de pantalla completa: fechas a la izquierda y trabajo del espacio a
/// la derecha. El contenido viene de las mismas tablas que el proyecto, así
/// que editar aquí no crea copias ni cambia el bento del proyecto.
class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ColoredBox(
    color: KraftColors.surface,
    child: Column(
      children: [
        KraftTopBar(
          leading: Row(
            children: [
              TopBarIconButton(
                icon: Symbols.arrow_back,
                tooltip: 'Volver al inicio',
                onTap: () => context.go(Routes.home),
              ),
              const SizedBox(width: KraftSpace.sm + 4),
              const Flexible(
                child: KraftBrand(breadcrumb: 'Calendario', showLogo: false),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = constraints.maxWidth >= 940;
              if (!twoColumns) {
                return ListView(
                  padding: const EdgeInsets.all(KraftSpace.lg),
                  children: const [
                    CalendarCard(),
                    SizedBox(height: KraftSpace.xl),
                    _CalendarWorkInbox(expanded: false),
                  ],
                );
              }
              return Padding(
                padding: const EdgeInsets.all(KraftSpace.xl),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: const [
                    Expanded(
                      flex: 7,
                      child: SingleChildScrollView(child: CalendarCard()),
                    ),
                    SizedBox(width: KraftSpace.lg),
                    Expanded(
                      flex: 5,
                      child: _CalendarWorkInbox(expanded: true),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _CalendarWorkInbox extends ConsumerWidget {
  const _CalendarWorkInbox({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(_calendarWorkFilterProvider);
    final selectedProject = ref.watch(calendarProjectFilterProvider);
    final projects = ref.watch(projectsProvider(null)).valueOrNull ?? const [];
    final items =
        ref.watch(allWorkItemsProvider).valueOrNull ?? const <WorkItem>[];

    final projectItems = [
      for (final item in items)
        if (selectedProject == null || item.projectId == selectedProject) item,
    ];

    final pending = projectItems.where((item) => item.status != 'done').length;
    final done = projectItems.where((item) => item.status == 'done').length;
    final total = projectItems.length;
    final progress = total > 0 ? done / total : 0.0;

    final visible =
        [
          for (final item in projectItems)
            if (switch (filter) {
              _WorkFilter.all => true,
              _WorkFilter.pending => item.status != 'done',
              _WorkFilter.done => item.status == 'done',
            })
              item,
        ]..sort((a, b) {
          if (filter == _WorkFilter.all) {
            final aDone = a.status == 'done' ? 1 : 0;
            final bDone = b.status == 'done' ? 1 : 0;
            if (aDone != bDone) return aDone.compareTo(bDone);
          }
          final aDate =
              a.dueAt ??
              (a.dueDay != null ? DateTime.tryParse(a.dueDay!) : null) ??
              DateTime(9999);
          final bDate =
              b.dueAt ??
              (b.dueDay != null ? DateTime.tryParse(b.dueDay!) : null) ??
              DateTime(9999);
          final comp = aDate.compareTo(bDate);
          if (comp != 0) return comp;
          return b.id.compareTo(a.id);
        });

    final projectNames = {
      for (final project in projects) project.id: project.title,
    };

    Widget list = visible.isEmpty
        ? _EmptyWorkList(filter: filter)
        : ListView.separated(
            shrinkWrap: !expanded,
            physics: expanded
                ? const AlwaysScrollableScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            itemCount: visible.length,
            separatorBuilder: (_, _) => const SizedBox(height: KraftSpace.sm),
            itemBuilder: (context, index) => _CalendarWorkRow(
              item: visible[index],
              projectName: projectNames[visible[index].projectId] ?? 'Proyecto',
            ),
          );

    return NeoBox(
      color: KraftColors.surfaceContainerLow,
      borderColor: KraftColors.outlineVariant,
      borderWidth: 1,
      shadow: 1,
      radius: KraftRadius.lg,
      padding: const EdgeInsets.all(KraftSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: KraftColors.primaryContainer.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(KraftRadius.sm),
                  border: Border.all(
                    color: KraftColors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Icon(
                  Symbols.assignment,
                  color: KraftColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: KraftSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Trabajo del espacio', style: KraftText.headlineSm),
                    const SizedBox(height: 2),
                    Text(
                      selectedProject == null
                          ? '$pending pendientes · $done terminadas'
                          : '$pending pendientes · proyecto filtrado',
                      style: KraftText.bodySm.copyWith(
                        color: KraftColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (projects.isNotEmpty)
                IconButton(
                  tooltip: 'Nueva actividad o requerimiento',
                  icon: const Icon(Symbols.add_circle, size: 22),
                  color: KraftColors.primary,
                  onPressed: () => showWorkItemEditor(
                    context,
                    ref,
                    projectId: selectedProject ?? projects.first.id,
                  ),
                ),
            ],
          ),
          const SizedBox(height: KraftSpace.sm),
          // Barra de progreso de avance
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: KraftColors.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(
                progress >= 1.0
                    ? KraftColors.secondaryContainer
                    : KraftColors.primary,
              ),
            ),
          ),
          const SizedBox(height: KraftSpace.md),
          Wrap(
            spacing: KraftSpace.xs,
            runSpacing: KraftSpace.xs,
            children: [
              _FilterChip(
                label: 'Todo ($total)',
                active: filter == _WorkFilter.all,
                onTap: () =>
                    ref.read(_calendarWorkFilterProvider.notifier).state =
                        _WorkFilter.all,
              ),
              _FilterChip(
                label: 'Pendientes ($pending)',
                active: filter == _WorkFilter.pending,
                onTap: () =>
                    ref.read(_calendarWorkFilterProvider.notifier).state =
                        _WorkFilter.pending,
              ),
              _FilterChip(
                label: 'Hechas ($done)',
                active: filter == _WorkFilter.done,
                onTap: () =>
                    ref.read(_calendarWorkFilterProvider.notifier).state =
                        _WorkFilter.done,
              ),
            ],
          ),
          const SizedBox(height: KraftSpace.md),
          if (expanded) Expanded(child: list) else list,
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(KraftRadius.sm),
    child: AnimatedContainer(
      duration: KraftMotion.fast,
      padding: const EdgeInsets.symmetric(
        horizontal: KraftSpace.sm + 2,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: active
            ? KraftColors.primaryContainer
            : KraftColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(KraftRadius.sm),
        border: Border.all(
          color: active ? KraftColors.primary : KraftColors.outlineVariant,
        ),
      ),
      child: Text(
        label,
        style: KraftText.labelCode.copyWith(
          color: active
              ? KraftColors.onPrimaryContainer
              : KraftColors.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _CalendarWorkRow extends ConsumerWidget {
  const _CalendarWorkRow({required this.item, required this.projectName});

  final WorkItem item;
  final String projectName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completed = item.status == 'done';
    final isRequirement = item.kind == 'requirement';
    final typeLabel = isRequirement ? 'REQUERIMIENTO' : 'ACTIVIDAD';
    final due =
        item.dueAt ??
        (item.dueDay != null ? DateTime.tryParse(item.dueDay!) : null);

    Future<void> toggleDone() async {
      final nextDone = !completed;
      final repo = ref.read(workItemsRepositoryProvider);
      if (item.kind == 'requirement') {
        final columns = await repo.ensureDefaultColumns(item.projectId);
        final targetCol = columns.firstWhere(
          (c) => c.category == (nextDone ? 'done' : 'todo'),
          orElse: () => columns.first,
        );
        await repo.moveRequirement(item, targetCol.id);
      } else {
        await repo.update(item.copyWith(status: nextDone ? 'done' : 'todo'));
      }
    }

    final card = NeoBox(
      onTap: () => showWorkItemEditor(
        context,
        ref,
        projectId: item.projectId,
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
      padding: const EdgeInsets.all(KraftSpace.sm + 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Checkbox interactivo de 1-toque
          IconButton(
            tooltip: completed
                ? 'Marcar como pendiente'
                : 'Marcar como terminado',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: Icon(
              completed ? Symbols.check_circle : Symbols.radio_button_unchecked,
              color: completed
                  ? KraftColors.secondaryContainer
                  : KraftColors.primary,
              size: 22,
            ),
            onPressed: toggleDone,
          ),
          const SizedBox(width: KraftSpace.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isRequirement
                            ? KraftColors.tertiaryContainer.withValues(
                                alpha: 0.2,
                              )
                            : KraftColors.primaryContainer.withValues(
                                alpha: 0.2,
                              ),
                        borderRadius: BorderRadius.circular(KraftRadius.sm),
                        border: Border.all(
                          color: isRequirement
                              ? KraftColors.tertiaryContainer.withValues(
                                  alpha: 0.5,
                                )
                              : KraftColors.primaryContainer.withValues(
                                  alpha: 0.5,
                                ),
                        ),
                      ),
                      child: Text(
                        typeLabel,
                        style: KraftText.techBadge.copyWith(
                          fontSize: 9,
                          color: isRequirement
                              ? KraftColors.tertiaryContainer
                              : KraftColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: KraftSpace.xs),
                    Expanded(
                      child: Text(
                        projectName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KraftText.techBadge.copyWith(
                          color: KraftColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: KraftText.bodyMd.copyWith(
                    color: completed
                        ? KraftColors.onSurfaceVariant
                        : KraftColors.onSurface,
                    fontWeight: FontWeight.w700,
                    decoration: completed ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: completed
                            ? KraftColors.secondaryContainer.withValues(
                                alpha: 0.15,
                              )
                            : KraftColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(KraftRadius.sm),
                      ),
                      child: Text(
                        workStatuses[item.status] ?? item.status,
                        style: KraftText.labelCode.copyWith(
                          fontSize: 10,
                          color: completed
                              ? KraftColors.secondaryContainer
                              : KraftColors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (due != null) ...[
                      const SizedBox(width: KraftSpace.xs),
                      Icon(
                        Symbols.calendar_today,
                        size: 11,
                        color: KraftColors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${due.day}/${due.month}/${due.year}',
                        style: KraftText.labelCode.copyWith(
                          fontSize: 10,
                          color: KraftColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
    // En escritorio el usuario espera arrastrar en cuanto mueve el ratón; el
    // gesto de pulsación larga hacía que los requerimientos parecieran no
    // arrastrables. Draggable conserva el tap para abrir el editor sin mover.
    return Draggable<WorkItem>(
      data: item,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: 280, child: Opacity(opacity: .9, child: card)),
      ),
      childWhenDragging: Opacity(opacity: .35, child: card),
      child: card,
    );
  }
}

class _EmptyWorkList extends StatelessWidget {
  const _EmptyWorkList({this.filter = _WorkFilter.all});

  final _WorkFilter filter;

  @override
  Widget build(BuildContext context) {
    final (icon, message) = switch (filter) {
      _WorkFilter.done => (
        Symbols.task_alt,
        'No hay actividades terminadas aún.\n¡Marca una tarea para verla aquí!',
      ),
      _WorkFilter.pending => (
        Symbols.sentiment_very_satisfied,
        '¡Todo al día!\nNo tienes actividades pendientes.',
      ),
      _WorkFilter.all => (
        Symbols.inbox,
        'No hay elementos en este proyecto o espacio.',
      ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: KraftSpace.xl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: KraftColors.outlineVariant),
            const SizedBox(height: KraftSpace.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: KraftText.bodySm.copyWith(
                color: KraftColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
