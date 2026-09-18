import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import '../theme/kraft_colors.dart';
import '../theme/kraft_motion.dart';
import '../theme/kraft_tokens.dart';

/// Contenedor neobrutalista: borde de tinta opcional + sombra dura desplazada.
/// Si tiene [onTap], al presionar se desplaza hacia la sombra y esta desaparece.
class NeoBox extends StatefulWidget {
  const NeoBox({
    super.key,
    required this.child,
    this.color,
    this.borderWidth = 0,
    this.borderColor,
    this.shadow = 3,
    this.radius = KraftRadius.lg,
    this.padding = EdgeInsets.zero,
    this.onTap,
    this.clip = false,
  });

  final Widget child;

  /// Relleno; por defecto, el de las tarjetas de la paleta activa.
  final Color? color;
  final double borderWidth;
  final Color? borderColor;
  final double shadow;
  final double radius;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool clip;

  @override
  State<NeoBox> createState() => _NeoBoxState();
}

class _NeoBoxState extends State<NeoBox> {
  bool _pressed = false;
  bool _focusVisible = false;

  void _setPressed(bool value) {
    if (widget.onTap != null && _pressed != value) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final offset = _pressed ? widget.shadow : 0.0;
    final box = AnimatedContainer(
      duration: KraftMotion.of(context, KraftMotion.press),
      transform: Matrix4.translationValues(offset, offset, 0),
      padding: widget.padding,
      clipBehavior: widget.clip ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: widget.color ?? KraftColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(widget.radius),
        border: _focusVisible
            ? Border.all(color: KraftColors.primary, width: 3)
            : widget.borderWidth > 0
            ? Border.all(
                color: widget.borderColor ?? KraftColors.ink,
                width: widget.borderWidth,
              )
            : null,
        boxShadow: _pressed || widget.shadow == 0
            ? null
            : KraftShadow.hard(widget.shadow),
      ),
      child: widget.child,
    );

    if (widget.onTap == null) {
      return box;
    }
    return Semantics(
      button: true,
      child: FocusableActionDetector(
        onShowFocusHighlight: (visible) =>
            setState(() => _focusVisible = visible),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          child: box,
        ),
      ),
    );
  }
}
