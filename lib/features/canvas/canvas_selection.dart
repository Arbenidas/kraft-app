import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../theme/kraft_colors.dart';
import '../../theme/kraft_motion.dart';
import '../../theme/kraft_tokens.dart';
import '../../theme/kraft_typography.dart';
import 'canvas_document.dart';
import 'canvas_models.dart';

/// Marcos de selección: borde de tinta + tiradores amarillos por elemento y caja discontinua del grupo.
class SelectionPainter extends CustomPainter {
  final palette = KraftColors.active;
  SelectionPainter(this.document, {required this.scale})
    : super(repaint: document);

  final CanvasDocument document;

  /// Escala de la vista: los trazos del marco mantienen grosor constante en pantalla.
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    if (!document.hasSelection) return;
    final px = 1 / scale;
    final frame = Paint()
      ..style = PaintingStyle.stroke
      ..color = KraftColors.ink
      ..strokeWidth = 2 * px;
    final handleFill = Paint()..color = KraftColors.primaryContainer;

    for (final item in document.items) {
      if (!document.isItemSelected(item.id)) continue;
      final rect = document.itemRect(item).inflate(6 * px);
      canvas.drawRect(rect, frame);
      final h = 9 * px;
      for (final corner in [
        rect.topLeft,
        rect.topRight,
        rect.bottomLeft,
        rect.bottomRight,
      ]) {
        final handle = Rect.fromCenter(center: corner, width: h, height: h);
        canvas
          ..drawRect(handle, handleFill)
          ..drawRect(handle, frame);
      }
    }

    final bounds = document.selectionBounds;
    if (bounds != null && document.selectionCount > 1) {
      _dashedRect(
        canvas,
        bounds.inflate(14 * px),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = KraftColors.ink.withValues(alpha: 0.7)
          ..strokeWidth = 1.5 * px,
        dash: 6 * px,
        gap: 4 * px,
      );
    }
  }

  @override
  bool shouldRepaint(SelectionPainter old) =>
      old.palette != palette || old.document != document || old.scale != scale;
}

/// Lazo en curso: relleno amarillo translúcido y contorno discontinuo.
class LassoPainter extends CustomPainter {
  final palette = KraftColors.active;
  LassoPainter(this.lasso, {required this.scale}) : super(repaint: lasso);

  final LassoPath lasso;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = lasso.points;
    if (pts.length < 2) return;
    final path = Path()..addPolygon(pts, pts.length > 2);
    canvas.drawPath(
      path,
      Paint()..color = KraftColors.primaryContainer.withValues(alpha: 0.18),
    );
    _dashedPath(
      canvas,
      Path()..addPolygon(pts, false),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = KraftColors.ink
        ..strokeWidth = 2 / scale
        ..strokeCap = StrokeCap.round,
      dash: 7 / scale,
      gap: 5 / scale,
    );
  }

  @override
  bool shouldRepaint(LassoPainter old) =>
      old.palette != palette || old.lasso != lasso || old.scale != scale;
}

void _dashedRect(
  Canvas canvas,
  Rect rect,
  Paint paint, {
  required double dash,
  required double gap,
}) => _dashedPath(canvas, Path()..addRect(rect), paint, dash: dash, gap: gap);

void _dashedPath(
  Canvas canvas,
  Path path,
  Paint paint, {
  required double dash,
  required double gap,
}) {
  for (final ui.PathMetric metric in path.computeMetrics()) {
    for (var d = 0.0; d < metric.length; d += dash + gap) {
      canvas.drawPath(metric.extractPath(d, d + dash), paint);
    }
  }
}

/// Barra flotante sobre la selección, en coordenadas de pantalla.
class SelectionToolbar extends StatelessWidget {
  const SelectionToolbar({
    super.key,
    required this.count,
    required this.hasStrokes,
    required this.canEdit,
    required this.color,
    required this.onDuplicate,
    required this.onFront,
    required this.onRecolor,
    required this.onEdit,
    required this.onDelete,
    this.onGroup,
    this.onUngroup,
    this.scale,
    this.onScale,
    this.blockStyle,
    this.onBlockStyle,
    this.canOpenTarget = false,
    this.onOpenTarget,
  });

  /// Estilo del párrafo seleccionado (título, subtítulo, texto o idea central).
  final BlockStyle? blockStyle;
  final ValueChanged<BlockStyle>? onBlockStyle;
  final bool canOpenTarget;
  final VoidCallback? onOpenTarget;

