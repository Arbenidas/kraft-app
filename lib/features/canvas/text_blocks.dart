import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../theme/kraft_colors.dart';
import '../../theme/kraft_tokens.dart';
import '../../theme/kraft_typography.dart';
import 'canvas_models.dart';

/// Medidas de los bloques de texto de las notas.
abstract final class TextBlocks {
  static const paragraphWidth = 560.0;
  static const checklistWidth = 440.0;
  static const checklistRow = 38.0;
  static const checklistPadding = 6.0;
  static const checkboxColumn = 40.0;
  static const linkSize = Size(300, 72);

  static TextStyle style(BlockStyle block) => switch (block) {
    BlockStyle.heading => KraftText.headlineLg.copyWith(
      fontSize: 34,
      height: 1.15,
      fontWeight: FontWeight.w700,
    ),
    BlockStyle.subheading => KraftText.headlineSm.copyWith(
      fontSize: 22,
      height: 1.25,
      fontWeight: FontWeight.w700,
    ),
    BlockStyle.body => KraftText.bodyLg.copyWith(
      fontSize: 18,
      height: 1.5,
      color: KraftColors.onSurface,
    ),
    BlockStyle.callout => KraftText.bodyLg.copyWith(
      fontSize: 18,
      height: 1.45,
      fontWeight: FontWeight.w600,
    ),
  };

  static String placeholder(CanvasItem item) => switch (item.type) {
    CanvasItemType.checklist => 'Una tarea por línea',
    _ => switch (item.block) {
      BlockStyle.heading => 'Título',
      BlockStyle.subheading => 'Subtítulo',
      BlockStyle.body => 'Escribe con el teclado o con el lápiz…',
      BlockStyle.callout => '¿Cuál es la idea central?',
    },
  };

  /// Fila de la checklist bajo [local] (coordenadas dentro del bloque), si cae sobre una casilla.
  static int? checkboxAt(CanvasItem item, Offset local) {
    if (item.type != CanvasItemType.checklist || local.dx > checkboxColumn)
      return null;
    final row = ((local.dy - checklistPadding) / checklistRow).floor();
    return row >= 0 && row < item.checklistLines.length ? row : null;
  }
}

/// Párrafo, título o idea central.
class ParagraphView extends StatelessWidget {
  const ParagraphView({super.key, required this.item});

  final CanvasItem item;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final style = TextBlocks.style(item.block);
    final empty = item.title.isEmpty;
    final text = Text(
      empty ? TextBlocks.placeholder(item) : item.title,
      style: empty ? style.copyWith(color: KraftColors.outline) : style,
    );
    final width = item.width ?? TextBlocks.paragraphWidth;
    if (item.block != BlockStyle.callout) {
      return SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: text,
        ),
      );
    }
    return _CalloutFrame(width: width, child: text);
  }
}

