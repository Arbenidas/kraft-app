import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../theme/kraft_colors.dart';
import 'canvas_icons.dart';
import 'canvas_items.dart';
import 'canvas_models.dart';

enum ElementCategory {
  study('APRENDER', Symbols.school),
  basics('BÁSICOS', Symbols.category),
  notes('NOTAS', Symbols.sticky_note_2),
  cards('TARJETAS', Symbols.web_asset),
  text('TEXTO', Symbols.text_fields),
  icons('ICONOS', Symbols.emoji_symbols);

  const ElementCategory(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Plantilla de la galería: un elemento listo para colocar.
class ElementTemplate {
  const ElementTemplate({
    required this.name,
    required this.category,
    required this.prototype,
    this.icon,
    this.description = '',
  });

  final String name;
  final ElementCategory category;

  /// Elemento de muestra en (0, 0); al colocarlo se centra en el punto elegido.
  final CanvasItem prototype;

  /// Icono para menús compactos (menú radial).
  final IconData? icon;
  final String description;

  CanvasItem placeAt(Offset center) {
    final size = canvasItemSize(prototype);
    return prototype.copyWith(
      position: center - Offset(size.width / 2, size.height / 2),
    );
  }
}

CanvasItem _proto(
  CanvasItemType type, {
  String title = '',
  String subtitle = '',
  String label = '',
  String? iconKey,
  Color? color,
  ShapeKind shape = ShapeKind.rectangle,
  ItemScale scale = ItemScale.medium,
  bool active = false,
  List<String> bullets = const [],
}) => CanvasItem(
  id: 'template',
  type: type,
  position: Offset.zero,
  title: title,
  subtitle: subtitle,
  label: label,
  iconKey: iconKey,
  color: color,
  shape: shape,
  scale: scale,
  active: active,
  bullets: bullets,
);

final elementCatalog = <ElementTemplate>[
  ElementTemplate(
    name: 'Concepto clave',
    description: 'Idea principal y sus rasgos',
    category: ElementCategory.study,
    prototype: _proto(
      CanvasItemType.card,
      title: 'Concepto clave',
      subtitle: 'Defínelo con tus propias palabras',
      label: 'CONCEPTO',
      iconKey: 'lightbulb',
      color: KraftColors.primaryContainer,
      bullets: const ['Qué significa', 'Por qué importa'],
    ),
    icon: Symbols.lightbulb,
  ),
  ElementTemplate(
    name: 'Definición',
    description: 'Término y explicación precisa',
    category: ElementCategory.study,
    prototype: _proto(
      CanvasItemType.card,
      title: 'Término',
      subtitle: 'Explicación breve y precisa',
      label: 'DEFINICIÓN',
      iconKey: 'search',
      color: KraftColors.tertiaryContainer,
    ),
    icon: Symbols.dictionary,
  ),
  ElementTemplate(
    name: 'Ejemplo',
    description: 'Caso concreto para aterrizar la idea',
    category: ElementCategory.study,
    prototype: _proto(
      CanvasItemType.card,
      title: 'Ejemplo práctico',
      subtitle: 'Así se ve el concepto en acción',
      label: 'EJEMPLO',
      iconKey: 'check_circle',
      color: KraftColors.secondaryContainer,
    ),
    icon: Symbols.science,
  ),
  ElementTemplate(
    name: 'Pregunta',
    description: 'Duda que falta resolver',
    category: ElementCategory.study,
    prototype: _proto(
      CanvasItemType.sticky,
      title: '¿Qué necesito entender mejor?',
      subtitle: 'Anota aquí la respuesta cuando la encuentres',
      label: 'PREGUNTA',
      iconKey: 'help',
      color: KraftColors.errorContainer,
    ),
    icon: Symbols.help,
  ),
  ElementTemplate(
    name: 'Comparación',
    description: 'Similitudes y diferencias',
    category: ElementCategory.study,
    prototype: _proto(
      CanvasItemType.card,
      title: 'A frente a B',
      subtitle: 'Compara cuándo conviene cada opción',
      label: 'COMPARA',
      iconKey: 'compare',
      bullets: const ['Se parecen en…', 'Se diferencian en…'],
      color: KraftColors.surfaceContainerHigh,
    ),
    icon: Symbols.compare_arrows,
  ),
  ElementTemplate(
    name: 'Repaso',
    description: 'Lista breve para comprobar dominio',
    category: ElementCategory.study,
    prototype: const CanvasItem(
      id: 'template',
      type: CanvasItemType.checklist,
      position: Offset.zero,
      title: 'Puedo explicarlo\nPuedo dar un ejemplo\nPuedo relacionarlo',
      checks: [false, false, false],
    ),
    icon: Symbols.fact_check,
  ),
  for (final shape in ShapeKind.values)
    ElementTemplate(
      name: shape.label,
      category: ElementCategory.basics,
      prototype: _proto(CanvasItemType.shape, shape: shape),
      icon: switch (shape) {
        ShapeKind.rectangle => Symbols.rectangle,
        ShapeKind.ellipse => Symbols.circle,
        ShapeKind.diamond => Symbols.shapes,
        ShapeKind.triangle => Symbols.change_history,
        ShapeKind.arrow => Symbols.arrow_right_alt,
        ShapeKind.line => Symbols.horizontal_rule,
      },
    ),
  ElementTemplate(
    name: 'Marco',
    description: 'Contenedor para organizar una capa, fase o grupo',
    category: ElementCategory.basics,
    prototype: const CanvasItem(
      id: 'template',
      type: CanvasItemType.frame,
      position: Offset.zero,
      title: 'Marco',
      width: 520,
      height: 360,
    ),
    icon: Symbols.dashboard_customize,
  ),
  for (final (color, name) in canvasFillColors.take(5))
    ElementTemplate(
      name: 'Nota ${name.toLowerCase()}',
      category: ElementCategory.notes,
      prototype: _proto(
        CanvasItemType.sticky,
        title: 'Nueva idea',
        label: 'NOTA',
        color: color,
      ),
      icon: Symbols.sticky_note_2,
    ),
  ElementTemplate(
    name: 'Paso',
    category: ElementCategory.cards,
    prototype: _proto(
      CanvasItemType.node,
      title: 'Nuevo paso',
      subtitle: 'Describe este paso',
      label: 'PASO',
      iconKey: 'bolt',
    ),
    icon: Symbols.web_asset,
  ),
  ElementTemplate(
    name: 'Tarjeta',
    category: ElementCategory.cards,
    prototype: _proto(
      CanvasItemType.card,
      title: 'Tarjeta',
      subtitle: 'Texto de apoyo',
      label: 'Tema',
      iconKey: 'lightbulb',
    ),
    icon: Symbols.style,
  ),
  ElementTemplate(
    name: 'Tarjeta verde',
    category: ElementCategory.cards,
    prototype: _proto(
      CanvasItemType.card,
      title: 'Aprobado',
      subtitle: 'Listo para producción',
      iconKey: 'check_circle',
      color: KraftColors.secondaryContainer,
    ),
    icon: Symbols.check_circle,
  ),
  ElementTemplate(
    name: 'Tarjeta alerta',
    category: ElementCategory.cards,
    prototype: _proto(
      CanvasItemType.card,
      title: 'Bloqueo',
      subtitle: 'Necesita revisión',
      iconKey: 'warning',
      color: KraftColors.errorContainer,
    ),
    icon: Symbols.warning,
  ),
  ElementTemplate(
    name: 'Párrafo',
    category: ElementCategory.text,
    prototype: _proto(CanvasItemType.paragraph),
    icon: Symbols.notes,
  ),
  ElementTemplate(
    name: 'Encabezado',
    category: ElementCategory.text,
    prototype: const CanvasItem(
      id: 'template',
      type: CanvasItemType.paragraph,
      position: Offset.zero,
      block: BlockStyle.heading,
    ),
    icon: Symbols.format_h1,
  ),
  ElementTemplate(
    name: 'Idea central',
    category: ElementCategory.text,
    prototype: const CanvasItem(
      id: 'template',
      type: CanvasItemType.paragraph,
      position: Offset.zero,
      block: BlockStyle.callout,
    ),
    icon: Symbols.lightbulb,
  ),
  ElementTemplate(
    name: 'Checklist',
    category: ElementCategory.text,
    prototype: _proto(CanvasItemType.checklist),
    icon: Symbols.checklist,
  ),
  ElementTemplate(
    name: 'Título',
    category: ElementCategory.text,
    prototype: _proto(
      CanvasItemType.text,
      title: 'Título',
      scale: ItemScale.large,
    ),
    icon: Symbols.title,
  ),
  ElementTemplate(
    name: 'Subtítulo',
    category: ElementCategory.text,
    prototype: _proto(CanvasItemType.text, title: 'Subtítulo'),
    icon: Symbols.text_fields,
  ),
  ElementTemplate(
    name: 'Texto',
    category: ElementCategory.text,
    prototype: _proto(
      CanvasItemType.text,
      title: 'Texto',
      scale: ItemScale.small,
    ),
    icon: Symbols.text_fields,
  ),
  for (final MapEntry(key: key, value: (icon, name)) in canvasIcons.entries)
    ElementTemplate(
      name: name,
      category: ElementCategory.icons,
      prototype: _proto(CanvasItemType.icon, iconKey: key),
      icon: icon,
    ),
];

ElementTemplate templateNamed(String name) =>
    elementCatalog.firstWhere((t) => t.name == name);
