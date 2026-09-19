import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app/router.dart';
import '../../data/providers.dart';
import '../../data/db/database.dart';
import '../../theme/kraft_colors.dart';
import '../../theme/kraft_motion.dart';
import '../../theme/kraft_tokens.dart';
import '../../theme/kraft_typography.dart';
import '../../utils/dates.dart';
import '../../widgets/entrance.dart';
import '../../widgets/section_header.dart';
import '../../widgets/tech_badge.dart';
import '../forms/entity_sheets.dart';
import '../projects/work_items_panel.dart';
import '../../data/enums.dart';
import '../forms/entity_styles.dart';

Future<void> _scheduleWork(WidgetRef ref, WorkItem item, DateTime day) async {
  await ref.read(workItemsRepositoryProvider).scheduleAllDay(item, day);
  ref.read(selectedDayProvider.notifier).state = dateOnly(day);
}

/// Cronograma: vista Semana/Mes navegable, puntos por evento y lista de hitos del día.
class CalendarCard extends ConsumerWidget {
  const CalendarCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Theme.of(context); // Rebuild when the active palette changes.
    final selected = ref.watch(selectedDayProvider);
    final mode = ref.watch(calendarModeProvider);
    final projects = ref.watch(projectsProvider(null)).valueOrNull ?? const [];
    final selectedProject = ref.watch(calendarProjectFilterProvider);
    final events = ref.watch(visibleScheduleProvider);
    final dayEvents = events
        .where((e) => isSameDay(e.startsAt, selected))
        .toList();
    final now = DateTime.now();
    final pending = dayEvents.where((e) => e.startsAt.isAfter(now)).length;