  final VoidCallback? onGroup;
  final VoidCallback? onUngroup;
  final int count;
  final bool hasStrokes;
  final bool canEdit;
  final Color color;
  final VoidCallback onDuplicate;
  final VoidCallback onFront;
  final VoidCallback onRecolor;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ItemScale? scale;
  final ValueChanged<ItemScale>? onScale;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: KraftColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(KraftRadius.lg),
        border: KraftBorder.ink(),
        boxShadow: KraftShadow.hard(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: KraftColors.primaryContainer,
              borderRadius: BorderRadius.circular(KraftRadius.sm),
            ),
            child: Text(
              count == 1 ? '1 SELECCIONADO' : '$count SELECCIONADOS',
              style: KraftText.techBadge.copyWith(
                color: KraftColors.onPrimaryContainer,
              ),
            ),
          ),
          if (onGroup != null)
            _ToolbarButton(
              icon: Symbols.group_work,
              tooltip: 'Agrupar',
              onTap: onGroup!,
            ),
          if (onUngroup != null)
            _ToolbarButton(
              icon: Symbols.workspaces,
              tooltip: 'Desagrupar',
              onTap: onUngroup!,
            ),
          if (canEdit)
            _ToolbarButton(
              icon: Symbols.edit,
              tooltip: 'Editar elemento',
              onTap: onEdit,
            ),
          if (canOpenTarget && onOpenTarget != null)
            _ToolbarButton(
              icon: Symbols.sticky_note_2,
              tooltip: 'Abrir recurso vinculado',
              onTap: onOpenTarget!,
            ),
          if (blockStyle != null && onBlockStyle != null)
            _ToolbarButton(
              icon: switch (blockStyle!) {
                BlockStyle.heading => Symbols.format_h1,
                BlockStyle.subheading => Symbols.format_h2,
                BlockStyle.body => Symbols.notes,
                BlockStyle.callout => Symbols.lightbulb,
              },
              tooltip: 'Estilo: ${blockStyle!.label}',
              onTap: () => onBlockStyle!(
                BlockStyle.values[(blockStyle!.index + 1) %
                    BlockStyle.values.length],
              ),
            ),
          if (scale != null && onScale != null)
            _ToolbarButton(
              tooltip: 'Tamaño ${scale!.label} · tocar para cambiar',
              onTap: () => onScale!(
                ItemScale.values[(scale!.index + 1) % ItemScale.values.length],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Symbols.zoom_out_map, size: 17),
                  const SizedBox(width: 3),
                  Text(
                    scale!.label,
                    style: KraftText.techBadge.copyWith(fontSize: 10),
                  ),
                ],
              ),
            ),
          _ToolbarButton(
            icon: Symbols.content_copy,
            tooltip: 'Duplicar',
            onTap: onDuplicate,
          ),
          _ToolbarButton(
            icon: Symbols.flip_to_front,
            tooltip: 'Traer al frente',
            onTap: onFront,
          ),
          if (hasStrokes)
            _ToolbarButton(
              tooltip: 'Aplicar color actual',
              onTap: onRecolor,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: KraftColors.ink),
                ),
              ),
            ),
          Container(
            width: 1,
            height: 24,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: KraftColors.outlineVariant,
          ),
          _ToolbarButton(
            icon: Symbols.delete,
            tooltip: 'Borrar selección',
            onTap: onDelete,
            danger: true,
          ),
        ],
      ),
    );
  }
}

/// Barra de la conexión seleccionada: etiqueta, trazado, puntas, dirección y borrar.
class LinkToolbar extends StatelessWidget {
  const LinkToolbar({
    super.key,
    required this.link,
    required this.onLabel,
    required this.onChanged,
    required this.onDelete,
  });

