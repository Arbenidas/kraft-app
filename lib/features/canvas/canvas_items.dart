import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../theme/kraft_colors.dart';
import '../../theme/kraft_tokens.dart';
import '../../theme/kraft_typography.dart';
import '../../widgets/tech_badge.dart';
import 'canvas_models.dart';
import 'canvas_painters.dart';
import 'text_blocks.dart';

/// Colores de fondo que ofrece el editor (notas, formas, tarjetas e iconos).
/// Getters: una lista `final` global se congela con la paleta del primer arranque
/// y las muestras de color se quedaban en el tema anterior.
List<(Color, String)> get canvasFillColors => [
  (KraftColors.surfaceContainerLowest, 'Blanco'),
  (KraftColors.primaryContainer, 'Amarillo'),
  (KraftColors.secondaryContainer, 'Verde'),
  (KraftColors.tertiaryContainer, 'Cian'),
  (KraftColors.errorContainer, 'Rosa'),
  (KraftColors.surfaceContainerHigh, 'Gris'),
];

/// Tintas para texto y formas de línea.
List<(Color, String)> get canvasInkColors => [
  (KraftColors.ink, 'Negro'),
  (KraftColors.primary, 'Oliva'),
  (KraftColors.secondary, 'Verde'),
  (KraftColors.tertiary, 'Azul'),
  (KraftColors.error, 'Rojo'),
];

/// Color efectivo del elemento.
Color canvasItemColor(CanvasItem item) =>
    item.color ??
    switch (item.type) {
      CanvasItemType.sticky => KraftColors.primaryContainer,
      CanvasItemType.text => KraftColors.ink,
      CanvasItemType.shape when item.shape.isStroke => KraftColors.ink,
      CanvasItemType.icon => KraftColors.primaryContainer,
      CanvasItemType.card => KraftColors.primaryContainer,
      CanvasItemType.paragraph || CanvasItemType.checklist => KraftColors.ink,
      CanvasItemType.frame => KraftColors.tertiaryContainer,
      CanvasItemType.link => KraftColors.tertiaryContainer,
      _ => KraftColors.surfaceContainerLowest,
    };

/// Tamaño de referencia (antes de maquetar) según tipo y escala.
Size canvasItemSize(CanvasItem item) {
  final base = switch (item.type) {
    CanvasItemType.node => Size(
      item.active ? 192 : 160,
      128 + (item.target == null ? 0 : 28),
    ),
    CanvasItemType.sticky => Size(224, 150 + (item.target == null ? 0 : 28)),
    CanvasItemType.shape => switch (item.shape) {
      ShapeKind.rectangle => const Size(180, 110),
      ShapeKind.ellipse || ShapeKind.diamond => const Size(150, 150),
      ShapeKind.triangle => const Size(160, 140),
      ShapeKind.arrow => const Size(200, 48),
      ShapeKind.line => const Size(200, 24),
    },
    CanvasItemType.text => const Size(240, 40),
    CanvasItemType.wireframe => const Size(280, 240),
    CanvasItemType.icon => const Size(72, 72),
    CanvasItemType.card => const Size(260, 150),
    CanvasItemType.paragraph ||
    CanvasItemType.checklist ||
    CanvasItemType.link ||
    CanvasItemType.frame => Size.zero,
  };
  return switch (item.type) {
    CanvasItemType.paragraph => _paragraphSize(item),
    CanvasItemType.checklist => Size(
      item.width ?? TextBlocks.checklistWidth,
      TextBlocks.checklistRow * item.checklistLines.length.clamp(1, 999) +
          TextBlocks.checklistPadding * 2,
    ),
    CanvasItemType.link => TextBlocks.linkSize,
    CanvasItemType.frame => Size(item.width ?? 520, item.height ?? 360),
    // Las tarjetas crecen con sus puntos de detalle.
    CanvasItemType.card => Size(
      (item.width ?? 260) * item.scale.factor,
      (150 + item.bullets.length * 24 + (item.target == null ? 0 : 28)) *
          item.scale.factor,
    ),
    _ => base * item.scale.factor,
  };
}

