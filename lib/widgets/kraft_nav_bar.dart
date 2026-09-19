import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/kraft_colors.dart';
import '../theme/kraft_motion.dart';
import '../theme/kraft_tokens.dart';
import '../theme/kraft_typography.dart';

class KraftNavDestination {
  const KraftNavDestination(this.label, this.icon);

  final String label;
  final IconData icon;
}

const kraftDestinations = [
  KraftNavDestination('Inicio', Symbols.grid_view),
  KraftNavDestination('Lienzo', Symbols.draw),
  KraftNavDestination('Notas', Symbols.edit_note),
  KraftNavDestination('Grafo', Symbols.hub),
];

/// Barra de navegación inferior; el destino activo va en amarillo con borde y sombra dura.
class KraftNavBar extends StatelessWidget {
  const KraftNavBar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

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
            offset: Offset(0, -1),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 672),
            child: SizedBox(
              height: 72,
              child: Row(
                children: [
                  for (final (i, dest) in kraftDestinations.indexed)
                    Expanded(
                      child: _NavItem(
                        destination: dest,
                        active: i == currentIndex,
                        onTap: () => onSelect(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Navegación persistente para escritorio. Conserva nombres visibles, foco de
/// teclado y ayudas emergentes; en iPad se usa [KraftNavBar] por su área táctil.
class KraftNavigationRail extends StatelessWidget {
  const KraftNavigationRail({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Container(
      width: 104,
      decoration: BoxDecoration(
        color: KraftColors.glass,
        border: Border(right: BorderSide(color: KraftColors.outlineVariant)),
      ),
      child: SafeArea(
        right: false,
        child: NavigationRail(
          backgroundColor: Colors.transparent,
          minWidth: 104,
          groupAlignment: -0.72,
          selectedIndex: currentIndex,
          labelType: NavigationRailLabelType.all,
          indicatorColor: KraftColors.primaryContainer,
          selectedIconTheme: IconThemeData(
            color: KraftColors.onPrimaryContainer,
          ),
          unselectedIconTheme: IconThemeData(
            color: KraftColors.onSurfaceVariant,
          ),
          selectedLabelTextStyle: KraftText.techBadge.copyWith(
            color: KraftColors.onSurface,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.7,
          ),
          unselectedLabelTextStyle: KraftText.techBadge.copyWith(
            color: KraftColors.onSurfaceVariant,
            letterSpacing: 0.7,
          ),
          leading: Padding(
            padding: const EdgeInsets.only(bottom: KraftSpace.lg),
            child: Text(
              'NAVEGAR',
              style: KraftText.techBadge.copyWith(
                color: KraftColors.onSurfaceVariant,
              ),
            ),
          ),
          destinations: [
            for (final (i, destination) in kraftDestinations.indexed)
              NavigationRailDestination(
                icon: Tooltip(
                  message: '${destination.label} · Ctrl+${i + 1}',
                  child: ExcludeSemantics(child: Icon(destination.icon)),
                ),
                selectedIcon: ExcludeSemantics(
                  child: Icon(destination.icon, fill: 1),
                ),
                label: Text(
                  destination.label.toUpperCase(),
                  semanticsLabel: destination.label,
                ),
              ),
          ],
          onDestinationSelected: onSelect,
          trailing: Padding(
            padding: const EdgeInsets.all(KraftSpace.sm),
            child: Text(
              'CTRL\n1—4',
              textAlign: TextAlign.center,
              style: KraftText.techBadge.copyWith(
                color: KraftColors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.active,
    required this.onTap,
  });

  final KraftNavDestination destination;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final fg = active
        ? KraftColors.onPrimaryContainer
        : KraftColors.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: active,
      label: destination.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            duration: KraftMotion.of(context, KraftMotion.base),
            // Sin rebote: al desactivarse, un sobrepaso daría un borde de grosor negativo.
            curve: KraftMotion.settle,
            constraints: const BoxConstraints(minWidth: 88, minHeight: 50),
            padding: const EdgeInsets.symmetric(
              horizontal: KraftSpace.md,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: active ? KraftColors.primaryContainer : null,
              borderRadius: BorderRadius.circular(KraftRadius.lg),
              border: active ? KraftBorder.ink() : null,
              boxShadow: active ? KraftShadow.hard(2) : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  scale: active ? 1.1 : 1,
                  duration: KraftMotion.of(context, KraftMotion.base),
                  curve: KraftMotion.pop,
                  child: Icon(
                    destination.icon,
                    size: 22,
                    color: fg,
                    fill: active ? 1 : 0,
                  ),
                ),
                const SizedBox(height: 2),
                ExcludeSemantics(
                  child: Text(
                    destination.label.toUpperCase(),
                    style: KraftText.techBadge.copyWith(
                      color: fg,
                      fontSize: 10,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
