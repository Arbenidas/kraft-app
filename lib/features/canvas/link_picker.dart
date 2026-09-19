import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/providers.dart';
import '../../theme/kraft_colors.dart';
import '../../theme/kraft_tokens.dart';
import '../../theme/kraft_typography.dart';
import '../../utils/dates.dart';
import '../../widgets/neo_box.dart';
import '../../widgets/neo_sheet.dart';

/// Elige un lienzo o una nota para enlazarlo. Devuelve `canvas:<id>` / `note:<id>` y su título.
Future<({String target, String title})?> showLinkPicker(
  BuildContext context, {
  String? exclude,
}) {
  return showNeoSheet<({String target, String title})>(
    context,
    eyebrow: 'ENLAZAR',
    title: '¿Dónde está la información?',
    builder: (_) => _LinkPicker(exclude: exclude),
  );
}

class _LinkPicker extends ConsumerStatefulWidget {
  const _LinkPicker({this.exclude});

  final String? exclude;

  @override
  ConsumerState<_LinkPicker> createState() => _LinkPickerState();
}

class _LinkPickerState extends ConsumerState<_LinkPicker> {
  String _query = '';

  bool _matches(String title) =>
      _query.isEmpty || title.toLowerCase().contains(_query.toLowerCase());

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final canvases = ref.watch(canvasesProvider).valueOrNull ?? const [];
    final notes = ref.watch(_allNotesProvider).valueOrNull ?? const [];
    final rows = [
      for (final c in canvases)
        if ('canvas:${c.id}' != widget.exclude && _matches(c.title))
          (
            target: 'canvas:${c.id}',
            title: c.title,
            updated: c.updatedAt,
            isNote: false,
          ),
      for (final n in notes)
        if ('note:${n.id}' != widget.exclude &&
            _matches(n.title.isEmpty ? 'Nota sin título' : n.title))
          (
            target: 'note:${n.id}',
            title: n.title.isEmpty ? 'Nota sin título' : n.title,
            updated: n.updatedAt,
            isNote: true,
          ),
    ]..sort((a, b) => b.updated.compareTo(a.updated));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          autofocus: false,
          onChanged: (v) => setState(() => _query = v.trim()),
          style: KraftText.bodyLg,
          decoration: InputDecoration(
            prefixIcon: const Icon(Symbols.search),
            hintText: 'Buscar lienzos y notas…',
            filled: true,
            fillColor: KraftColors.surfaceContainer,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KraftRadius.sm),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: KraftSpace.md),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(KraftSpace.lg),
            child: Text(
              'No hay nada que enlazar todavía.',
              textAlign: TextAlign.center,
              style: KraftText.labelCode,
            ),
          ),
        for (final row in rows.take(12))
          Padding(
            padding: const EdgeInsets.only(bottom: KraftSpace.sm),
            child: NeoBox(
              onTap: () => Navigator.pop(context, (
                target: row.target,
                title: row.title,
              )),
              shadow: 2,
              borderWidth: 1.5,
              radius: KraftRadius.md,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: row.isNote
                          ? KraftColors.secondaryContainer
                          : KraftColors.tertiaryContainer,
                      borderRadius: BorderRadius.circular(KraftRadius.sm),
                      border: KraftBorder.ink(),
                    ),
                    child: Icon(
                      row.isNote ? Symbols.sticky_note_2 : Symbols.gesture,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: KraftText.headlineSm.copyWith(fontSize: 16),
                        ),
                        Text(
                          '${row.isNote ? 'NOTA' : 'LIENZO'} · ${relativeTime(row.updated)}',
                          style: KraftText.techBadge.copyWith(
                            color: KraftColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Symbols.add_link, size: 20),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

final _allNotesProvider = StreamProvider.autoDispose(
  (ref) => ref.watch(notesRepositoryProvider).watchAll(),
);
