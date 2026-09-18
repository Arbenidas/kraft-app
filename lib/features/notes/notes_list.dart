import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app/router.dart';
import '../../data/db/database.dart';
import '../../data/enums.dart';
import '../../data/providers.dart';
import '../../theme/kraft_colors.dart';
import '../../theme/kraft_motion.dart';
import '../../theme/kraft_tokens.dart';
import '../../theme/kraft_typography.dart';
import '../../utils/dates.dart';
import '../../widgets/entrance.dart';
import '../../widgets/filter_pill.dart';
import '../../widgets/kraft_toast.dart';
import '../../widgets/tech_badge.dart';
import '../forms/entity_sheets.dart';
import '../forms/entity_styles.dart';
import 'note_document.dart';
import 'note_text.dart';

/// Notas guardadas en cuadrícula; tocar una abre su editor a pantalla completa.
class NotesList extends ConsumerWidget {
  const NotesList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Theme.of(context); // Rebuild when the active palette changes.
    final notes = ref.watch(notesProvider).valueOrNull;
    final allNotes = ref.watch(allNotesProvider).valueOrNull ?? const [];
    final total = ref.watch(noteCountProvider).valueOrNull ?? 0;
    final category = ref.watch(noteCategoryFilterProvider);

    final categoryCounts = <NoteCategory, int>{
      for (final c in NoteCategory.values) c: 0,
    };
    for (final n in allNotes) {
      categoryCounts[n.category] = (categoryCounts[n.category] ?? 0) + 1;
    }

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(KraftSpace.lg, KraftSpace.lg, KraftSpace.lg, 0),
          sliver: SliverList.list(
            children: [
              Row(
                children: [
                  Text(
                    'Notas',
                    style: KraftText.headlineSm.copyWith(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: KraftSpace.sm),
                  TechBadge(
                    '$total guardadas',
                    background: KraftColors.surfaceContainerHighest,
                    foreground: KraftColors.onSurface,
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: KraftColors.primaryContainer,
                      foregroundColor: KraftColors.onPrimaryContainer,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(KraftRadius.md),
                        side: BorderSide(color: KraftColors.border, width: 1.2),
                      ),
                    ),
                    onPressed: () => createNoteAndOpen(
                      context,
                      ref,
                      category: category ?? NoteCategory.idea,
                    ),
                    icon: const Icon(Symbols.add, size: 18),
                    label: Text(
                      'Nueva nota',
                      style: KraftText.labelCode.copyWith(
                        fontWeight: FontWeight.w700,
                        color: KraftColors.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: KraftSpace.md),
              const _SearchField(),
              const SizedBox(height: KraftSpace.md),
              Wrap(
                spacing: KraftSpace.sm,
                runSpacing: KraftSpace.sm,
                children: [
                  FilterPill(
                    label: 'TODAS (${allNotes.length})',
                    icon: Symbols.done_all,
                    selected: category == null,
                    onTap: () => ref.read(noteCategoryFilterProvider.notifier).state = null,
                  ),
                  for (final c in NoteCategory.values)
                    FilterPill(
                      label: '${c.label.toUpperCase()} (${categoryCounts[c] ?? 0})',
                      icon: c.icon,
                      selected: category == c,
                      onTap: () => ref.read(noteCategoryFilterProvider.notifier).state = c,
                    ),
                ],
              ),
              const SizedBox(height: KraftSpace.lg),
            ],
          ),
        ),
        if (notes == null)
          const SliverToBoxAdapter(child: SizedBox.shrink())
        else if (notes.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(KraftSpace.lg),
              child: Column(
                children: [
                  Text(
                    ref.read(noteQueryProvider).isEmpty && category == null
                        ? 'Aún no hay notas.'
                        : 'Sin resultados para la búsqueda actual.',
                    style: KraftText.labelCode.copyWith(color: KraftColors.onSurfaceVariant),
                  ),
                  const SizedBox(height: KraftSpace.md),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: KraftColors.primaryContainer,
                      foregroundColor: KraftColors.onPrimaryContainer,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(KraftRadius.md),
                        side: BorderSide(color: KraftColors.border),
                      ),
                    ),
                    onPressed: () => createNoteAndOpen(context, ref, category: category ?? NoteCategory.idea),
                    icon: const Icon(Symbols.edit_note, size: 18),
                    label: Text(
                      'Crear primera nota',
                      style: KraftText.labelCode.copyWith(
                        fontWeight: FontWeight.w700,
                        color: KraftColors.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(KraftSpace.lg, 0, KraftSpace.lg, KraftSpace.xl),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 380,
                mainAxisExtent: 172,
                crossAxisSpacing: KraftSpace.md,
                mainAxisSpacing: KraftSpace.md,
              ),
              itemCount: notes.length,
              itemBuilder: (context, i) => Entrance(
                key: ValueKey(notes[i].id),
                index: i,
                child: _NoteTile(note: notes[i]),
              ),
            ),
          ),
      ],
    );
  }
}

