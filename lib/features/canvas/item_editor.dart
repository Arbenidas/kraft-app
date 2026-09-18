import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../theme/kraft_colors.dart';
import '../../theme/kraft_motion.dart';
import '../../theme/kraft_tokens.dart';
import '../../theme/kraft_typography.dart';
import '../../widgets/neo_box.dart';
import '../../widgets/neo_sheet.dart';
import 'canvas_icons.dart';
import 'canvas_items.dart';
import 'canvas_models.dart';
import 'link_picker.dart';

/// Resultado del editor: el elemento modificado, o la orden de borrarlo.
sealed class ItemEditResult {
  const ItemEditResult();
}

class ItemEdited extends ItemEditResult {
  const ItemEdited(this.item);
  final CanvasItem item;
}

class ItemDeleted extends ItemEditResult {
  const ItemDeleted();
}

Future<ItemEditResult?> showItemEditor(BuildContext context, CanvasItem item) {
  return showNeoSheet<ItemEditResult>(
    context,
    eyebrow: 'EDITAR ELEMENTO',
    title: _typeName(item),
    builder: (_) => _ItemEditor(item: item),
  );
}

String _typeName(CanvasItem item) => switch (item.type) {
  CanvasItemType.node => 'Paso',
  CanvasItemType.sticky => 'Nota adhesiva',
  CanvasItemType.shape => item.shape.label,
  CanvasItemType.text => 'Texto',
  CanvasItemType.wireframe => 'Wireframe',
  CanvasItemType.icon => 'Icono',
  CanvasItemType.card => 'Tarjeta',
  CanvasItemType.paragraph => item.block.label,
  CanvasItemType.checklist => 'Checklist',
  CanvasItemType.link => 'Enlace',
  CanvasItemType.frame => 'Marco',
};

class _ItemEditor extends StatefulWidget {
  const _ItemEditor({required this.item});

  final CanvasItem item;

