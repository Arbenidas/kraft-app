import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../theme/kraft_colors.dart';
import '../../theme/kraft_motion.dart';
import '../../theme/kraft_tokens.dart';
import '../../theme/kraft_typography.dart';
import 'canvas_document.dart';
import 'canvas_items.dart';
import 'canvas_models.dart';

/// Proyección entre el lienzo y el minimapa.
@immutable
class MinimapProjection {
  const MinimapProjection._(this.region, this.scale, this.origin);

  /// Encuadra el contenido (con margen) y la zona visible dentro de [mapSize].
  factory MinimapProjection.of({
    required CanvasDocument document,
    required Matrix4 view,
    required Size viewportSize,
    required Size mapSize,
  }) {
    final visible = MinimapProjection.visibleWorld(view, viewportSize);
    final content = document.contentBounds;
    var region = (content ?? visible)
        .inflate(320)
        .expandToInclude(visible)
        .inflate(40);
    if (region.isEmpty)
      region = Rect.fromCenter(center: region.center, width: 1000, height: 700);
    final scale = math.min(
      mapSize.width / region.width,
      mapSize.height / region.height,
    );
    // Centra la región en el mapa.
    final origin = Offset(
      (mapSize.width - region.width * scale) / 2 - region.left * scale,
      (mapSize.height - region.height * scale) / 2 - region.top * scale,
    );
    return MinimapProjection._(region, scale, origin);
  }

  final Rect region;
  final double scale;
  final Offset origin;

  Offset toMap(Offset world) => world * scale + origin;
  Rect rectToMap(Rect world) =>
      Rect.fromPoints(toMap(world.topLeft), toMap(world.bottomRight));
  Offset toWorld(Offset map) => (map - origin) / scale;

  static Rect visibleWorld(Matrix4 view, Size viewportSize) =>
      MatrixUtils.transformRect(
        Matrix4.inverted(view),
        Offset.zero & viewportSize,
      );
}

/// Minimapa plegable: muestra el contenido y la zona visible; tocar o arrastrar mueve la vista.
class CanvasMinimap extends StatefulWidget {
  const CanvasMinimap({
    super.key,
    required this.document,
    required this.viewer,
    required this.viewportSize,
    required this.expanded,
    required this.onExpandedChanged,
    required this.onJump,
    required this.onDrag,
  });

  static const mapSize = Size(212, 132);

  final CanvasDocument document;
  final TransformationController viewer;
  final Size viewportSize;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;

  /// Toque: centrar la vista en ese punto del lienzo con animación.
  final ValueChanged<Offset> onJump;

  /// Arrastre: centrar la vista en ese punto al instante.
  final ValueChanged<Offset> onDrag;

  @override
  State<CanvasMinimap> createState() => _CanvasMinimapState();
}

class _CanvasMinimapState extends State<CanvasMinimap> {
  /// Proyección congelada durante el arrastre: si se recalculara, el mapa cambiaría de escala bajo el dedo.
  MinimapProjection? _dragProjection;

