import 'package:flutter/widgets.dart';

/// Movimiento neobrutalista: rápido, con un muelle corto y sin fundidos largos.
abstract final class KraftMotion {
  static const press = Duration(milliseconds: 90);
  static const fast = Duration(milliseconds: 140);
  static const base = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 260);

  /// Retraso entre elementos de una entrada escalonada, y su tope.
  static const stagger = Duration(milliseconds: 35);
  static const maxStagger = Duration(milliseconds: 280);

  /// Llega con un rebote leve (~6 %).
  static const Curve pop = Cubic(0.34, 1.36, 0.64, 1);

  /// Frena en seco, sin rebote.
  static const Curve settle = Curves.easeOutCubic;

  /// Respeta "Reducir movimiento" del sistema.
  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static Duration of(BuildContext context, Duration duration) => reduced(context) ? Duration.zero : duration;
}
