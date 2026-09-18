import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app/router.dart';
import '../../data/enums.dart';
import '../../data/providers.dart';
import '../../theme/kraft_colors.dart';
import '../../theme/kraft_motion.dart';
import '../../theme/kraft_tokens.dart';
import '../../theme/kraft_typography.dart';
import '../../widgets/entrance.dart';
import '../../widgets/filter_pill.dart';
import '../../widgets/kraft_top_bar.dart';
import '../../widgets/neo_box.dart';
import '../forms/entity_sheets.dart';
import '../forms/entity_styles.dart';
import '../home/project_card.dart';

final _kindFilterProvider = StateProvider.autoDispose<ProjectKind?>(
  (ref) => null,
);

class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Theme.of(context); // Rebuild when the active palette changes.
    final kind = ref.watch(_kindFilterProvider);
    final projects = ref.watch(projectsProvider(kind)).valueOrNull;

    return Column(
      children: [
        KraftTopBar(
          leading: Row(
            children: [
              TopBarIconButton(
                icon: Symbols.arrow_back,
                tooltip: 'Volver',
                onTap: () => context.go(Routes.home),
              ),
              const SizedBox(width: KraftSpace.sm + 4),
              const Flexible(
                child: KraftBrand(breadcrumb: 'Proyectos', showLogo: false),
              ),
            ],
          ),
          actions: [
            NeoBox(
              onTap: () => showProjectSheet(context, ref),
              color: KraftColors.primaryContainer,
              borderWidth: 1.5,
              shadow: 2,
              radius: KraftRadius.lg,
              padding: const EdgeInsets.symmetric(
                horizontal: KraftSpace.md,
                vertical: 10,
              ),
              child: Row(
                children: [
                  const Icon(Symbols.add, size: 20),
                  const SizedBox(width: 4),
                  Text(
                    'NUEVO PROYECTO',
                    style: KraftText.labelCode.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const gap = KraftSpace.md;
              final contentWidth = constraints.maxWidth - KraftSpace.xl * 2;
              final columns = (contentWidth / 320).floor().clamp(1, 4);
              final cardWidth = (contentWidth - gap * (columns - 1)) / columns;

              return ListView(
                padding: const EdgeInsets.all(KraftSpace.xl),
                children: [
                  Text(
                    'Todos los proyectos',
                    style: KraftText.headlineLg.copyWith(fontSize: 28),
                  ),
                  const SizedBox(height: KraftSpace.md),
                  Wrap(
                    spacing: KraftSpace.sm,
                    runSpacing: KraftSpace.sm,
                    children: [
                      FilterPill(
                        label: 'TODOS',
                        icon: Symbols.done_all,
                        selected: kind == null,
                        onTap: () =>
                            ref.read(_kindFilterProvider.notifier).state = null,
                      ),
                      for (final k in ProjectKind.values)
                        FilterPill(
                          label: k.label,
                          icon: k.icon,
                          selected: kind == k,
                          onTap: () =>
                              ref.read(_kindFilterProvider.notifier).state = k,
                        ),
                    ],
                  ),
                  const SizedBox(height: KraftSpace.lg),
                  if (projects == null)
                    const SizedBox(height: 200)
                  else if (projects.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: KraftSpace.xl),
                      child: Text(
                        kind == null
                            ? 'Aún no hay proyectos.'
                            : 'No hay proyectos de tipo ${kind.label}.',
                        textAlign: TextAlign.center,
                        style: KraftText.labelCode.copyWith(
                          color: KraftColors.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    AnimatedSwitcher(
                      duration: KraftMotion.of(context, KraftMotion.fast),
                      child: Wrap(
                        key: ValueKey(kind),
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (final (i, p) in projects.indexed)
                            Entrance(
                              key: ValueKey(p.id),
                              index: i,
                              child: ProjectCard(
                                project: p,
                                counts: ref.watch(projectCountsProvider)[p.id],
                                width: cardWidth,
                                onTap: () => context.push(Routes.project(p.id)),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