  MinimapProjection _projection() => MinimapProjection.of(
    document: widget.document,
    view: widget.viewer.value,
    viewportSize: widget.viewportSize,
    mapSize: CanvasMinimap.mapSize,
  );

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return AnimatedSize(
      duration: KraftMotion.of(context, KraftMotion.base),
      curve: KraftMotion.settle,
      alignment: Alignment.topRight,
      child: Container(
        decoration: BoxDecoration(
          color: KraftColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(KraftRadius.lg),
          border: KraftBorder.ink(),
          boxShadow: KraftShadow.hard(3),
        ),
        clipBehavior: Clip.antiAlias,
        child: widget.expanded ? _expanded() : _collapsed(),
      ),
    );
  }

  Widget _collapsed() {
    return Tooltip(
      message: 'Mostrar minimapa',
      child: GestureDetector(
        onTap: () => widget.onExpandedChanged(true),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Symbols.map, size: 18),
              const SizedBox(width: 6),
              Text('MAPA', style: KraftText.techBadge),
            ],
          ),
        ),
      ),
    );
  }

  Widget _expanded() {
    return SizedBox(
      width: CanvasMinimap.mapSize.width,
      child: _expandedContent(),
    );
  }

  Widget _expandedContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: KraftColors.ink, width: 2),
            ),
          ),
          child: Row(
            children: [
              const Icon(Symbols.map, size: 16),
              const SizedBox(width: 6),
              Text('MAPA', style: KraftText.techBadge),
              const SizedBox(width: 8),
              Expanded(
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    widget.document,
                    widget.viewer,
                  ]),
                  builder: (context, _) {
                    final center = MinimapProjection.visibleWorld(
                      widget.viewer.value,
                      widget.viewportSize,
                    ).center;
                    return Text(
                      'X ${center.dx.round()}  Y ${center.dy.round()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: KraftText.techBadge.copyWith(
                        fontWeight: FontWeight.w400,
                        color: KraftColors.onSurfaceVariant,
                      ),
                    );
                  },
                ),
              ),
              IconButton(
                tooltip: 'Ocultar minimapa',
                visualDensity: VisualDensity.compact,
                onPressed: () => widget.onExpandedChanged(false),
                icon: const Icon(Symbols.close_fullscreen, size: 16),
              ),
            ],
          ),
        ),
        Semantics(
          label: 'Minimapa del lienzo',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) =>
                widget.onJump(_projection().toWorld(d.localPosition)),
            onPanStart: (d) {
              _dragProjection = _projection();
              widget.onDrag(_dragProjection!.toWorld(d.localPosition));
            },
            onPanUpdate: (d) => widget.onDrag(
              (_dragProjection ?? _projection()).toWorld(d.localPosition),
            ),
            onPanEnd: (_) => _dragProjection = null,
            onPanCancel: () => _dragProjection = null,
            child: CustomPaint(
              size: CanvasMinimap.mapSize,
              painter: _MinimapPainter(
                document: widget.document,
                viewer: widget.viewer,
                viewportSize: widget.viewportSize,
                frozen: () => _dragProjection,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter({
    required this.document,
    required this.viewer,
    required this.viewportSize,
    required this.frozen,
  }) : super(repaint: Listenable.merge([document, viewer]));

  final CanvasDocument document;
  final TransformationController viewer;
  final Size viewportSize;
  final MinimapProjection? Function() frozen;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = KraftColors.surfaceContainerLow,
    );
    if (viewportSize.isEmpty) return;

    final p =
        frozen() ??
        MinimapProjection.of(
          document: document,
          view: viewer.value,
          viewportSize: viewportSize,
          mapSize: size,
        );

    // Trama de fondo: una cruz cada ~400 pt de lienzo para dar referencia de escala.
    final grid = Paint()
      ..color = KraftColors.outlineVariant.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    const cell = 400.0;
    for (
      var x = (p.region.left / cell).floor() * cell;
      x <= p.region.right;
      x += cell
    ) {
      final mx = p.toMap(Offset(x, 0)).dx;
      canvas.drawLine(Offset(mx, 0), Offset(mx, size.height), grid);
    }
    for (
      var y = (p.region.top / cell).floor() * cell;
      y <= p.region.bottom;
      y += cell
    ) {
      final my = p.toMap(Offset(0, y)).dy;
      canvas.drawLine(Offset(0, my), Offset(size.width, my), grid);
    }

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..color = KraftColors.ink
      ..strokeWidth = 1;
    for (final item in document.items) {
      final r = p.rectToMap(document.itemRect(item));
      final fill = item.type == CanvasItemType.node && item.active
          ? KraftColors.primaryContainer
          : canvasItemColor(item);
      canvas
        ..drawRect(r, Paint()..color = fill)
        ..drawRect(r, border);
    }

    for (final stroke in document.strokes) {
      final pts = stroke.points;
      if (pts.isEmpty) continue;
      final step = math.max(1, pts.length ~/ 24);
      final path = Path()..moveTo(p.toMap(pts.first).dx, p.toMap(pts.first).dy);
      for (var i = step; i < pts.length; i += step) {
        final m = p.toMap(pts[i]);
        path.lineTo(m.dx, m.dy);
      }
      final last = p.toMap(pts.last);
      path.lineTo(last.dx, last.dy);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = stroke.highlighter
              ? stroke.color.withValues(alpha: 0.5)
              : stroke.color
          ..strokeWidth = math.max(1, stroke.paintedWidth * p.scale)
          ..strokeCap = StrokeCap.round,
      );
    }

    final visible = p.rectToMap(
      MinimapProjection.visibleWorld(viewer.value, viewportSize),
    );
    canvas
      ..drawRect(
        visible,
        Paint()..color = KraftColors.primaryContainer.withValues(alpha: 0.28),
      )
      ..drawRect(
        visible,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = KraftColors.ink
          ..strokeWidth = 2,
      );
  }

  @override
  bool shouldRepaint(_MinimapPainter old) =>
      old.document != document ||
      old.viewer != viewer ||
      old.viewportSize != viewportSize;
}