  final CanvasLink link;
  final VoidCallback onLabel;
  final ValueChanged<CanvasLink> onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final nextStyle =
        LinkStyle.values[(link.style.index + 1) % LinkStyle.values.length];
    final nextArrow =
        LinkArrow.values[(link.arrow.index + 1) % LinkArrow.values.length];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: KraftColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(KraftRadius.lg),
        border: KraftBorder.ink(),
        boxShadow: KraftShadow.hard(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: KraftColors.primaryContainer,
              borderRadius: BorderRadius.circular(KraftRadius.sm),
            ),
            child: Text(
              'CONEXIÓN',
              style: KraftText.techBadge.copyWith(
                color: KraftColors.onPrimaryContainer,
              ),
            ),
          ),
          _ToolbarButton(
            icon: Symbols.label,
            tooltip: 'Etiqueta de la conexión',
            onTap: onLabel,
          ),
          _ToolbarButton(
            icon: link.style == LinkStyle.curved
                ? Symbols.gesture
                : Symbols.trending_flat,
            tooltip: 'Trazado: ${nextStyle.label}',
            onTap: () => onChanged(link.copyWith(style: nextStyle)),
          ),
          _ToolbarButton(
            icon: switch (link.arrow) {
              LinkArrow.end => Symbols.arrow_right_alt,
              LinkArrow.both => Symbols.sync_alt,
              LinkArrow.none => Symbols.horizontal_rule,
            },
            tooltip: 'Puntas: ${nextArrow.label}',
            onTap: () => onChanged(link.copyWith(arrow: nextArrow)),
          ),
          _ToolbarButton(
            icon: Symbols.swap_horiz,
            tooltip: 'Invertir dirección',
            onTap: () => onChanged(link.copyWith(from: link.to, to: link.from)),
          ),
          Container(
            width: 1,
            height: 24,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: KraftColors.outlineVariant,
          ),
          _ToolbarButton(
            icon: Symbols.delete,
            tooltip: 'Borrar conexión',
            onTap: onDelete,
            danger: true,
          ),
        ],
      ),
    );
  }
}

/// Tirador redondo junto al elemento seleccionado: se arrastra hasta otro elemento para conectarlos,
/// o se toca y luego se toca el destino.
class ConnectorKnob extends StatelessWidget {
  const ConnectorKnob({
    super.key,
    required this.active,
    required this.onTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
  });

  static const size = 40.0;

  /// Esperando a que se toque el destino.
  final bool active;
  final VoidCallback onTap;
  final ValueChanged<Offset> onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onDragCancel;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Tooltip(
      message: 'Conectar con otro elemento',
      child: Semantics(
        button: true,
        label: 'Conectar',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onTap: onTap,
          onPanStart: (d) => onDragStart(d.globalPosition),
          onPanUpdate: (d) => onDragUpdate(d.globalPosition),
          onPanEnd: (_) => onDragEnd(),
          onPanCancel: onDragCancel,
          child: AnimatedContainer(
            duration: KraftMotion.of(context, KraftMotion.fast),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: active ? KraftColors.ink : KraftColors.primaryContainer,
              shape: BoxShape.circle,
              border: KraftBorder.ink(),
              boxShadow: KraftShadow.hard(2),
            ),
            child: Icon(
              Symbols.arrow_right_alt,
              size: 22,
              color: active ? KraftColors.primaryContainer : KraftColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.tooltip,
    required this.onTap,
    this.icon,
    this.child,
    this.danger = false,
  });

  final String tooltip;
  final VoidCallback onTap;
  final IconData? icon;
  final Widget? child;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 40,
          child: Center(
            child:
                child ??
                Icon(
                  icon,
                  size: 20,
                  color: danger ? KraftColors.error : KraftColors.onSurface,
                ),
          ),
        ),
      ),
    );
  }
}

/// Aparece con un "pop" cada vez que cambia la selección.
class SelectionPop extends StatelessWidget {
  const SelectionPop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: KraftMotion.of(context, KraftMotion.base),
      curve: KraftMotion.pop,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.9 + 0.1 * t,
          alignment: Alignment.bottomCenter,
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Informa del tamaño real de su hijo después de cada maquetación.
class SizeReporter extends SingleChildRenderObjectWidget {
  const SizeReporter({super.key, required this.onSize, super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderSizeReporter(onSize);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSizeReporter renderObject,
  ) => renderObject.onSize = onSize;
}

class RenderSizeReporter extends RenderProxyBox {
  RenderSizeReporter(this.onSize);

  ValueChanged<Size> onSize;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    if (size != _reported) {
      _reported = size;
      final reported = size;
      // Fuera de la fase de layout: notificar cambios aquí dispararía una reconstrucción ilegal.
      WidgetsBinding.instance.addPostFrameCallback((_) => onSize(reported));
    }
  }
}
