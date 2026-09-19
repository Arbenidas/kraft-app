import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/db/database.dart';
import '../../data/providers.dart';
import '../../theme/kraft_colors.dart';
import '../../theme/kraft_motion.dart';
import '../../theme/kraft_tokens.dart';
import '../../theme/kraft_typography.dart';
import '../../utils/dates.dart';
import '../../widgets/entrance.dart';
import '../../widgets/neo_checkbox.dart';
import '../forms/entity_sheets.dart';
import '../reminders/reminder_field.dart';

class QuickTaskList extends ConsumerWidget {
  const QuickTaskList({super.key, this.tasks});

  /// Lista ya filtrada (la de un proyecto). Sin ella se pintan todas las pendientes.
  final List<QuickTask>? tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Theme.of(context); // Rebuild when the active palette changes.
    final tasks = this.tasks ?? ref.watch(tasksProvider).valueOrNull;
    if (tasks == null) return const SizedBox(height: 120);
    if (tasks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: KraftSpace.lg),
        child: Text(
          'Nada pendiente. Añade una nota rápida.',
          textAlign: TextAlign.center,
          style: KraftText.labelCode.copyWith(
            color: KraftColors.onSurfaceVariant,
          ),
        ),
      );
    }
    return AnimatedSize(
      duration: KraftMotion.of(context, KraftMotion.base),
      curve: KraftMotion.settle,
      alignment: Alignment.topCenter,
      child: Column(
        children: [
          for (final (i, task) in tasks.indexed)
            Padding(
              key: ValueKey(task.id),
              padding: EdgeInsets.only(top: i == 0 ? 0 : KraftSpace.xs + 2),
              child: Entrance(
                index: i,
                child: _QuickTaskTile(task: task),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickTaskTile extends ConsumerStatefulWidget {
  const _QuickTaskTile({required this.task});

  final QuickTask task;

  @override
  ConsumerState<_QuickTaskTile> createState() => _QuickTaskTileState();
}

class _QuickTaskTileState extends ConsumerState<_QuickTaskTile> {
  /// Estado visual inmediato; se guarda tras la animación para que la reordenación no la corte.
  bool? _pendingDone;
  Timer? _commit;

  bool get _done => _pendingDone ?? widget.task.done;

  @override
  void didUpdateWidget(_QuickTaskTile old) {
    super.didUpdateWidget(old);
    if (widget.task.done == _pendingDone) _pendingDone = null;
  }

  @override
  void dispose() {
    _commit?.cancel();
    super.dispose();
  }

  void _toggle(bool value) {
    setState(() => _pendingDone = value);
    _commit?.cancel();
    _commit = Timer(
      KraftMotion.slow,
      () => ref.read(tasksRepositoryProvider).setDone(widget.task, value),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final task = widget.task;
    final meta = _done
        ? (task.completedAt != null
              ? 'Completado ${relativeTime(task.completedAt!).toLowerCase()}'
              : 'Completado')
        : [
            if (task.remindAt != null) '⏰ ${reminderLabel(task.remindAt!)}',
            if (task.highPriority) 'Prioridad alta',
            if (task.detail.isNotEmpty) task.detail,
          ].join(' • ');

    return Dismissible(
      key: ValueKey('dismiss-${task.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => deleteTaskWithUndo(context, ref, task),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: KraftSpace.lg),
        decoration: BoxDecoration(
          color: KraftColors.error,
          borderRadius: BorderRadius.circular(KraftRadius.md),
        ),
        child: const Icon(Symbols.delete, color: Colors.white),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        decoration: BoxDecoration(
          color: KraftColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(KraftRadius.md),
          boxShadow: KraftShadow.hard(2),
        ),
        child: Row(
          children: [
            NeoCheckbox(
              checked: _done,
              onChanged: _toggle,
              size: 26,
              fill: KraftColors.secondaryContainer,
              checkColor: KraftColors.onSecondaryContainer,
              bordered: false,
              semanticLabel: task.title,
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => showTaskSheet(context, ref, task: task),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: KraftMotion.of(context, KraftMotion.fast),
                        style: KraftText.bodyMd.copyWith(
                          color: _done
                              ? KraftColors.onSurfaceVariant
                              : KraftColors.onSurface,
                          decoration: _done
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                          fontWeight: task.highPriority && !_done
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                        // Lo dictado suele ser una frase entera: en una línea no cabía.
                        child: Text(
                          task.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Row(
                        children: [
                          if (meta.isNotEmpty)
                            Flexible(
                              child: Text(
                                meta,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: KraftText.labelCode.copyWith(
                                  color: _done
                                      ? KraftColors.secondary
                                      : KraftColors.onSurfaceVariant,
                                  fontWeight: _done
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          if (task.label != null && !_done) ...[
                            if (meta.isNotEmpty)
                              Text(
                                ' • ',
                                style: KraftText.labelCode.copyWith(
                                  color: KraftColors.onSurfaceVariant,
                                ),
                              ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              decoration: BoxDecoration(
                                color: KraftColors.primaryContainer,
                                borderRadius: BorderRadius.circular(
                                  KraftRadius.sm,
                                ),
                              ),
                              child: Text(
                                task.label!,
                                style: KraftText.labelCode.copyWith(
                                  color: KraftColors.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Más opciones',
              icon: Icon(
                Symbols.more_vert,
                size: 18,
                color: KraftColors.onSurfaceVariant,
              ),
              color: KraftColors.surfaceContainerLowest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(KraftRadius.lg),
                side: BorderSide(color: KraftColors.ink, width: 2),
              ),
              onSelected: (value) => switch (value) {
                'edit' => showTaskSheet(context, ref, task: task),
                'project' => showProjectPicker(
                  context,
                  ref,
                  current: task.projectId,
                  onPick: (id) =>
                      ref.read(tasksRepositoryProvider).setProject(task.id, id),
                ),
                _ => deleteTaskWithUndo(context, ref, task),
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Editar')),
                PopupMenuItem(
                  value: 'project',
                  child: Text('Mover a proyecto'),
                ),
                PopupMenuItem(value: 'delete', child: Text('Borrar')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
