import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app/router.dart';
import '../../data/providers.dart';
import '../../theme/kraft_colors.dart';
import '../../theme/kraft_motion.dart';
import '../../theme/kraft_tokens.dart';
import '../../theme/kraft_typography.dart';
import '../../widgets/entrance.dart';
import '../../widgets/kraft_top_bar.dart';
import '../../widgets/neo_box.dart';
import '../../widgets/section_header.dart';
import '../canvas/canvases_screen.dart';
import '../forms/entity_sheets.dart';
import '../settings/settings_screen.dart';
import 'calendar_card.dart';
import 'project_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Column(
      children: [
        KraftTopBar(
          leading: const KraftBrand(
            badge: 'PRO',
            badgeHighlighted: true,
            subtitle: 'Espacio Creativo',
          ),
          actions: [
            TopBarIconButton(
              icon: Symbols.folder_open,
              tooltip: 'Abrir proyectos',
              onTap: () => context.go(Routes.projects),
            ),
            _CreateButton(onTap: () => showCreateMenu(context, ref)),
            const SettingsButton(),
            const KraftAvatar(),
          ],
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= kWideBreakpoint;
              final desktop = constraints.maxWidth >= kDesktopContentBreakpoint;
              final gutter = desktop
                  ? KraftSpace.xl
                  : wide
                  ? KraftSpace.lg
                  : KraftSpace.md;
              Widget section(int index, Widget child) => Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1440),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: gutter),
                    child: Entrance(index: index, child: child),
                  ),
                ),
              );
              return Scrollbar(
                child: ListView(
                  padding: const EdgeInsets.only(
                    top: KraftSpace.lg,
                    bottom: KraftSpace.xl,
                  ),
                  children: [
                    section(0, _Greeting(showKeyboardHint: desktop)),
                    const SizedBox(height: KraftSpace.lg),
                    section(1, const _PrimaryActions()),
                    const SizedBox(height: KraftSpace.sm),
                    section(2, const _QuickUtilities()),
                    const SizedBox(height: KraftSpace.xl),
                    section(3, const CalendarCard()),
                    const SizedBox(height: KraftSpace.xl),
                    section(4, _RecentProjectsSection(desktop: desktop)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CreateButton extends StatelessWidget {
  const _CreateButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return NeoBox(
      onTap: onTap,
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
          Icon(Symbols.add, size: 20, color: KraftColors.onPrimaryContainer),
          const SizedBox(width: 4),
          Text(
            'CREAR',
            style: KraftText.labelCode.copyWith(
              color: KraftColors.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Greeting extends ConsumerWidget {
  const _Greeting({this.showKeyboardHint = false});

  final bool showKeyboardHint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Theme.of(context); // Rebuild when the active palette changes.
    final projects = ref.watch(projectCountProvider).valueOrNull;
    final notes = ref.watch(noteCountProvider).valueOrNull;

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: KraftSpace.sm,
      spacing: KraftSpace.md,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Hola, Alex', style: KraftText.headlineLg),
            Text(
              '¿En qué quieres trabajar hoy?',
              style: KraftText.bodyMd.copyWith(
                color: KraftColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        Wrap(
          spacing: KraftSpace.sm,
          runSpacing: KraftSpace.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: KraftSpace.md,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: KraftColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(999),
                boxShadow: KraftShadow.soft,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: KraftColors.secondaryContainer,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  _Counter(
                    value: projects,
                    suffix: projects == 1 ? ' Proyecto' : ' Proyectos',
                    bold: true,
                  ),
                  Text(
                    '  •  ',
                    style: KraftText.labelCode.copyWith(
                      color: KraftColors.onSurfaceVariant.withValues(
                        alpha: 0.6,
                      ),
                    ),
                  ),
                  _Counter(
                    value: notes,
                    suffix: notes == 1 ? ' Nota' : ' Notas',
                  ),
                ],
              ),
            ),
            if (showKeyboardHint)
              Tooltip(
                message: 'Usa Ctrl o ⌘ más 1, 2, 3 o 4 para cambiar de sección',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KraftSpace.sm,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: KraftColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(KraftRadius.md),
                  ),
                  child: Text(
                    'CTRL + 1—4',
                    style: KraftText.techBadge.copyWith(
                      color: KraftColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Número que "rueda" hasta su nuevo valor.
class _Counter extends StatelessWidget {
  const _Counter({
    required this.value,
    required this.suffix,
    this.bold = false,
  });

  final int? value;
  final String suffix;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final style = KraftText.labelCode.copyWith(
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      color: bold ? KraftColors.onSurface : KraftColors.onSurfaceVariant,
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(end: (value ?? 0).toDouble()),
      duration: KraftMotion.of(context, KraftMotion.slow),
      curve: KraftMotion.settle,
      builder: (context, v, _) => Text('${v.round()}$suffix', style: style),
    );
  }
}

class _PrimaryActions extends ConsumerWidget {
  const _PrimaryActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Theme.of(context); // Rebuild when the active palette changes.
    final actions = [
      _PrimaryActionCard(
        title: 'Nuevo Lienzo',
        subtitle: 'Bocetos, diagramas y stylus',
        icon: Symbols.draw,
        highlighted: true,
        onTap: () => createCanvasAndOpen(context, ref),
      ),
      _PrimaryActionCard(
        title: 'Nueva Nota',
        subtitle: 'Ideas, listas y texto plano',
        icon: Symbols.edit_note,
        onTap: () => createNoteAndOpen(context, ref),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            children: [
              actions.first,
              const SizedBox(height: KraftSpace.md),
              actions.last,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: actions.first),
            const SizedBox(width: KraftSpace.md),
            Expanded(child: actions.last),
          ],
        );
      },
    );
  }
}

class _PrimaryActionCard extends StatelessWidget {
  const _PrimaryActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.highlighted = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final fg = highlighted
        ? KraftColors.onPrimaryContainer
        : KraftColors.onSurface;
    final sub = highlighted
        ? KraftColors.onPrimaryContainer.withValues(alpha: 0.8)
        : KraftColors.onSurfaceVariant;
    return Semantics(
      label: '$title. $subtitle',
      button: true,
      child: NeoBox(
        onTap: onTap,
        color: highlighted
            ? KraftColors.primaryContainer
            : KraftColors.surfaceContainerLowest,
        borderWidth: KraftBorder.width,
        shadow: 4,
        radius: KraftRadius.lg,
        padding: const EdgeInsets.all(KraftSpace.md),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: highlighted
                    ? KraftColors.surfaceContainerLowest
                    : KraftColors.surfaceContainer,
                borderRadius: BorderRadius.circular(KraftRadius.md),
              ),
              child: Icon(icon, size: 24, color: KraftColors.onSurface),
            ),
            const SizedBox(width: KraftSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: KraftText.headlineSm.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    subtitle,
                    overflow: TextOverflow.ellipsis,
                    style: KraftText.bodySm.copyWith(color: sub),
                  ),
                ],
              ),
            ),
            Icon(
              Symbols.arrow_forward,
              size: 24,
              color: fg.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickUtilities extends StatelessWidget {
  const _QuickUtilities();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final items = [
      ('Mis lienzos', Symbols.draw, () => context.go(Routes.canvas)),
      ('Mis notas', Symbols.edit_note, () => context.go(Routes.notes)),
      ('Explorar grafo', Symbols.hub, () => context.go(Routes.graph)),
    ];
    return Wrap(
      spacing: KraftSpace.xs + 2,
      runSpacing: KraftSpace.xs + 2,
      children: [
        for (final (label, icon, onTap) in items)
          NeoBox(
            onTap: onTap,
            color: KraftColors.surfaceContainer,
            shadow: 0,
            radius: KraftRadius.md,
            padding: const EdgeInsets.symmetric(
              horizontal: KraftSpace.md,
              vertical: 8,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: KraftColors.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: KraftText.labelCode.copyWith(
                    color: KraftColors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _RecentProjectsSection extends ConsumerWidget {
  const _RecentProjectsSection({required this.desktop});

  final bool desktop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Theme.of(context); // Rebuild when the active palette changes.
    final projects = ref.watch(projectsProvider(null)).valueOrNull ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Proyectos Recientes',
          icon: Symbols.folder_open,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _LinkButton(
                label: 'Nuevo',
                leadingIcon: Symbols.add,
                onTap: () => showProjectSheet(context, ref),
              ),
              _LinkButton(
                label: 'Ver todos',
                trailingIcon: Symbols.arrow_forward,
                onTap: () => context.go(Routes.projects),
              ),
            ],
          ),
        ),
        const SizedBox(height: KraftSpace.sm + 4),
        if (projects.isEmpty)
          SizedBox(
            height: 180,
            child: _EmptyProjects(
              onCreate: () => showProjectSheet(context, ref),
            ),
          )
        else if (desktop)
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1260 ? 3 : 2;
              final cardWidth =
                  (constraints.maxWidth - (columns - 1) * KraftSpace.md) /
                  columns;
              return Wrap(
                spacing: KraftSpace.md,
                runSpacing: KraftSpace.lg,
                children: [
                  for (final (i, project) in projects.take(6).indexed)
                    SizedBox(
                      width: cardWidth,
                      child: Entrance(
                        key: ValueKey(project.id),
                        index: i,
                        offset: const Offset(0, 18),
                        child: ProjectCard(
                          project: project,
                          counts: ref.watch(projectCountsProvider)[project.id],
                          width: null,
                          onTap: () => context.push(Routes.project(project.id)),
                        ),
                      ),
                    ),
                ],
              );
            },
          )
        else
          SizedBox(
            height: 310,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
              itemCount: projects.length.clamp(0, 8),
              separatorBuilder: (_, _) => const SizedBox(width: KraftSpace.md),
              itemBuilder: (_, i) => Entrance(
                key: ValueKey(projects[i].id),
                index: i,
                offset: const Offset(24, 0),
                child: ProjectCard(
                  project: projects[i],
                  counts: ref.watch(projectCountsProvider)[projects[i].id],
                  onTap: () => context.push(Routes.project(projects[i].id)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _EmptyProjects extends StatelessWidget {
  const _EmptyProjects({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Center(
      child: NeoBox(
        onTap: onCreate,
        color: KraftColors.primaryContainer,
        borderWidth: KraftBorder.width,
        shadow: 3,
        padding: const EdgeInsets.symmetric(
          horizontal: KraftSpace.lg,
          vertical: KraftSpace.md,
        ),
        child: Text(
          'CREA TU PRIMER PROYECTO',
          style: KraftText.labelCode.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({
    required this.label,
    required this.onTap,
    this.leadingIcon,
    this.trailingIcon,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? leadingIcon;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final style = KraftText.labelCode.copyWith(
      color: KraftColors.primary,
      fontWeight: FontWeight.w700,
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KraftRadius.md),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leadingIcon != null)
              Icon(leadingIcon, size: 16, color: KraftColors.primary),
            Text(' $label ', style: style),
            if (trailingIcon != null)
              Icon(trailingIcon, size: 16, color: KraftColors.primary),
          ],
        ),
      ),
    );
  }
}