/// Estimación antes de maquetar (luego se usa el tamaño real medido).
Size _paragraphSize(CanvasItem item) {
  final width = item.width ?? TextBlocks.paragraphWidth;
  final style = TextBlocks.style(item.block);
  final fontSize = style.fontSize!;
  final charsPerLine = (width / (fontSize * 0.52)).floor().clamp(1, 1000);
  final text = item.title.isEmpty ? TextBlocks.placeholder(item) : item.title;
  final lines = text
      .split('\n')
      .fold(
        0,
        (sum, l) => sum + (l.length / charsPerLine).ceil().clamp(1, 1000),
      );
  final height = lines * fontSize * (style.height ?? 1.3) + 8;
  return Size(width, item.block == BlockStyle.callout ? height + 48 : height);
}

class CanvasItemView extends StatelessWidget {
  const CanvasItemView({super.key, required this.item});

  final CanvasItem item;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final child = switch (item.type) {
      CanvasItemType.node => _NodeCard(item: item),
      CanvasItemType.sticky => _StickyNote(item: item),
      CanvasItemType.shape => _Shape(item: item),
      CanvasItemType.text => _TextLabel(item: item),
      CanvasItemType.wireframe => _WireframeSketch(item: item),
      CanvasItemType.icon => _IconItem(item: item),
      CanvasItemType.card => _Card(item: item),
      CanvasItemType.paragraph => ParagraphView(item: item),
      CanvasItemType.checklist => ChecklistView(item: item),
      CanvasItemType.link => LinkChipView(item: item),
      CanvasItemType.frame => _Frame(item: item),
    };
    return Align(
      alignment: Alignment.topLeft,
      widthFactor: item.zoom,
      heightFactor: item.zoom,
      child: Transform.scale(
        scale: item.zoom,
        alignment: Alignment.topLeft,
        child: child,
      ),
    );
  }
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({required this.item});

  final CanvasItem item;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final size = canvasItemSize(item);
    final f = item.scale.factor;
    return Container(
      width: size.width,
      decoration: BoxDecoration(
        color: item.color ?? KraftColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(KraftRadius.lg),
        border: KraftBorder.ink(),
        boxShadow: KraftShadow.hard(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: item.active
                  ? KraftColors.primaryContainer
                  : KraftColors.surfaceContainerHigh,
              border: Border(
                bottom: BorderSide(color: KraftColors.ink, width: 2),
              ),
            ),
            child: Row(
              children: [
                if (item.icon != null) ...[
                  Icon(
                    item.icon,
                    size: 14,
                    color: item.active
                        ? KraftColors.onPrimaryContainer
                        : KraftColors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KraftText.techBadge.copyWith(
                      fontSize: 10,
                      color: item.active
                          ? KraftColors.onPrimaryContainer
                          : KraftColors.onSurfaceVariant,
                    ),
                  ),
                ),
                if (item.active)
                  TechBadge(
                    'ACTIVO',
                    background: KraftColors.ink,
                    foreground: KraftColors.surface,
                    fontSize: 9,
                  )
                else
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: KraftColors.secondaryContainer,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title.toUpperCase(),
                  style: KraftText.headlineSm.copyWith(
                    fontSize: 16 * f,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                if (item.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.subtitle,
                    style: KraftText.bodySm.copyWith(fontSize: 12 * f),
                  ),
                ],
                if (item.target != null) ...[
                  const SizedBox(height: 8),
                  _LinkedResourceBadge(target: item.target!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StickyNote extends StatelessWidget {
  const _StickyNote({required this.item});

  final CanvasItem item;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final divider = BorderSide(
      color: KraftColors.onColor(canvasItemColor(item)).withValues(alpha: 0.2),
    );
    final f = item.scale.factor;
    return Transform.rotate(
      angle: -2 * math.pi / 180,
      child: Container(
        width: canvasItemSize(item).width,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: canvasItemColor(item),
          borderRadius: BorderRadius.circular(KraftRadius.lg),
          border: KraftBorder.ink(),
          boxShadow: KraftShadow.hard(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(border: Border(bottom: divider)),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.label.isEmpty ? 'NOTA' : item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KraftText.techBadge.copyWith(
                        fontSize: 10,
                        color: KraftColors.onColor(
                          canvasItemColor(item),
                        ).withValues(alpha: 0.7),
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  Icon(
                    item.icon ?? Symbols.push_pin,
                    size: 15,
                    color: KraftColors.onColor(canvasItemColor(item)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: KraftSpace.sm),
              child: Text(
                item.title,
                style: KraftText.headlineSm.copyWith(
                  color: KraftColors.onColor(canvasItemColor(item)),
                  fontSize: 15 * f,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
            if (item.subtitle.isNotEmpty)
              Container(
                padding: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(border: Border(top: divider)),
                child: Text(
                  item.subtitle,
                  style: KraftText.labelCode.copyWith(
                    fontSize: 10 * f,
                    color: KraftColors.onColor(
                      canvasItemColor(item),
                    ).withValues(alpha: 0.8),
                  ),
                ),
              ),
            if (item.target != null) ...[
              const SizedBox(height: 6),
              _LinkedResourceBadge(target: item.target!),
            ],
          ],
        ),
      ),
    );
  }
}

class _Shape extends StatelessWidget {
  const _Shape({required this.item});

  final CanvasItem item;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final size = canvasItemSize(item);
    final hasText = !item.shape.isStroke && item.title.isNotEmpty;
    return SizedBox.fromSize(
      size: size,
      child: CustomPaint(
        painter: ShapePainter(shape: item.shape, color: canvasItemColor(item)),
        child: hasText
            ? Center(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    item.shape == ShapeKind.triangle ? size.height * 0.35 : 12,
                    16,
                    12,
                  ),
                  child: Text(
                    item.title.toUpperCase(),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: KraftText.labelCode.copyWith(
                      color: KraftColors.onColor(canvasItemColor(item)),
                      fontWeight: FontWeight.w700,
                      fontSize: 13 * item.scale.factor,
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

/// Formas neobrutalistas: sombra dura desplazada + relleno + borde de tinta.
class ShapePainter extends CustomPainter {
  const ShapePainter({required this.shape, required this.color});

  final ShapeKind shape;
  final Color color;

  static const _shadow = 4.0;
  static const _stroke = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (shape.isStroke) {
      _paintLine(canvas, size);
      return;
    }
    final body = _path(Size(size.width - _shadow, size.height - _shadow));
    canvas
      ..drawPath(
        body.shift(const Offset(_shadow, _shadow)),
        Paint()..color = KraftColors.ink,
      )
      ..drawPath(body, Paint()..color = color)
      ..drawPath(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _stroke
          ..strokeJoin = StrokeJoin.round
          ..color = KraftColors.ink,
      );
  }

  Path _path(Size s) {
    final r = Offset.zero & s;
    return switch (shape) {
      ShapeKind.rectangle =>
        Path()..addRRect(
          RRect.fromRectAndRadius(
            r.deflate(1),
            const Radius.circular(KraftRadius.md),
          ),
        ),
      ShapeKind.ellipse => Path()..addOval(r.deflate(1)),
      ShapeKind.diamond =>
        Path()
          ..moveTo(s.width / 2, 1)
          ..lineTo(s.width - 1, s.height / 2)
          ..lineTo(s.width / 2, s.height - 1)
          ..lineTo(1, s.height / 2)
          ..close(),
      ShapeKind.triangle =>
        Path()
          ..moveTo(s.width / 2, 1)
          ..lineTo(s.width - 1, s.height - 1)
          ..lineTo(1, s.height - 1)
          ..close(),
      _ => Path(),
    };
  }

  void _paintLine(Canvas canvas, Size size) {
    final y = size.height / 2;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final end = shape == ShapeKind.arrow ? size.width - 14 : size.width - 4;
    canvas.drawLine(Offset(4, y), Offset(end, y), paint);
    if (shape == ShapeKind.arrow) {
      canvas.drawPath(
        Path()
          ..moveTo(size.width - 2, y)
          ..lineTo(size.width - 20, y - 12)
          ..lineTo(size.width - 20, y + 12)
          ..close(),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(ShapePainter old) =>
      old.shape != shape || old.color != color;
}

class _TextLabel extends StatelessWidget {
  const _TextLabel({required this.item});

  final CanvasItem item;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final fontSize = switch (item.scale) {
      ItemScale.small => 16.0,
      ItemScale.medium => 22.0,
      ItemScale.large => 34.0,
    };
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: canvasItemSize(item).width * 1.6),
      child: Text(
        item.title.isEmpty ? 'Texto' : item.title,
        style: KraftText.headlineSm.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: fontSize,
          height: 1.2,
          color: canvasItemColor(item),
        ),
      ),
    );
  }
}

class _IconItem extends StatelessWidget {
  const _IconItem({required this.item});

  final CanvasItem item;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final size = canvasItemSize(item);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size.width,
          height: size.height,
          decoration: BoxDecoration(
            color: canvasItemColor(item),
            borderRadius: BorderRadius.circular(KraftRadius.lg),
            border: KraftBorder.ink(),
            boxShadow: KraftShadow.hard(3),
          ),
          child: Icon(
            item.icon ?? Symbols.star,
            size: size.width * 0.52,
            color: KraftColors.ink,
          ),
        ),
        if (item.title.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            item.title.toUpperCase(),
            style: KraftText.techBadge.copyWith(
              fontSize: 10 * item.scale.factor,
            ),
          ),
        ],
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.item});

  final CanvasItem item;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final size = canvasItemSize(item);
    final f = item.scale.factor;
    return Container(
      width: size.width,
      decoration: BoxDecoration(
        color: KraftColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(KraftRadius.lg),
        border: KraftBorder.ink(),
        boxShadow: KraftShadow.hard(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 44 * f,
              decoration: BoxDecoration(
                color: canvasItemColor(item),
                border: Border(
                  right: BorderSide(color: KraftColors.ink, width: 2),
                ),
              ),
              alignment: Alignment.topCenter,
              padding: const EdgeInsets.only(top: 12),
              child: Icon(
                item.icon ?? Symbols.bolt,
                size: 22 * f,
                color: KraftColors.onColor(canvasItemColor(item)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item.label.isNotEmpty) ...[
                      Text(
                        item.label.toUpperCase(),
                        style: KraftText.techBadge.copyWith(
                          fontSize: 10,
                          color: KraftColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      item.title.isEmpty ? 'Tarjeta' : item.title,
                      style: KraftText.headlineSm.copyWith(
                        fontSize: 17 * f,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    if (item.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        item.subtitle,
                        style: KraftText.bodySm.copyWith(
                          fontSize: 12.5 * f,
                          color: KraftColors.onSurface,
                        ),
                      ),
                    ],
                    for (final bullet in item.bullets) ...[
                      const SizedBox(height: 5),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 5, right: 6),
                            child: Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: KraftColors.ink,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              bullet,
                              style: KraftText.bodySm.copyWith(
                                fontSize: 12 * f,
                                height: 1.3,
                                color: KraftColors.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (item.target != null) ...[
                      const SizedBox(height: 10),
                      _LinkedResourceBadge(target: item.target!),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkedResourceBadge extends StatelessWidget {
  const _LinkedResourceBadge({required this.target});

  final String target;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final note = target.startsWith('note:');
    return Semantics(
      label: note ? 'Nota vinculada' : 'Lienzo vinculado',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: KraftColors.tertiaryContainer,
          borderRadius: BorderRadius.circular(KraftRadius.sm),
          border: Border.all(color: KraftColors.ink, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              note ? Symbols.sticky_note_2 : Symbols.gesture,
              size: 13,
              color: KraftColors.ink,
            ),
            const SizedBox(width: 4),
            Text(
              note ? 'ABRIR NOTA' : 'ABRIR LIENZO',
              style: KraftText.techBadge.copyWith(
                fontSize: 8.5,
                color: KraftColors.ink,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Symbols.arrow_outward, size: 12),
          ],
        ),
      ),
    );
  }
}

/// Marco con título: agrupa elementos (capa, fase, carril) y se pinta detrás de ellos.
class _Frame extends StatelessWidget {
  const _Frame({required this.item});

  final CanvasItem item;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final size = canvasItemSize(item);
    final color = canvasItemColor(item);
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(KraftRadius.lg),
        border: Border.all(
          color: KraftColors.onColor(canvasItemColor(item)),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(KraftRadius.lg - 2),
              ),
              border: Border(
                bottom: BorderSide(
                  color: KraftColors.onColor(canvasItemColor(item)),
                  width: 2,
                ),
              ),
            ),
            child: Row(
              children: [
                if (item.icon != null) ...[
                  Icon(
                    item.icon,
                    size: 16,
                    color: KraftColors.onColor(canvasItemColor(item)),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    item.title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KraftText.techBadge.copyWith(
                      fontSize: 12,
                      color: KraftColors.onColor(canvasItemColor(item)),
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                if (item.subtitle.isNotEmpty)
                  Text(
                    item.subtitle,
                    style: KraftText.labelCode.copyWith(
                      fontSize: 11,
                      color: KraftColors.onColor(canvasItemColor(item)),
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

class _WireframeSketch extends StatelessWidget {
  const _WireframeSketch({required this.item});

  final CanvasItem item;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Opacity(
      opacity: 0.9,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: WireframeSketchPainter.size,
            painter: WireframeSketchPainter(),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(
              item.label,
              style: KraftText.labelCode.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: KraftColors.tertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