  @override
  State<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<_ItemEditor> {
  late CanvasItem _draft = widget.item;
  late final _title = TextEditingController(text: widget.item.title);
  late final _subtitle = TextEditingController(text: widget.item.subtitle);
  late final _label = TextEditingController(text: widget.item.label);

  CanvasItemType get _type => widget.item.type;
  bool get _hasSubtitle =>
      _type == CanvasItemType.node ||
      _type == CanvasItemType.sticky ||
      _type == CanvasItemType.card;
  bool get _hasLabel => _hasSubtitle || _type == CanvasItemType.wireframe;
  bool get _hasTitle =>
      _type != CanvasItemType.wireframe &&
      !(_type == CanvasItemType.shape && _draft.shape.isStroke);
  bool get _hasIcon =>
      _type == CanvasItemType.node ||
      _type == CanvasItemType.card ||
      _type == CanvasItemType.icon ||
      _type == CanvasItemType.sticky;
  bool get _usesInk =>
      _type == CanvasItemType.text ||
      (_type == CanvasItemType.shape && _draft.shape.isStroke);
  bool get _hasColor => _type != CanvasItemType.wireframe;
  bool get _canLink =>
      _type == CanvasItemType.node ||
      _type == CanvasItemType.sticky ||
      _type == CanvasItemType.card;

  @override
  void initState() {
    super.initState();
    void sync() => setState(() {
      _draft = _draft.copyWith(
        title: _title.text,
        subtitle: _subtitle.text,
        label: _label.text,
      );
    });
    _title.addListener(sync);
    _subtitle.addListener(sync);
    _label.addListener(sync);
  }

  @override
  void dispose() {
    _title.dispose();
    _subtitle.dispose();
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final colors = _usesInk ? canvasInkColors : canvasFillColors;
    final currentColor = canvasItemColor(_draft);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Vista previa en vivo.
        Container(
          height: 150,
          decoration: BoxDecoration(
            color: KraftColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(KraftRadius.lg),
            border: Border.all(color: KraftColors.outlineVariant),
          ),
          padding: const EdgeInsets.all(16),
          child: IgnorePointer(
            child: FittedBox(
              child: AnimatedSwitcher(
                duration: KraftMotion.of(context, KraftMotion.fast),
                child: Padding(
                  key: ValueKey(
                    Object.hash(
                      _draft.scale,
                      _draft.shape,
                      _draft.color,
                      _draft.iconKey,
                      _draft.active,
                    ),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: CanvasItemView(item: _draft),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: KraftSpace.md),
        if (_hasTitle) ...[
          NeoTextField(
            label: _type == CanvasItemType.icon
                ? 'Etiqueta bajo el icono'
                : 'Título',
            controller: _title,
            maxLines: 3,
          ),
          const SizedBox(height: KraftSpace.md),
        ],
        if (_hasSubtitle) ...[
          NeoTextField(label: 'Texto', controller: _subtitle, maxLines: 4),
          const SizedBox(height: KraftSpace.md),
        ],
        if (_hasLabel) ...[
          NeoTextField(label: 'Etiqueta', controller: _label),
          const SizedBox(height: KraftSpace.md),
        ],
        if (_type == CanvasItemType.shape) ...[
          NeoChoice<ShapeKind>(
            label: 'Forma',
            value: _draft.shape,
            onChanged: (v) =>
                setState(() => _draft = _draft.copyWith(shape: v)),
            options: [
              for (final k in ShapeKind.values)
                (k, k.label, KraftColors.primaryContainer),
            ],
          ),
          const SizedBox(height: KraftSpace.md),
        ],
        if (_hasColor) ...[
          Text(
            (_usesInk ? 'Tinta' : 'Color').toUpperCase(),
            style: KraftText.techBadge.copyWith(
              color: KraftColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final (color, name) in colors)
                _Swatch(
                  color: color,
                  name: name,
                  selected: color == currentColor,
                  onTap: () =>
                      setState(() => _draft = _draft.copyWith(color: color)),
                ),
            ],
          ),
          const SizedBox(height: KraftSpace.md),
        ],
        if (_hasIcon) ...[
          Text(
            'ICONO',
            style: KraftText.techBadge.copyWith(
              color: KraftColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (_type != CanvasItemType.icon)
                _IconOption(
                  icon: Symbols.block,
                  name: 'Sin icono',
                  selected: _draft.iconKey == null,
                  onTap: () =>
                      setState(() => _draft = _draft.copyWith(clearIcon: true)),
                ),
              for (final MapEntry(key: key, value: (icon, name))
                  in canvasIcons.entries)
                _IconOption(
                  icon: icon,
                  name: name,
                  selected: _draft.iconKey == key,
                  onTap: () =>
                      setState(() => _draft = _draft.copyWith(iconKey: key)),
                ),
            ],
          ),
          const SizedBox(height: KraftSpace.md),
        ],
        if (_canLink) ...[
          Text(
            'RECURSO VINCULADO',
            style: KraftText.techBadge.copyWith(
              color: KraftColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          NeoBox(
            onTap: () async {
              final picked = await showLinkPicker(context);
              if (picked != null && mounted)
                setState(() => _draft = _draft.copyWith(target: picked.target));
            },
            color: _draft.target == null
                ? KraftColors.surfaceContainerLow
                : KraftColors.tertiaryContainer,
            borderWidth: 1.5,
            shadow: _draft.target == null ? 0 : 2,
            radius: KraftRadius.md,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  _draft.target?.startsWith('note:') == true
                      ? Symbols.sticky_note_2
                      : Symbols.add_link,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _draft.target == null
                        ? 'Vincular una nota o un lienzo'
                        : '${_draft.target!.startsWith('note:') ? 'Nota' : 'Lienzo'} vinculado · ${_draft.target!.split(':').last}',
                    style: KraftText.bodySm.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (_draft.target != null)
                  IconButton(
                    tooltip: 'Quitar vínculo',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(
                      () => _draft = _draft.copyWith(clearTarget: true),
                    ),
                    icon: const Icon(Symbols.link_off, size: 19),
                  )
                else
                  const Icon(Symbols.chevron_right, size: 20),
              ],
            ),
          ),
          const SizedBox(height: KraftSpace.md),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            NeoChoice<ItemScale>(
              label: 'Tamaño',
              value: _draft.scale,
              onChanged: (v) =>
                  setState(() => _draft = _draft.copyWith(scale: v)),
              options: [
                for (final s in ItemScale.values)
                  (s, s.label, KraftColors.primaryContainer),
              ],
            ),
            if (_type == CanvasItemType.node) ...[
              SizedBox(width: KraftSpace.lg),
              NeoChoice<bool>(
                label: 'Estado',
                value: _draft.active,
                onChanged: (v) =>
                    setState(() => _draft = _draft.copyWith(active: v)),
                options: [
                  (false, 'Normal', KraftColors.surfaceContainerHigh),
                  (true, 'Activo', KraftColors.primaryContainer),
                ],
              ),
            ],
          ],
        ),
        const SizedBox(height: KraftSpace.lg),
        NeoSheetActions(
          onSave: () => Navigator.pop(context, ItemEdited(_draft)),
          onDelete: () => Navigator.pop(context, const ItemDeleted()),
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Tooltip(
      message: name,
      child: Semantics(
        button: true,
        selected: selected,
        label: name,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: KraftMotion.of(context, KraftMotion.fast),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: KraftColors.ink,
                width: selected ? 3 : 1.5,
              ),
              boxShadow: selected ? KraftShadow.hard(2) : null,
            ),
            child: selected
                ? Icon(
                    Symbols.check,
                    size: 18,
                    color: color.computeLuminance() > 0.4
                        ? KraftColors.ink
                        : Colors.white,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

class _IconOption extends StatelessWidget {
  const _IconOption({
    required this.icon,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Tooltip(
      message: name,
      child: NeoBox(
        onTap: onTap,
        color: selected
            ? KraftColors.primaryContainer
            : KraftColors.surfaceContainerLowest,
        borderWidth: selected ? 2 : 1,
        shadow: selected ? 2 : 0,
        radius: KraftRadius.md,
        padding: const EdgeInsets.all(7),
        child: Icon(icon, size: 20),
      ),
    );
  }
}
