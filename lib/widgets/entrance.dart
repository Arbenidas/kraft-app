import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/kraft_motion.dart';

/// Hace entrar a su hijo una sola vez al montarse: sube unos píxeles con rebote corto.
/// [index] escalona varios elementos de una misma lista.
class Entrance extends StatefulWidget {
  const Entrance({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = const Offset(0, 14),
    this.scale = 1,
  });

  final Widget child;
  final int index;
  final Offset offset;

  /// Escala inicial (p. ej. 0.9 para elementos que "caen" en el lienzo).
  final double scale;

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _move;
  late final Animation<double> _fade;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final delayMs = math.min(
      widget.index * KraftMotion.stagger.inMilliseconds,
      KraftMotion.maxStagger.inMilliseconds,
    );
    final totalMs = KraftMotion.slow.inMilliseconds + delayMs;
    // El retraso vive dentro del propio controlador (sin Timer): nada queda colgando al desmontar.
    final start = delayMs / totalMs;
    _controller = AnimationController(vsync: this, duration: Duration(milliseconds: totalMs));
    _move = CurvedAnimation(parent: _controller, curve: Interval(start, 1, curve: KraftMotion.pop));
    _fade = CurvedAnimation(parent: _controller, curve: Interval(start, start + (1 - start) / 2, curve: Curves.easeOut));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (KraftMotion.reduced(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
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
      child: widget.child,
      builder: (context, child) {
        if (_controller.isCompleted) return child!;
        final t = _move.value;
        return Opacity(
          opacity: _fade.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: widget.offset * (1 - t),
            child: widget.scale == 1 ? child : Transform.scale(scale: widget.scale + (1 - widget.scale) * t, child: child),
          ),
        );
      },
    );
  }
}