class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  late final _controller = TextEditingController(text: ref.read(noteQueryProvider));
  Timer? _debounce;
  bool _focused = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () => ref.read(noteQueryProvider.notifier).state = value);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      child: AnimatedContainer(
        duration: KraftMotion.fast,
        decoration: BoxDecoration(
          color: KraftColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(KraftRadius.md),
          border: Border.all(
            color: _focused ? KraftColors.primary : KraftColors.outlineVariant.withValues(alpha: 0.6),
            width: _focused ? 1.8 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: KraftColors.shadow.withValues(alpha: 0.2),
              offset: const Offset(0, 2),
              blurRadius: 4,
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: KraftSpace.md),
        child: Row(
          children: [
            Icon(
              Symbols.search,
              size: 20,
              color: _focused ? KraftColors.primary : KraftColors.onSurfaceVariant,
            ),
            const SizedBox(width: KraftSpace.sm),
            Expanded(
              child: TextField(
                controller: _controller,
                onChanged: _onChanged,
                style: KraftText.bodyMd,
                decoration: InputDecoration(
                  hintText: 'Buscar en notas por título o contenido...',
                  hintStyle: KraftText.bodyMd.copyWith(color: KraftColors.outline),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            if (_controller.text.isNotEmpty)
              IconButton(
                tooltip: 'Limpiar búsqueda',
                splashRadius: 18,
                onPressed: () {
                  _controller.clear();
                  _onChanged('');
                },
                icon: const Icon(Symbols.close, size: 18),
              ),
          ],
        ),
      ),
    );
  }
}

class _NoteTile extends ConsumerStatefulWidget {
  const _NoteTile({required this.note});

  final Note note;

  @override
  ConsumerState<_NoteTile> createState() => _NoteTileState();
}

class _NoteTileState extends ConsumerState<_NoteTile> {
  bool _hovered = false;

  static String cleanTitle(String raw) {
    var t = raw.trim();
    if (t.startsWith(checkboxOpen) || t.startsWith(checkboxDone) || t.startsWith('☑')) {
      t = stripCheckbox(t);
    }
    t = t.replaceFirst(RegExp(r'^#{1,6}\s*'), '');
    t = t.replaceAll('**', '').replaceAll('__', '').replaceAll('`', '');
    return t.trim();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final note = widget.note;
    final lines = (note.keyIdea.isNotEmpty ? note.keyIdea : note.body).split('\n');
    final source = (lines.isNotEmpty && lines.first.trim() == note.title.trim() ? lines.skip(1) : lines).join('\n');
    final preview = NoteTextController.readablePreview(source);

    // Checklist stats
    var openTasks = 0;
    var doneTasks = 0;
    final fullText = '${note.title}\n${note.keyIdea}\n${note.body}';
    for (final l in fullText.split('\n')) {
      final tr = l.trim();
      if (tr.startsWith(checkboxOpen) || tr.startsWith('- [ ]')) {
        openTasks++;
      } else if (tr.startsWith(checkboxDone) || tr.startsWith('☑') || tr.startsWith('- [x]')) {
        doneTasks++;
      }
    }
    final totalTasks = openTasks + doneTasks;
    final allTasksDone = totalTasks > 0 && openTasks == 0;

    // Sketch / Canvas indicators
    final hasSketch = note.category == NoteCategory.boceto ||
        note.content.contains('"sketches"') ||
        note.content.contains('"strokes"');
    final hasCanvasLink = note.content.contains('canvas:');

    final title = cleanTitle(note.title);

    return Dismissible(
      key: ValueKey('dismiss-note-${note.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => deleteNoteWithUndo(context, ref, note.id),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: KraftSpace.lg),
        decoration: BoxDecoration(
          color: KraftColors.error,
          borderRadius: BorderRadius.circular(KraftRadius.md),
        ),
        child: const Icon(Symbols.delete, color: Colors.white),
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: KraftMotion.fast,
          decoration: BoxDecoration(
            color: _hovered
                ? KraftColors.surfaceContainerLow
                : KraftColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(KraftRadius.md),
            border: Border.all(
              color: _hovered
                  ? note.category.color.withValues(alpha: 0.8)
                  : KraftColors.outlineVariant.withValues(alpha: 0.5),
              width: _hovered ? 1.5 : 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: KraftColors.shadow.withValues(alpha: _hovered ? 0.35 : 0.2),
                offset: Offset(0, _hovered ? 4 : 2),
                blurRadius: _hovered ? 8 : 4,
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(KraftRadius.md),
              onTap: () => context.push(Routes.noteEditor(note.id)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title and category indicator dot
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: note.category.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title.isEmpty ? 'Sin título' : title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: KraftText.headlineSm.copyWith(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              fontStyle: title.isEmpty ? FontStyle.italic : null,
                              color: title.isEmpty
                                  ? KraftColors.onSurfaceVariant
                                  : KraftColors.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Preview
                    Expanded(
                      child: Text(
                        preview.isNotEmpty
                            ? preview
                            : (title.isEmpty ? 'Nota vacía · toca para editar' : 'Sin contenido adicional'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: KraftText.bodySm.copyWith(
                          color: KraftColors.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Footer with category badge, metadata pills, and time
                    Row(
                      children: [
                        TechBadge(
                          note.category.label.toUpperCase(),
                          background: note.category.color.withValues(alpha: 0.25),
                          foreground: KraftColors.onSurface,
                          leadingDot: note.category.color,
                        ),
                        if (totalTasks > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: allTasksDone
                                  ? KraftColors.secondaryContainer.withValues(alpha: 0.3)
                                  : KraftColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(KraftRadius.sm),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  allTasksDone ? Symbols.check_circle : Symbols.check_box,
                                  size: 12,
                                  color: allTasksDone
                                      ? KraftColors.secondary
                                      : KraftColors.onSurfaceVariant,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '$doneTasks/$totalTasks',
                                  style: KraftText.labelCode.copyWith(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: allTasksDone
                                        ? KraftColors.secondary
                                        : KraftColors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (hasSketch) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: KraftColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(KraftRadius.sm),
                            ),
                            child: Icon(
                              Symbols.gesture,
                              size: 12,
                              color: KraftColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (hasCanvasLink) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: KraftColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(KraftRadius.sm),
                            ),
                            child: Icon(
                              Symbols.link,
                              size: 12,
                              color: KraftColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const Spacer(),
                        Text(
                          relativeTime(note.updatedAt),
                          style: KraftText.labelCode.copyWith(
                            fontSize: 11,
                            color: KraftColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> deleteNoteWithUndo(BuildContext context, WidgetRef ref, int noteId) async {
  final repo = ref.read(notesRepositoryProvider);
  final overlay = Overlay.of(context, rootOverlay: true);
  final snapshot = await repo.deleteWithSnapshot(noteId);
  KraftToast.showOn(
    overlay,
    'Nota borrada',
    icon: Symbols.delete,
    actionLabel: 'Deshacer',
    onAction: () => repo.restore(snapshot),
  );
}

class NotesEmptyState extends ConsumerWidget {
  const NotesEmptyState({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Center(
      child: Entrance(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          padding: const EdgeInsets.all(KraftSpace.xl),
          decoration: BoxDecoration(
            color: KraftColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(KraftRadius.xl),
            border: Border.all(color: KraftColors.outlineVariant.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: KraftColors.shadow.withValues(alpha: 0.2),
                offset: const Offset(0, 4),
                blurRadius: 10,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: KraftColors.primaryContainer.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: Icon(Symbols.edit_note, size: 32, color: KraftColors.primary),
              ),
              const SizedBox(height: KraftSpace.md),
              Text(
                'Escribe tu primera nota',
                style: KraftText.headlineSm.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: KraftSpace.xs),
              Text(
                'Captura ideas, actas de reuniones o bocetos libres con soporte táctil y markdown.',
                style: KraftText.bodySm.copyWith(color: KraftColors.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: KraftSpace.lg),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: KraftColors.primaryContainer,
                  foregroundColor: KraftColors.onPrimaryContainer,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(KraftRadius.md),
                    side: BorderSide(color: KraftColors.border),
                  ),
                ),
                onPressed: () => createNoteAndOpen(context, ref),
                icon: const Icon(Symbols.add, size: 18),
                label: Text(
                  'Crear primera nota',
                  style: KraftText.labelCode.copyWith(
                    fontWeight: FontWeight.w700,
                    color: KraftColors.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
