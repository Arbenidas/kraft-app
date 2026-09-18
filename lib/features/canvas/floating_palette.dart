import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/kraft_colors.dart';
import '../../theme/kraft_motion.dart';
import '../../theme/kraft_tokens.dart';
import 'canvas_selection.dart' show SizeReporter;

enum PaletteDock {
  topLeft(Alignment.topLeft),
  centerLeft(Alignment.centerLeft),
  bottomLeft(Alignment.bottomLeft),
  bottomCenter(Alignment.bottomCenter),
  topRight(Alignment.topRight),
  centerRight(Alignment.centerRight),
  bottomRight(Alignment.bottomRight);

  const PaletteDock(this.alignment);
  final Alignment alignment;

  bool get isLeft => alignment.x < 0;
  bool get isRight => alignment.x > 0;

  /// En un lado la paleta se pone en vertical para no tapar el lienzo.
  bool get isVertical => this != bottomCenter;
}

/// Paleta que se encoge en una burbuja arrastrable. Al soltar la burbuja se ancla
/// en la esquina más cercana; al tocarla, la paleta se despliega desde esa esquina.
class FloatingPalette extends StatefulWidget {
  const FloatingPalette({
    super.key,
    required this.collapsed,
    required this.dock,
    required this.insets,
    required this.onExpand,
    required this.onDockChanged,
    required this.palette,
    required this.bubble,
    this.onPaletteSize,
  });

  final bool collapsed;
  final PaletteDock dock;

  /// Márgenes libres por borde (la parte superior deja sitio a la barra de estado y al minimapa).
  final EdgeInsets insets;
  final VoidCallback onExpand;
  final ValueChanged<PaletteDock> onDockChanged;
  final Widget palette;
  final Widget bubble;

  /// Tamaño visible de la paleta desplegada (para colocar la galería a su lado).
  final ValueChanged<Size>? onPaletteSize;

  static const bubbleSize = 64.0;

  @override
  State<FloatingPalette> createState() => _FloatingPaletteState();
}

class _FloatingPaletteState extends State<FloatingPalette> {
  /// Posición libre mientras se arrastra la burbuja; `null` = anclada.
  Offset? _drag;

  Offset _dockPosition(PaletteDock dock, Size area) {
    const s = FloatingPalette.bubbleSize;
    final i = widget.insets;
    return switch (dock) {
      PaletteDock.topLeft => Offset(i.left, i.top),
      PaletteDock.centerLeft => Offset(i.left, (area.height - s) / 2),
      PaletteDock.bottomLeft => Offset(i.left, area.height - i.bottom - s),
      PaletteDock.bottomCenter => Offset((area.width - s) / 2, area.height - i.bottom - s),
      PaletteDock.topRight => Offset(area.width - i.right - s, i.top),
      PaletteDock.centerRight => Offset(area.width - i.right - s, (area.height - s) / 2),
      PaletteDock.bottomRight => Offset(area.width - i.right - s, area.height - i.bottom - s),
    };
  }

  PaletteDock _nearestDock(Offset position, Size area) {
    final center = position + const Offset(FloatingPalette.bubbleSize / 2, FloatingPalette.bubbleSize / 2);
    return PaletteDock.values.reduce((best, dock) {
      final a = (_dockPosition(best, area) - center).distanceSquared;
      final b = (_dockPosition(dock, area) - center).distanceSquared;
      return b < a ? dock : best;
    });
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = constraints.biggest;
        final collapsed = widget.collapsed;
        final dock = widget.dock;
        final bubblePos = _drag ?? _dockPosition(dock, area);
        final i = widget.insets;

        return Stack(
          children: [
            // Paleta desplegada: se encoge hacia su esquina al hacerse burbuja.
            Positioned(
              left: i.left,
              right: i.right,
              top: i.top,
              bottom: i.bottom,
              child: IgnorePointer(
                ignoring: collapsed,
                child: Align(
                  alignment: dock.alignment,
                  child: AnimatedScale(
                    scale: collapsed ? 0.15 : 1,
                    alignment: dock.alignment,
                    duration: KraftMotion.of(context, collapsed ? KraftMotion.base : KraftMotion.slow),
                    curve: collapsed ? Curves.easeInCubic : KraftMotion.pop,
                    child: AnimatedOpacity(
                      opacity: collapsed ? 0 : 1,
                      duration: KraftMotion.of(context, KraftMotion.fast),
                      child: SizeReporter(
                        onSize: (size) => widget.onPaletteSize?.call(size),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: math.max(0, area.width - i.horizontal),
                            maxHeight: math.max(0, area.height - i.vertical),
                          ),
                          child: FittedBox(fit: BoxFit.scaleDown, child: widget.palette),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Burbuja.
            AnimatedPositioned(
              duration: _drag != null ? Duration.zero : KraftMotion.of(context, KraftMotion.slow),
              curve: Curves.easeOutBack,
              left: bubblePos.dx,
              top: bubblePos.dy,
              width: FloatingPalette.bubbleSize,
              height: FloatingPalette.bubbleSize,
              child: IgnorePointer(
                ignoring: !collapsed,
                child: AnimatedScale(
                  scale: collapsed ? (_drag != null ? 1.08 : 1) : 0,
                  duration: KraftMotion.of(context, collapsed ? KraftMotion.slow : KraftMotion.fast),
                  curve: collapsed ? KraftMotion.pop : Curves.easeIn,
                  child: Semantics(
                    button: true,
                    label: 'Mostrar herramientas',
                    child: GestureDetector(
                      onTap: widget.onExpand,
                      onPanStart: (d) => setState(() => _drag = bubblePos),
                      onPanUpdate: (d) => setState(() {
                        final next = (_drag ?? bubblePos) + d.delta;
                        _drag = Offset(
                          next.dx.clamp(0, math.max(0, area.width - FloatingPalette.bubbleSize)),
                          next.dy.clamp(0, math.max(0, area.height - FloatingPalette.bubbleSize)),
                        );
                      }),
                      onPanEnd: (_) {
                        final target = _nearestDock(_drag ?? bubblePos, area);
                        setState(() => _drag = null);
                        widget.onDockChanged(target);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: KraftColors.surfaceContainerLowest,
                          shape: BoxShape.circle,
                          border: KraftBorder.ink(),
                          boxShadow: KraftShadow.hard(3),
                        ),
                        child: Center(child: widget.bubble),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
