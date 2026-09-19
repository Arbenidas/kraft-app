import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../theme/kraft_colors.dart';
import '../../theme/kraft_tokens.dart';
import '../../theme/kraft_typography.dart';
import '../../widgets/dot_grid.dart';
import '../../widgets/kraft_top_bar.dart';
import '../../widgets/neo_box.dart';
import '../../widgets/tech_badge.dart';

/// Marcador de posición: aún no existe vista de Grafo en Stitch.
class GraphScreen extends StatelessWidget {
  const GraphScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Column(
      children: [
        const KraftTopBar(
          leading: KraftBrand(breadcrumb: 'Grafo'),
          actions: [KraftAvatar()],
        ),
        Expanded(
          child: Stack(
            children: [
              const Positioned.fill(child: DotGrid()),
              Center(
                child: NeoBox(
                  borderWidth: KraftBorder.width,
                  shadow: 4,
                  padding: const EdgeInsets.all(KraftSpace.lg),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TechBadge(
                          'PRÓXIMAMENTE',
                          background: KraftColors.primaryContainer,
                          foreground: KraftColors.onSurface,
                        ),
                        const SizedBox(height: KraftSpace.md),
                        Icon(
                          Symbols.hub,
                          size: 48,
                          color: KraftColors.onSurface,
                        ),
                        const SizedBox(height: KraftSpace.sm),
                        Text(
                          'Grafo de ideas',
                          style: KraftText.headlineLg.copyWith(fontSize: 28),
                        ),
                        const SizedBox(height: KraftSpace.xs),
                        Text(
                          'Conexiones entre proyectos, notas y bocetos.',
                          textAlign: TextAlign.center,
                          style: KraftText.bodyMd.copyWith(
                            color: KraftColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
