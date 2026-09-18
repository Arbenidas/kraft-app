import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/db/database.dart';
import '../../data/providers.dart';
import '../../data/enums.dart';
import '../../theme/kraft_colors.dart';
import '../../theme/kraft_tokens.dart';
import '../../theme/kraft_typography.dart';
import '../../utils/dates.dart';
import '../../widgets/dot_grid.dart';
import '../../widgets/neo_box.dart';
import '../../widgets/tech_badge.dart';
import '../forms/entity_styles.dart';

class ProjectCard extends StatelessWidget {
  const ProjectCard({
    super.key,
    required this.project,
    required this.onTap,
    this.width = 340,
    this.counts,
  });

  /// Cuánto contiene el proyecto. Sin esto la tarjeta no dice nada de su contenido.
  final ProjectCounts? counts;

  final Project project;
  final VoidCallback onTap;
  final double? width;

  static const coverHeight = 160.0;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final highlighted = project.kind == ProjectKind.stylus;
    return SizedBox(
      width: width,
      child: NeoBox(
        onTap: onTap,
        shadow: 3,
        radius: KraftRadius.lg,
        clip: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: coverHeight,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ProjectCover(project: project),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: TechBadge(
                      project.kind.label,
                      background: highlighted
                          ? KraftColors.primaryContainer
                          : KraftColors.glass,
                      foreground: highlighted
                          ? KraftColors.onPrimaryContainer
                          : KraftColors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(KraftSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          project.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: KraftText.headlineSm.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: KraftSpace.sm),
                      Text(
                        relativeTime(project.updatedAt),
                        style: KraftText.labelCode.copyWith(
                          color: KraftColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 36,
                    child: Text(
                      project.description.isEmpty
                          ? 'Sin descripción'
                          : project.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: KraftText.bodySm,
                    ),
                  ),
                  const SizedBox(height: KraftSpace.sm),
                  if (counts case final c?) ...[
                    Builder(
                      builder: (_) {
                        final parts = [
                          if (c.notes > 0) '${c.notes} notas',
                          if (c.canvases > 0) '${c.canvases} lienzos',
                          if (c.tasks > 0) '${c.tasks} tareas',
                        ];
                        return Text(
                          parts.isEmpty
                              ? 'Vacío · toca para llenarlo'
                              : parts.join(' · '),
                          style: KraftText.labelCode.copyWith(
                            color: KraftColors.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: KraftSpace.xs),
                  ],
                  SizedBox(
                    height: 18,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        for (final tag in project.tags)
                          Padding(
                            padding: const EdgeInsets.only(
                              right: KraftSpace.xs,
                            ),
                            child: TechBadge(tag),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProjectCover extends StatelessWidget {
  const ProjectCover({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final asset = project.imageAsset;
    if (asset != null) {
      // Decodifica al tamaño mostrado (x2) en vez de a la resolución original.
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final Widget imageWidget;
      if (asset.startsWith('assets/')) {
        imageWidget = Image.asset(
          asset,
          fit: BoxFit.cover,
          cacheWidth: (380 * dpr).round(),
        );
      } else {
        imageWidget = Image.file(
          File(asset),
          fit: BoxFit.cover,
          cacheWidth: (380 * dpr).round(),
          errorBuilder: (_, _, _) => _GeneratedCover(project: project),
        );
      }

      return Stack(
        fit: StackFit.expand,
        children: [
          imageWidget,
          // Degradado sutil en la parte inferior para profundidad y legibilidad
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.45, 1.0],
                  colors: [
                    Colors.transparent,
                    KraftColors.surfaceContainerLowest.withValues(alpha: 0.82),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }
    return _GeneratedCover(project: project);
  }
}

class _GeneratedCover extends StatelessWidget {
  const _GeneratedCover({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final kindColor = project.kind.color;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kindColor.withValues(alpha: 0.35),
            KraftColors.surfaceContainerLowest,
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: DotGrid(spacing: 14, radius: 1, color: KraftColors.dots),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: KraftColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(KraftRadius.lg),
                    border: Border.all(
                      color: kindColor.withValues(alpha: 0.7),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: kindColor.withValues(alpha: 0.25),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                      ...KraftShadow.hard(2, KraftColors.shadow.withValues(alpha: 0.4)),
                    ],
                  ),
                  child: Icon(
                    project.kind.icon,
                    size: 28,
                    color: kindColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  project.kind.label,
                  style: KraftText.labelCode.copyWith(
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w700,
                    color: KraftColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
