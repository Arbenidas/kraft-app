import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app/router.dart';
import '../../data/providers.dart';
import '../../theme/kraft_colors.dart';
import '../../theme/kraft_tokens.dart';
import '../../theme/kraft_typography.dart';
import '../../widgets/kraft_top_bar.dart';
import '../../widgets/section_header.dart';
import 'work_items_panel.dart';

/// Vista de trabajo separada del resumen bento del proyecto. Tener rutas
/// distintas evita que una tarjeta parezca un simple selector que deja el
/// contenido fuera de la pantalla.
class ProjectWorkScreen extends ConsumerWidget {
  const ProjectWorkScreen({
    super.key,
    required this.projectId,
    required this.requirements,
    this.focusItemId,
  });

  final int projectId;
  final bool requirements;
  final int? focusItemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(projectProvider(projectId)).valueOrNull;
    final title = requirements ? 'Requerimientos' : 'Actividades';
    final icon = requirements ? Symbols.rule : Symbols.calendar_month;
    final subtitle = requirements
        ? 'Alcance, criterios de aceptación y desglose del proyecto'
        : 'Trabajo planificado y seguimiento del proyecto';

    return ColoredBox(
      color: KraftColors.surface,
      child: Column(
        children: [
          KraftTopBar(
            leading: Row(
              children: [
                TopBarIconButton(
                  icon: Symbols.arrow_back,
                  tooltip: 'Volver al proyecto',
                  onTap: () => context.go(Routes.project(projectId)),
                ),
                const SizedBox(width: KraftSpace.sm + 4),
                Flexible(
                  child: KraftBrand(
                    breadcrumb: project == null
                        ? title
                        : '${project.title} / $title',
                    showLogo: false,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(KraftSpace.xl),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SectionHeader(title: title, icon: icon),
                        const SizedBox(height: KraftSpace.xs),
                        Text(
                          subtitle,
                          style: KraftText.bodyMd.copyWith(
                            color: KraftColors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: KraftSpace.xl),
                        WorkItemsPanel(
                          projectId: projectId,
                          requirements: requirements,
                          focusItemId: focusItemId,
                        ),
                      ],
                    ),
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
