import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../theme/kraft_colors.dart';
import '../../theme/kraft_motion.dart';
import '../../theme/kraft_typography.dart';
import 'element_catalog.dart';

class RadialOption {
  const RadialOption(this.label, this.icon, this.template);

  final String label;
  final IconData icon;
  final ElementTemplate template;
}

/// Opciones de la rueda, en sentido horario desde arriba.
final radialOptions = [
  RadialOption('Nota', Symbols.sticky_note_2, templateNamed('Nota amarillo')),
  RadialOption('Texto', Symbols.title, templateNamed('Subtítulo')),
  RadialOption('Tarjeta', Symbols.style, templateNamed('Tarjeta')),
  RadialOption('Rectángulo', Symbols.rectangle, templateNamed('Rectángulo')),
  RadialOption('Círculo', Symbols.circle, templateNamed('Círculo')),
  RadialOption('Rombo', Symbols.shapes, templateNamed('Rombo')),
  RadialOption('Flecha', Symbols.arrow_right_alt, templateNamed('Flecha')),
  RadialOption('Estrella', Symbols.star, templateNamed('Estrella')),
];

/// Estado de la rueda abierta: centro en pantalla, punto del lienzo donde se colocará y opción resaltada.
@immutable
class RadialMenuState {
  const RadialMenuState({
    required this.center,
    required this.world,
    this.hovered,
    this.held = true,
  });

  final Offset center;
  final Offset world;
  final int? hovered;

  /// El lápiz sigue apoyado: soltar elige la opción resaltada.
  final bool held;

  RadialMenuState copyWith({
    int? hovered,
    bool clearHovered = false,
    bool? held,
  }) => RadialMenuState(
    center: center,
    world: world,
    hovered: clearHovered ? null : (hovered ?? this.hovered),
    held: held ?? this.held,
  );
}

/// Rueda de selección rápida estilo "arma" en mini: aparece girando desde el lápiz,
/// resalta la porción hacia la que apuntas y la etiqueta se muestra en el centro.
class RadialMenu extends StatefulWidget {
  const RadialMenu({
    super.key,
    required this.state,
    required this.onSelect,
    required this.onDismiss,
  });

  final RadialMenuState state;
  final ValueChanged<int> onSelect;
  final VoidCallback onDismiss;

  static const outerRadius = 104.0;
  static const innerRadius = 38.0;

  /// Porción bajo [point] o `null` si está en el centro (zona muerta).
  static int? indexAt(Offset center, Offset point, [int? count]) {
    final n = count ?? radialOptions.length;
    final d = point - center;
    if (d.distance < innerRadius) return null;
    // 0 rad arriba, creciendo en sentido horario.
    var angle = math.atan2(d.dx, -d.dy);
    if (angle < 0) angle += 2 * math.pi;
    final segment = 2 * math.pi / n;
    return ((angle + segment / 2) / segment).floor() % n;
  }

  /// Mantiene la rueda completa dentro del visor.
  static Offset clampCenter(Offset center, Size viewport) {
    const margin = outerRadius + 12;
    return Offset(
      center.dx.clamp(margin, math.max(margin, viewport.width - margin)),
      center.dy.clamp(margin, math.max(margin, viewport.height - margin)),
    );
  }

  @override
  State<RadialMenu> createState() => _RadialMenuState();
}

