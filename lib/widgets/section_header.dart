import 'package:flutter/material.dart';

import '../theme/kraft_colors.dart';
import '../theme/kraft_tokens.dart';
import '../theme/kraft_typography.dart';

/// Cabecera de sección: icono (o marcador de color) + título en mayúsculas + acción.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.iconColor,
    this.marker,
    this.trailing,
  });

  final String title;
  final IconData? icon;
  final Color? iconColor;

  /// Cuadrado de color con sombra dura, usado en la biblioteca.
  final Color? marker;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 22, color: iconColor ?? KraftColors.primary),
          const SizedBox(width: KraftSpace.xs + 2),
        ],
        if (marker != null) ...[
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: marker,
              borderRadius: BorderRadius.circular(KraftRadius.sm),
              boxShadow: KraftShadow.hard(1),
            ),
          ),
          const SizedBox(width: KraftSpace.sm),
        ],
        Expanded(
          child: Text(
            title.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style: KraftText.headlineSm.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}
