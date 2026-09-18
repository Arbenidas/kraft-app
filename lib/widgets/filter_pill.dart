import 'package:flutter/material.dart';

import '../theme/kraft_colors.dart';
import '../theme/kraft_tokens.dart';
import '../theme/kraft_typography.dart';
import 'neo_box.dart';

/// Píldora de filtro con sombra dura; amarilla cuando está seleccionada.
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.muted = false,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool selected;

  /// Variante secundaria sin sombra (p. ej. "+ Etiqueta").
  final bool muted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final fg = selected ? KraftColors.onPrimaryContainer : muted ? KraftColors.onSurfaceVariant : KraftColors.onSurface;
    return NeoBox(
      onTap: onTap ?? () {},
      color: selected
          ? KraftColors.primaryContainer
          : muted
              ? KraftColors.surfaceContainer
              : KraftColors.surfaceContainerLowest,
      shadow: muted ? 0 : 2,
      radius: KraftRadius.sm,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: KraftText.labelCode.copyWith(
              color: fg,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
