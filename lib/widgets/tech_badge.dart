import 'package:flutter/material.dart';

import '../theme/kraft_colors.dart';
import '../theme/kraft_tokens.dart';
import '../theme/kraft_typography.dart';

/// Etiqueta monoespaciada tipo `LIENZO`, `URGENTE` o `#SISTEMA`.
class TechBadge extends StatelessWidget {
  const TechBadge(
    this.label, {
    super.key,
    this.background,
    this.foreground,
    this.leadingDot,
    this.fontSize,
  });

  final String label;
  final Color? background;
  final Color? foreground;
  final Color? leadingDot;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: KraftSpace.xs + 1, vertical: 2),
      decoration: BoxDecoration(
        color: background ?? KraftColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(KraftRadius.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leadingDot != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: leadingDot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: KraftText.techBadge.copyWith(color: foreground ?? KraftColors.onColor(background ?? KraftColors.surfaceContainerHigh), fontSize: fontSize),
            ),
          ),
        ],
      ),
    );
  }
}