class _RadialMenuState extends State<RadialMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_open.status == AnimationStatus.dismissed) {
      KraftMotion.reduced(context) ? _open.value = 1 : _open.forward();
    }
  }

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final s = widget.state;
    const r = RadialMenu.outerRadius + 12;
    final hovered = s.hovered;

    return Stack(
      children: [
        // Con el lápiz ya levantado, tocar fuera cierra la rueda.
        if (!s.held)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onDismiss,
            ),
          ),
        Positioned(
          left: s.center.dx - r,
          top: s.center.dy - r,
          width: r * 2,
          height: r * 2,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              final i = RadialMenu.indexAt(const Offset(r, r), d.localPosition);
              i == null ? widget.onDismiss() : widget.onSelect(i);
            },
            child: AnimatedBuilder(
              animation: _open,
              builder: (context, _) {
                final t = _open.value;
                final pop = KraftMotion.pop.transform(t);
                return Opacity(
                  opacity: Curves.easeOut.transform(math.min(1, t * 2)),
                  child: Transform.rotate(
                    // Entra girando un cuarto de vuelta, como una ruleta que se asienta.
                    angle: -0.6 * (1 - Curves.easeOutCubic.transform(t)),
                    child: Transform.scale(
                      scale: 0.35 + 0.65 * pop,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _RingPainter(
                                count: radialOptions.length,
                                hovered: hovered,
                                progress: t,
                              ),
                            ),
                          ),
                          for (final (i, option) in radialOptions.indexed)
                            _SegmentIcon(
                              index: i,
                              count: radialOptions.length,
                              icon: option.icon,
                              highlighted: i == hovered,
                              progress: t,
                              center: const Offset(r, r),
                            ),
                          Center(
                            child: _CenterLabel(
                              label: hovered == null
                                  ? 'AÑADIR'
                                  : radialOptions[hovered].label.toUpperCase(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.count,
    required this.hovered,
    required this.progress,
  });

  final int count;
  final int? hovered;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final segment = 2 * math.pi / count;
    const gap = 0.05;

    for (var i = 0; i < count; i++) {
      // Aparición escalonada de cada porción.
      final local = ((progress - i * 0.05) / 0.6).clamp(0.0, 1.0);
      if (local == 0) continue;
      final isHovered = i == hovered;
      final outer = RadialMenu.outerRadius + (isHovered ? 10 : 0);
      const inner = RadialMenu.innerRadius + 4.0;
      // El ángulo 0 de Canvas apunta a la derecha: se corrige para empezar arriba.
      final start = -math.pi / 2 + i * segment - segment / 2 + gap / 2;
      final sweep = (segment - gap) * local;
      final path = Path()
        ..arcTo(Rect.fromCircle(center: c, radius: outer), start, sweep, true)
        ..arcTo(
          Rect.fromCircle(center: c, radius: inner),
          start + sweep,
          -sweep,
          false,
        )
        ..close();

      if (isHovered) {
        canvas.drawPath(
          path.shift(const Offset(3, 3)),
          Paint()..color = KraftColors.ink,
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = isHovered
              ? KraftColors.primaryContainer
              : KraftColors.scrim,
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = isHovered
              ? KraftColors.ink
              : KraftColors.primaryContainer.withValues(alpha: 0.35),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.hovered != hovered || old.progress != progress || old.count != count;
}

class _SegmentIcon extends StatelessWidget {
  const _SegmentIcon({
    required this.index,
    required this.count,
    required this.icon,
    required this.highlighted,
    required this.progress,
    required this.center,
  });

  final int index;
  final int count;
  final IconData icon;
  final bool highlighted;
  final double progress;
  final Offset center;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final angle = index * 2 * math.pi / count;
    final radius =
        (RadialMenu.outerRadius + RadialMenu.innerRadius) / 2 +
        (highlighted ? 6 : 0);
    final pos = center + Offset(math.sin(angle), -math.cos(angle)) * radius;
    final local = ((progress - index * 0.05 - 0.15) / 0.5).clamp(0.0, 1.0);
    return Positioned(
      left: pos.dx - 16,
      top: pos.dy - 16,
      width: 32,
      height: 32,
      child: Opacity(
        opacity: local,
        child: Transform.scale(
          scale: (highlighted ? 1.25 : 1) * (0.6 + 0.4 * local),
          child: Icon(
            icon,
            size: 22,
            color: highlighted ? KraftColors.ink : Colors.white,
          ),
        ),
      ),
    );
  }
}

class _CenterLabel extends StatelessWidget {
  const _CenterLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Container(
      width: RadialMenu.innerRadius * 2 - 4,
      height: RadialMenu.innerRadius * 2 - 4,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: KraftColors.surfaceContainerLowest,
        shape: BoxShape.circle,
        border: Border.all(color: KraftColors.ink, width: 2),
      ),
      padding: const EdgeInsets.all(4),
      child: FittedBox(
        child: Text(label, style: KraftText.techBadge.copyWith(fontSize: 10)),
      ),
    );
  }
}
