import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/kraft_colors.dart';
import '../theme/kraft_motion.dart';
import '../theme/kraft_tokens.dart';

/// Casilla con "pop" al marcarse.
class NeoCheckbox extends StatelessWidget {
  const NeoCheckbox({
    super.key,
    required this.checked,
    required this.onChanged,
    this.size = 24,
    this.fill,
    this.checkColor = Colors.white,
    this.bordered = true,
    this.semanticLabel,
  });

  final bool checked;
  final ValueChanged<bool> onChanged;
  final double size;
  final Color? fill;
  final Color checkColor;
  final bool bordered;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Semantics(
      checked: checked,
      label: semanticLabel,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!checked),
        child: Padding(
          // Área táctil mínima de 44 pt sin agrandar la casilla.
          padding: EdgeInsets.all((44 - size).clamp(0, 20) / 2),
          child: AnimatedContainer(
            duration: KraftMotion.of(context, KraftMotion.fast),
            curve: KraftMotion.settle,
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: checked
                  ? (fill ?? KraftColors.secondary)
                  : KraftColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(KraftRadius.sm),
              border: bordered
                  ? Border.all(
                      color: checked
                          ? (fill ?? KraftColors.secondary)
                          : KraftColors.border,
                      width: 1.5,
                    )
                  : null,
            ),
            child: AnimatedSwitcher(
              duration: KraftMotion.of(context, KraftMotion.base),
              switchInCurve: KraftMotion.pop,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: checked
                  ? Icon(
                      Symbols.check,
                      key: const ValueKey(true),
                      size: size * 0.8,
                      weight: 700,
                      color: checkColor,
                    )
                  : const SizedBox.shrink(key: ValueKey(false)),
            ),
          ),
        ),
      ),
    );
  }
}