class _CalloutFrame extends StatelessWidget {
  const _CalloutFrame({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: KraftColors.primaryContainer,
        borderRadius: BorderRadius.circular(KraftRadius.md),
        border: KraftBorder.ink(),
        boxShadow: KraftShadow.hard(3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Symbols.lightbulb, size: 15, color: KraftColors.ink),
              const SizedBox(width: 6),
              Text(
                'IDEA CENTRAL',
                style: KraftText.techBadge.copyWith(
                  color: KraftColors.ink,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

/// Lista de casillas: se marcan tocando la casilla con el dedo o el lápiz.
class ChecklistView extends StatelessWidget {
  const ChecklistView({super.key, required this.item});

  final CanvasItem item;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final lines = item.checklistLines;
    final style = TextBlocks.style(BlockStyle.body);
    return Container(
      width: item.width ?? TextBlocks.checklistWidth,
      padding: const EdgeInsets.symmetric(
        vertical: TextBlocks.checklistPadding,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (lines.isEmpty)
            SizedBox(
              height: TextBlocks.checklistRow,
              child: Row(
                children: [
                  const SizedBox(
                    width: TextBlocks.checkboxColumn,
                    child: _Box(checked: false),
                  ),
                  Text(
                    TextBlocks.placeholder(item),
                    style: style.copyWith(color: KraftColors.outline),
                  ),
                ],
              ),
            ),
          for (final (text, done) in lines)
            SizedBox(
              height: TextBlocks.checklistRow,
              child: Row(
                children: [
                  SizedBox(
                    width: TextBlocks.checkboxColumn,
                    child: _Box(checked: done),
                  ),
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style.copyWith(
                        decoration: done ? TextDecoration.lineThrough : null,
                        color: done ? KraftColors.onSurfaceVariant : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: checked
              ? KraftColors.secondary
              : KraftColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(KraftRadius.sm),
          border: KraftBorder.ink(),
        ),
        child: checked
            ? const Icon(
                Symbols.check,
                size: 18,
                color: Colors.white,
                weight: 700,
              )
            : null,
      ),
    );
  }
}

/// Enlace a un lienzo o nota: tocar dos veces lo abre.
class LinkChipView extends StatelessWidget {
  const LinkChipView({super.key, required this.item});

  final CanvasItem item;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final isNote = item.target?.startsWith('note:') ?? false;
    return Container(
      width: TextBlocks.linkSize.width,
      height: TextBlocks.linkSize.height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isNote
            ? KraftColors.secondaryContainer
            : KraftColors.tertiaryContainer,
        borderRadius: BorderRadius.circular(KraftRadius.lg),
        border: KraftBorder.ink(),
        boxShadow: KraftShadow.hard(3),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: KraftColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(KraftRadius.md),
              border: KraftBorder.ink(),
            ),
            child: Icon(
              isNote ? Symbols.sticky_note_2 : Symbols.gesture,
              size: 24,
              color: KraftColors.ink,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isNote ? 'NOTA ENLAZADA' : 'LIENZO ENLAZADO',
                  style: KraftText.techBadge.copyWith(
                    color: KraftColors.ink,
                    fontSize: 10,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  item.title.isEmpty ? 'Sin título' : item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KraftText.headlineSm.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Icon(Symbols.north_east, size: 20, color: KraftColors.ink),
        ],
      ),
    );
  }
}

/// Edición en el sitio de un párrafo o checklist: un campo de texto con el mismo aspecto.
/// Acepta teclado y Scribble del Apple Pencil (escribir a mano sobre el campo).
class InlineBlockEditor extends StatefulWidget {
  const InlineBlockEditor({
    super.key,
    required this.item,
    required this.onChanged,
    required this.onDone,
  });

  final CanvasItem item;

  /// Texto nuevo mientras se escribe (para medir el bloque en vivo).
  final ValueChanged<String> onChanged;
  final VoidCallback onDone;

  @override
  State<InlineBlockEditor> createState() => _InlineBlockEditorState();
}

class _InlineBlockEditorState extends State<InlineBlockEditor> {
  late final _controller = TextEditingController(text: widget.item.title);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) widget.onDone();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final item = widget.item;
    final checklist = item.type == CanvasItemType.checklist;
    final style = TextBlocks.style(checklist ? BlockStyle.body : item.block);
    final field = Material(
      type: MaterialType.transparency,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              _focus.unfocus(),
        },
        child: TextField(
          controller: _controller,
          focusNode: _focus,
          maxLines: null,
          style: checklist
              ? style.copyWith(
                  height: TextBlocks.checklistRow / style.fontSize!,
                )
              : style,
          cursorColor: KraftColors.ink,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          onChanged: widget.onChanged,
          decoration: InputDecoration(
            isCollapsed: true,
            border: InputBorder.none,
            hintText: TextBlocks.placeholder(item),
            hintStyle: style.copyWith(color: KraftColors.outline),
            contentPadding: checklist
                ? const EdgeInsets.fromLTRB(
                    TextBlocks.checkboxColumn,
                    TextBlocks.checklistPadding,
                    0,
                    TextBlocks.checklistPadding,
                  )
                : const EdgeInsets.symmetric(vertical: 4),
          ),
        ),
      ),
    );
    final width =
        item.width ??
        (checklist ? TextBlocks.checklistWidth : TextBlocks.paragraphWidth);
    final editor = item.block == BlockStyle.callout && !checklist
        ? _CalloutFrame(width: width, child: field)
        : SizedBox(width: width, child: field);
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: Border.all(color: KraftColors.primaryContainer, width: 3),
        borderRadius: BorderRadius.circular(KraftRadius.sm),
      ),
      child: editor,
    );
  }
}
