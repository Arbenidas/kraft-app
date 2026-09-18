import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/kraft_colors.dart';
import '../theme/kraft_tokens.dart';
import '../theme/kraft_typography.dart';
import 'tech_badge.dart';

/// Barra superior translúcida común. [leading] ocupa la izquierda y
/// [actions] la derecha; usa [KraftBrand] para el logotipo.
class KraftTopBar extends StatelessWidget {
  const KraftTopBar({
    super.key,
    required this.leading,
    this.actions = const [],
  });

  final Widget leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Container(
      decoration: BoxDecoration(
        color: KraftColors.glass,
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: KraftSpace.md),
            child: Row(
              children: [
                Expanded(child: leading),
                const SizedBox(width: KraftSpace.sm),
                for (final (i, action) in actions.indexed) ...[
                  if (i > 0) const SizedBox(width: KraftSpace.sm),
                  action,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Logotipo KRAFT con insignia y subtítulo o migas de pan opcionales.
class KraftBrand extends StatelessWidget {
  const KraftBrand({
    super.key,
    this.badge = 'v2.4',
    this.badgeHighlighted = false,
    this.subtitle,
    this.breadcrumb,
    this.showLogo = true,
  });

  final String badge;
  final bool badgeHighlighted;
  final String? subtitle;
  final String? breadcrumb;
  final bool showLogo;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Row(
      children: [
        if (showLogo) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(KraftRadius.md),
            child: Image.asset('assets/images/logo.png', width: 32, height: 32),
          ),
          const SizedBox(width: KraftSpace.sm),
        ],
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'KRAFT',
                    style: KraftText.headlineSm.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  TechBadge(
                    badge,
                    background: badgeHighlighted
                        ? KraftColors.primaryContainer
                        : KraftColors.surfaceContainerHighest,
                    foreground: badgeHighlighted
                        ? KraftColors.onPrimaryContainer
                        : KraftColors.onSurfaceVariant,
                  ),
                  if (breadcrumb != null) ...[
                    const SizedBox(width: KraftSpace.sm),
                    Flexible(
                      child: Text(
                        '/ $breadcrumb',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KraftText.labelCode.copyWith(
                          color: KraftColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  overflow: TextOverflow.ellipsis,
                  style: KraftText.labelCode.copyWith(
                    color: KraftColors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class KraftAvatar extends StatelessWidget {
  const KraftAvatar({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: KraftColors.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/images/avatar.jpg',
          width: size - 4,
          height: size - 4,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

/// Botón cuadrado de icono de la barra superior.
class TopBarIconButton extends StatelessWidget {
  const TopBarIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.highlighted = false,
    this.size = 44,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool highlighted;
  final double size;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Tooltip(
      message: tooltip,
      child: Material(
        color: highlighted
            ? KraftColors.primaryContainer
            : KraftColors.surfaceContainer,
        borderRadius: BorderRadius.circular(KraftRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(KraftRadius.lg),
          onTap: onTap ?? () {},
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: 20, color: KraftColors.onSurface),
          ),
        ),
      ),
    );
  }
}

/// Botón "Buscar..." de la página principal.
class TopBarSearchButton extends StatelessWidget {
  const TopBarSearchButton({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Material(
      color: KraftColors.surfaceContainer,
      borderRadius: BorderRadius.circular(KraftRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(KraftRadius.lg),
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Icon(
                Symbols.search,
                size: 20,
                color: KraftColors.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                'Buscar...',
                style: KraftText.labelCode.copyWith(
                  color: KraftColors.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
