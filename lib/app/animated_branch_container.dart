import 'package:flutter/material.dart';

import '../theme/kraft_motion.dart';

/// Contenedor de pestañas: la pestaña entrante sube 12 px y aparece en 200 ms.
/// Las inactivas quedan fuera de escena (sin pintar ni animar) una vez ocultas.
class AnimatedBranchContainer extends StatelessWidget {
  const AnimatedBranchContainer({
    super.key,
    required this.currentIndex,
    required this.children,
  });

  final int currentIndex;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (final (i, child) in children.indexed)
          _Branch(active: i == currentIndex, child: child),
      ],
    );
  }
}

class _Branch extends StatefulWidget {
  const _Branch({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_Branch> createState() => _BranchState();
}

class _BranchState extends State<_Branch> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: KraftMotion.base,
    value: widget.active ? 1 : 0,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: KraftMotion.pop,
  );

  @override
  void didUpdateWidget(_Branch old) {
    super.didUpdateWidget(old);
    if (widget.active == old.active) return;
    if (widget.active) {
      _controller.value = 0;
      if (KraftMotion.reduced(context)) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    } else {
      // Sale sin animación: la entrante tapa la transición.
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: ExcludeFocus(
        excluding: !widget.active,
        child: Material(
          type: MaterialType.transparency,
          clipBehavior: Clip.hardEdge,
          child: widget.child,
        ),
      ),
      builder: (context, child) {
        final t = _controller.value;
        final hidden = !widget.active && t == 0;
        return Offstage(
          offstage: hidden,
          child: TickerMode(
            enabled: widget.active,
            child: IgnorePointer(
              ignoring: !widget.active,
              child: Opacity(
                opacity: Curves.easeOut.transform(t.clamp(0.0, 1.0)),
                child: Transform.translate(
                  offset: Offset(0, 12 * (1 - _curve.value)),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
