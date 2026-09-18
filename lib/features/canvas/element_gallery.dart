import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../theme/kraft_colors.dart';
import '../../theme/kraft_motion.dart';
import '../../theme/kraft_tokens.dart';
import '../../theme/kraft_typography.dart';
import 'canvas_items.dart';
import 'element_catalog.dart';

/// Panel desplegable de elementos: tocar inserta en el centro de la vista, arrastrar lo suelta donde quieras.
class ElementGallery extends StatefulWidget {
  const ElementGallery({
    super.key,
    required this.onInsert,
    required this.onDragStarted,
    required this.onClose,
    this.onSearchFocusChanged,
  });

  final ValueChanged<ElementTemplate> onInsert;
  final VoidCallback onDragStarted;
  final VoidCallback onClose;
  final ValueChanged<bool>? onSearchFocusChanged;

  static const width = 560.0;

  @override
  State<ElementGallery> createState() => _ElementGalleryState();
}

class _ElementGalleryState extends State<ElementGallery> {
  ElementCategory _category = ElementCategory.basics;
  final _search = TextEditingController();
  late final FocusNode _searchFocus;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchFocus = FocusNode(debugLabel: 'buscar elementos');
    _searchFocus.addListener(_notifySearchFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _notifySearchFocus() =>
      widget.onSearchFocusChanged?.call(_searchFocus.hasFocus);

  @override
  void dispose() {
    _searchFocus
      ..removeListener(_notifySearchFocus)
      ..dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final query = _query.toLowerCase();
    final templates = elementCatalog.where((t) {
      if (query.isEmpty) return t.category == _category;
      return '${t.name} ${t.description} ${t.category.label}'
          .toLowerCase()
          .contains(query);
    }).toList();
    final compact = _category == ElementCategory.icons;
    final availableWidth = MediaQuery.sizeOf(context).width - 32;

    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: ElementGallery.width.clamp(0, availableWidth),
        decoration: BoxDecoration(
          color: KraftColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(KraftRadius.xl),
          border: KraftBorder.ink(),
          boxShadow: KraftShadow.hard(5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              decoration: BoxDecoration(
                color: KraftColors.primaryContainer,
                border: Border(
                  bottom: BorderSide(color: KraftColors.ink, width: 2),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Symbols.widgets, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'ELEMENTOS',
                    style: KraftText.techBadge.copyWith(fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Toca para añadir · arrastra para colocar',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KraftText.labelCode.copyWith(
                        fontSize: 11,
                        color: KraftColors.onPrimaryContainer,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar elementos',
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onClose,
                    icon: const Icon(Symbols.close, size: 18),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: TextField(
                controller: _search,
                focusNode: _searchFocus,
                onChanged: (value) => setState(() => _query = value.trim()),
                textInputAction: TextInputAction.search,
                style: KraftText.bodySm,
                decoration: InputDecoration(
                  hintText: 'Buscar concepto, forma o tarjeta…',
                  prefixIcon: const Icon(Symbols.search, size: 19),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpiar búsqueda',
                          onPressed: () => setState(() {
                            _search.clear();
                            _query = '';
                          }),
                          icon: const Icon(Symbols.close, size: 18),
                        ),
                  filled: true,
                  fillColor: KraftColors.surfaceContainerLow,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(KraftRadius.md),
                    borderSide: BorderSide(color: KraftColors.outlineVariant),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in ElementCategory.values)
                    _CategoryChip(
                      category: c,
                      selected: c == _category,
                      onTap: () => setState(() => _category = c),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: compact ? 220 : 280,
              child: templates.isEmpty
                  ? Center(
                      child: Text(
                        'No encontré elementos',
                        style: KraftText.labelCode.copyWith(
                          color: KraftColors.onSurfaceVariant,
                        ),
                      ),
                    )
                  : GridView.builder(
                      key: ValueKey('$_category-$_query'),
                      padding: const EdgeInsets.all(10),
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: compact ? 58 : 172,
                        mainAxisExtent: compact ? 52 : 116,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: templates.length,
                      itemBuilder: (context, index) => _TemplateTile(
                        template: templates[index],
                        compact: compact,
                        onTap: () => widget.onInsert(templates[index]),
                        onDragStarted: widget.onDragStarted,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final ElementCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Semantics(
      button: true,
      selected: selected,
      label: category.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KraftRadius.md),
        child: AnimatedContainer(
          duration: KraftMotion.of(context, KraftMotion.fast),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? KraftColors.ink : KraftColors.surfaceContainer,
            borderRadius: BorderRadius.circular(KraftRadius.md),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                category.icon,
                size: 15,
                color: selected
                    ? KraftColors.primaryContainer
                    : KraftColors.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Text(
                category.label,
                style: KraftText.techBadge.copyWith(
                  color: selected
                      ? KraftColors.surface
                      : KraftColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({
    required this.template,
    required this.compact,
    required this.onTap,
    required this.onDragStarted,
  });

  final ElementTemplate template;
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback onDragStarted;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final tileSize = compact
        ? const Size(46, 46)
        : const Size(double.infinity, 116);
    final preview = _Preview(
      template: template,
      size: compact ? const Size(34, 34) : const Size(80, 50),
    );

    final tile = Tooltip(
      message: template.description.isEmpty
          ? template.name
          : '${template.name}: ${template.description}',
      child: Semantics(
        button: true,
        label: template.name,
        hint: template.description,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(KraftRadius.md),
          child: Container(
            width: tileSize.width,
            height: tileSize.height,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: KraftColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(KraftRadius.md),
              border: Border.all(color: KraftColors.outlineVariant),
            ),
            child: compact
                ? Center(child: preview)
                : Column(
                    children: [
                      Expanded(child: Center(child: preview)),
                      const SizedBox(height: 3),
                      Text(
                        template.name.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KraftText.techBadge.copyWith(fontSize: 9),
                      ),
                      if (template.description.isNotEmpty)
                        Text(
                          template.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: KraftText.labelCode.copyWith(
                            fontSize: 9,
                            color: KraftColors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );

    return Draggable<ElementTemplate>(
      data: template,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: onDragStarted,
      feedback: FractionalTranslation(
        // El elemento queda centrado bajo el dedo o el lápiz.
        translation: const Offset(-0.5, -0.5),
        child: Opacity(
          opacity: 0.85,
          child: Material(
            type: MaterialType.transparency,
            child: CanvasItemView(item: template.prototype),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: tile),
      child: tile,
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.template, required this.size});

  final ElementTemplate template;
  final Size size;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return SizedBox.fromSize(
      size: size,
      child: IgnorePointer(
        child: FittedBox(
          fit: BoxFit.contain,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: CanvasItemView(item: template.prototype),
          ),
        ),
      ),
    );
  }
}