    void shift(int direction) {
      final notifier = ref.read(selectedDayProvider.notifier);
      notifier.state = switch (mode) {
        CalendarMode.week => addDays(selected, 7 * direction),
        CalendarMode.month => DateTime(
          selected.year,
          selected.month + direction,
          1,
        ),
      };
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Cronograma // ${monthName(selected)} ${selected.year}',
          icon: Symbols.calendar_today,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Abrir calendario',
                onPressed: () => context.go(Routes.calendar),
                icon: const Icon(Symbols.open_in_full, size: 19),
              ),
              _ModeToggle(
                mode: mode,
                onChanged: (m) =>
                    ref.read(calendarModeProvider.notifier).state = m,
              ),
            ],
          ),
        ),
        const SizedBox(height: KraftSpace.sm + 4),
        Theme(
          data: Theme.of(
            context,
          ).copyWith(hoverColor: KraftColors.surfaceContainerHighest),
          child: Material(
            key: const ValueKey('calendar-project-filter'),
            color: KraftColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int?>(
                  focusColor: KraftColors.surfaceContainerHighest,
                  dropdownColor: KraftColors.surfaceContainerHigh,
                  value: projects.any((p) => p.id == selectedProject)
                      ? selectedProject
                      : null,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Todos los proyectos'),
                    ),
                    for (final p in projects)
                      DropdownMenuItem(value: p.id, child: Text(p.title)),
                  ],
                  onChanged: (id) =>
                      ref.read(calendarProjectFilterProvider.notifier).state =
                          id,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: KraftSpace.sm),
        Container(
          padding: const EdgeInsets.all(KraftSpace.md),
          decoration: BoxDecoration(
            color: KraftColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(KraftRadius.lg),
            border: KraftBorder.ink(),
            boxShadow: KraftShadow.hard(3),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: KraftColors.secondaryContainer,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: KraftSpace.sm),
                  Flexible(
                    child: Text(
                      longDay(selected).toUpperCase(),
                      overflow: TextOverflow.ellipsis,
                      style: KraftText.labelCode.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (isSameDay(selected, now)) ...[
                    const SizedBox(width: KraftSpace.sm),
                    TechBadge('HOY', background: KraftColors.surfaceContainer),
                  ] else ...[
                    const SizedBox(width: KraftSpace.sm),
                    GestureDetector(
                      onTap: () =>
                          ref.read(selectedDayProvider.notifier).state =
                              dateOnly(now),
                      child: TechBadge(
                        'IR A HOY',
                        background: KraftColors.primaryContainer,
                        foreground: KraftColors.onPrimaryContainer,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    pending == 1
                        ? '1 Hito pendiente'
                        : '$pending Hitos pendientes',
                    style: KraftText.labelCode.copyWith(
                      color: KraftColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: KraftSpace.sm),
                  _IconBtn(
                    icon: Symbols.chevron_left,
                    tooltip: 'Anterior',
                    onTap: () => shift(-1),
                  ),
                  _IconBtn(
                    icon: Symbols.chevron_right,
                    tooltip: 'Siguiente',
                    onTap: () => shift(1),
                  ),
                  _IconBtn(
                    icon: Symbols.add,
                    tooltip: 'Nuevo hito',
                    filled: true,
                    onTap: () {
                      final projectId = ref.read(calendarProjectFilterProvider);
                      if (projectId == null) {
                        showEventSheet(context, ref, day: selected);
                      } else {
                        showWorkItemEditor(
                          context,
                          ref,
                          projectId: projectId,
                          initialDate: selected,
                        );
                      }
                    },
                  ),
                ],
              ),
              Divider(
                height: KraftSpace.md,
                thickness: 1,
                color: KraftColors.surfaceContainerHighest,
              ),
              AnimatedSize(
                duration: KraftMotion.of(context, KraftMotion.base),
                curve: KraftMotion.settle,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: KraftMotion.of(context, KraftMotion.fast),
                  child: mode == CalendarMode.week
                      ? _WeekStrip(
                          key: ValueKey('w${startOfWeek(selected)}'),
                          selected: selected,
                          events: events,
                        )
                      : _MonthGrid(
                          key: ValueKey('m${selected.year}-${selected.month}'),
                          selected: selected,
                          events: events,
                        ),
                ),
              ),
              const SizedBox(height: KraftSpace.sm + 4),
              AnimatedSize(
                duration: KraftMotion.of(context, KraftMotion.base),
                curve: KraftMotion.settle,
                alignment: Alignment.topCenter,
                child: dayEvents.isEmpty
                    ? _EmptyDay(
                        onAdd: () =>
                            showEventSheet(context, ref, day: selected),
                      )
                    : Column(
                        key: ValueKey(selected),
                        children: [
                          for (final (i, event) in dayEvents.indexed) ...[
                            if (i > 0) const SizedBox(height: KraftSpace.sm),
                            Entrance(
                              key: ValueKey(event.key),
                              index: i,
                              child: _EventTile(
                                entry: event,
                                onTap: () => switch (event) {
                                  WorkEntry(:final item) => showWorkItemEditor(
                                    context,
                                    ref,
                                    projectId: item.projectId,
                                    item: item,
                                    kind: item.kind,
                                  ),
                                  EventEntry(:final event) => showEventSheet(
                                    context,
                                    ref,
                                    event: event,
                                  ),
                                  TaskEntry(:final task) => showTaskSheet(
                                    context,
                                    ref,
                                    task: task,
                                  ),
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

List<Color> _dotsFor(DateTime day, List<ScheduleEntry> events) => [
  for (final e in events)
    if (isSameDay(e.startsAt, day))
      switch (e) {
        WorkEntry() => KraftColors.primary,
        EventEntry(:final event) => event.tag.dot,
        TaskEntry(:final task) =>
          task.highPriority ? KraftColors.error : KraftColors.tertiary,
      },
].take(3).toList();

class _WeekStrip extends ConsumerWidget {
  const _WeekStrip({super.key, required this.selected, required this.events});

  final DateTime selected;
  final List<ScheduleEntry> events;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Theme.of(context); // Rebuild when the active palette changes.
    final start = startOfWeek(selected);
    return Row(
      children: [
        for (var i = 0; i < 7; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Entrance(
              index: i,
              offset: const Offset(0, 8),
              child: _DayCell(
                day: addDays(start, i),
                selected: isSameDay(addDays(start, i), selected),
                dots: _dotsFor(addDays(start, i), events),
                onTap: () => ref.read(selectedDayProvider.notifier).state =
                    addDays(start, i),
                onDrop: (item) => _scheduleWork(ref, item, addDays(start, i)),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MonthGrid extends ConsumerWidget {
  const _MonthGrid({super.key, required this.selected, required this.events});

  final DateTime selected;
  final List<ScheduleEntry> events;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Theme.of(context); // Rebuild when the active palette changes.
    final first = startOfWeek(startOfMonth(selected));
    final today = DateTime.now();
    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    weekdayShort(addDays(first, i)).toUpperCase(),
                    style: KraftText.techBadge.copyWith(
                      fontSize: 10,
                      color: KraftColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var week = 0; week < 6; week++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                for (var d = 0; d < 7; d++)
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final day = addDays(first, week * 7 + d);
                        final inMonth = day.month == selected.month;
                        final isSelected = isSameDay(day, selected);
                        final dots = _dotsFor(day, events);
                        return DragTarget<WorkItem>(
                          onWillAcceptWithDetails: (details) =>
                              details.data.status != 'done',
                          onAcceptWithDetails: (details) =>
                              _scheduleWork(ref, details.data, day),
                          builder: (context, candidates, _) => GestureDetector(
                            onTap: () =>
                                ref.read(selectedDayProvider.notifier).state =
                                    day,
                            child: AnimatedContainer(
                              duration: KraftMotion.of(
                                context,
                                KraftMotion.fast,
                              ),
                              height: 44,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? KraftColors.primaryContainer
                                    : inMonth
                                    ? KraftColors.surfaceContainerLow
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(
                                  KraftRadius.md,
                                ),
                                border: candidates.isNotEmpty
                                    ? KraftBorder.ink()
                                    : isSelected
                                    ? KraftBorder.ink()
                                    : isSameDay(day, today)
                                    ? Border.all(
                                        color: KraftColors.ink.withValues(
                                          alpha: 0.4,
                                        ),
                                      )
                                    : null,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '${day.day}',
                                    style: KraftText.labelCode.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: inMonth
                                          ? KraftColors.onSurface
                                          : KraftColors.outlineVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  _Dots(colors: dots, size: 5),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final CalendarMode mode;
  final ValueChanged<CalendarMode> onChanged;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    Widget segment(String label, CalendarMode value) {
      final active = mode == value;
      return GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: KraftMotion.of(context, KraftMotion.fast),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: active ? KraftColors.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(KraftRadius.sm),
            boxShadow: active ? KraftShadow.hard(1.5) : null,
          ),
          child: Text(
            label,
            style: KraftText.labelCode.copyWith(
              color: active
                  ? KraftColors.onPrimaryContainer
                  : KraftColors.onSurfaceVariant,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: KraftColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(KraftRadius.md),
        border: Border.all(color: KraftColors.ink.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          segment('Semana', CalendarMode.week),
          segment('Mes', CalendarMode.month),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          backgroundColor: filled
              ? KraftColors.primaryContainer
              : KraftColors.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KraftRadius.md),
            side: filled
                ? BorderSide(color: KraftColors.ink, width: 1.5)
                : BorderSide.none,
          ),
        ),
        icon: Icon(icon, size: 18, color: KraftColors.onSurface),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.colors, this.size = 6});

  final List<Color> colors;
  final double size;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return SizedBox(
      height: size,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final color in colors)
            Container(
              width: size,
              height: size,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.dots,
    required this.onTap,
    required this.onDrop,
  });

  final DateTime day;
  final bool selected;
  final List<Color> dots;
  final VoidCallback onTap;
  final ValueChanged<WorkItem> onDrop;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final today = isSameDay(day, DateTime.now());
    return Semantics(
      button: true,
      selected: selected,
      label: longDay(day),
      child: DragTarget<WorkItem>(
        onWillAcceptWithDetails: (details) => details.data.status != 'done',
        onAcceptWithDetails: (details) => onDrop(details.data),
        builder: (context, candidates, _) => GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: KraftMotion.of(context, KraftMotion.fast),
            curve: KraftMotion.settle,
            padding: const EdgeInsets.symmetric(vertical: KraftSpace.sm + 4),
            transform: Matrix4.translationValues(0, selected ? -2 : 0, 0),
            decoration: BoxDecoration(
              color: candidates.isNotEmpty
                  ? KraftColors.primaryContainer
                  : selected
                  ? KraftColors.primaryContainer
                  : KraftColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(KraftRadius.md),
              border: candidates.isNotEmpty || selected
                  ? KraftBorder.ink()
                  : Border.all(
                      color: today
                          ? KraftColors.ink.withValues(alpha: 0.4)
                          : Colors.transparent,
                      width: KraftBorder.width,
                    ),
              boxShadow: selected ? KraftShadow.hard(2) : null,
            ),
            child: ExcludeSemantics(
              child: Column(
                children: [
                  Text(
                    weekdayShort(day).toUpperCase(),
                    style: KraftText.techBadge.copyWith(
                      fontSize: 10,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                      color: selected
                          ? KraftColors.onPrimaryContainer
                          : KraftColors.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${day.day}',
                    style: KraftText.headlineSm.copyWith(
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? KraftColors.onPrimaryContainer
                          : KraftColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _Dots(colors: dots),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: KraftSpace.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Sin hitos para este día',
            style: KraftText.labelCode.copyWith(
              color: KraftColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: KraftSpace.sm),
          TextButton(onPressed: onAdd, child: const Text('Añadir')),
        ],
      ),
    );
  }
}

class _EventTile extends ConsumerWidget {
  const _EventTile({required this.entry, required this.onTap});

  final ScheduleEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Theme.of(context); // Rebuild when the active palette changes.
    // Una cita usa el estilo de su etiqueta; un recordatorio, el suyo propio según
    // prioridad y si ya está hecho.
    final (s, badge, done) = switch (entry) {
      WorkEntry(:final item) => (
        EventTag.lienzo.style,
        item.kind == 'requirement' ? 'REQUERIMIENTO' : 'ACTIVIDAD',
        item.status == 'done',
      ),
      EventEntry(:final event) => (event.tag.style, event.tag.label, false),
      TaskEntry(:final task) => (
        (
          accent: task.done
              ? KraftColors.secondary
              : task.highPriority
              ? KraftColors.error
              : KraftColors.tertiary,
          text: task.done
              ? KraftColors.secondary
              : task.highPriority
              ? KraftColors.error
              : KraftColors.tertiary,
          badge: task.done
              ? KraftColors.secondaryContainer
              : task.highPriority
              ? KraftColors.errorContainer
              : KraftColors.tertiaryContainer,
          onBadge: task.done
              ? KraftColors.onSecondaryContainer
              : task.highPriority
              ? KraftColors.onErrorContainer
              : KraftColors.onTertiaryContainer,
          icon: Symbols.alarm,
        ),
        task.done ? 'HECHO' : 'TAREA',
        task.done,
      ),
    };
    final past =
        done ||
        (entry.allDay
            ? dateOnly(entry.startsAt).isBefore(dateOnly(DateTime.now()))
            : entry.startsAt.isBefore(DateTime.now()));

    Future<void> toggleDone() async {
      switch (entry) {
        case WorkEntry(:final item):
          final nextDone = item.status != 'done';
          final repo = ref.read(workItemsRepositoryProvider);
          if (item.kind == 'requirement') {
            final columns = await repo.ensureDefaultColumns(item.projectId);
            final targetCol = columns.firstWhere(
              (c) => c.category == (nextDone ? 'done' : 'todo'),
              orElse: () => columns.first,
            );
            await repo.moveRequirement(item, targetCol.id);
          } else {
            await repo.update(
              item.copyWith(status: nextDone ? 'done' : 'todo'),
            );
          }
        case TaskEntry(:final task):
          await ref.read(tasksRepositoryProvider).setDone(task, !task.done);
        case EventEntry():
          break;
      }
    }

    final isToggleable = entry is WorkEntry || entry is TaskEntry;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: KraftMotion.fast,
        opacity: past ? 0.65 : 1,
        child: Container(
          decoration: BoxDecoration(
            color: KraftColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(KraftRadius.md),
            border: Border.all(
              color: done
                  ? KraftColors.secondaryContainer.withValues(alpha: 0.4)
                  : KraftColors.surfaceContainerHighest,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(
                  width: 4,
                  color: done ? KraftColors.secondaryContainer : s.accent,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        if (isToggleable)
                          InkWell(
                            onTap: toggleDone,
                            borderRadius: BorderRadius.circular(KraftRadius.sm),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: done
                                    ? KraftColors.secondaryContainer.withValues(
                                        alpha: 0.2,
                                      )
                                    : KraftColors.surfaceContainer,
                                borderRadius: BorderRadius.circular(
                                  KraftRadius.sm,
                                ),
                                border: Border.all(
                                  color: done
                                      ? KraftColors.secondaryContainer
                                      : KraftColors.outlineVariant,
                                  width: 1.2,
                                ),
                              ),
                              child: Icon(
                                done ? Symbols.check_circle : s.icon,
                                size: 18,
                                color: done
                                    ? KraftColors.secondaryContainer
                                    : s.text,
                              ),
                            ),
                          )
                        else
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: KraftColors.surfaceContainer,
                              borderRadius: BorderRadius.circular(
                                KraftRadius.sm,
                              ),
                            ),
                            child: Icon(s.icon, size: 18, color: s.text),
                          ),
                        const SizedBox(width: KraftSpace.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    entry.allDay
                                        ? 'TODO EL DÍA'
                                        : hhmm(entry.startsAt),
                                    style: KraftText.labelCode.copyWith(
                                      color: done
                                          ? KraftColors.secondaryContainer
                                          : s.text,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      entry.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: KraftText.bodyMd.copyWith(
                                        fontWeight: FontWeight.w700,
                                        decoration: done
                                            ? TextDecoration.lineThrough
                                            : null,
                                        color: done
                                            ? KraftColors.onSurfaceVariant
                                            : KraftColors.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (entry.detail.isNotEmpty)
                                Text(
                                  entry.detail,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: KraftText.bodySm,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: KraftSpace.sm),
                        TechBadge(
                          badge,
                          background: s.badge,
                          foreground: s.onBadge,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
