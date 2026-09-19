import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/enums.dart';
import '../../theme/kraft_colors.dart';

/// Colores e iconos asociados a cada tipo, compartidos por tarjetas, insignias y formularios.
extension ProjectKindStyle on ProjectKind {
  Color get color => switch (this) {
    ProjectKind.lienzo => KraftColors.surfaceContainerHigh,
    ProjectKind.stylus => KraftColors.primaryContainer,
    ProjectKind.nota => KraftColors.tertiaryContainer,
  };

  IconData get icon => switch (this) {
    ProjectKind.lienzo => Symbols.draw,
    ProjectKind.stylus => Symbols.stylus_note,
    ProjectKind.nota => Symbols.edit_note,
  };
}

extension EventTagStyle on EventTag {
  /// (acento de borde, texto de hora, fondo de insignia, texto de insignia, icono)
  ({Color accent, Color text, Color badge, Color onBadge, IconData icon})
  get style => switch (this) {
    EventTag.lienzo => (
      accent: KraftColors.primaryContainer,
      text: KraftColors.primary,
      badge: KraftColors.primaryContainer,
      onBadge: KraftColors.onPrimaryContainer,
      icon: Symbols.draw,
    ),
    EventTag.urgente => (
      accent: KraftColors.secondaryContainer,
      text: KraftColors.secondary,
      badge: KraftColors.secondaryContainer,
      onBadge: KraftColors.onSecondaryContainer,
      icon: Symbols.schedule,
    ),
    EventTag.reunion => (
      accent: KraftColors.tertiaryFixedDim,
      text: KraftColors.tertiary,
      badge: KraftColors.tertiaryContainer,
      onBadge: KraftColors.onTertiaryContainer,
      icon: Symbols.groups,
    ),
    EventTag.nota => (
      accent: KraftColors.outline,
      text: KraftColors.onSurfaceVariant,
      badge: KraftColors.surfaceContainerHigh,
      onBadge: KraftColors.onSurfaceVariant,
      icon: Symbols.edit_note,
    ),
  };

  Color get dot => switch (this) {
    EventTag.lienzo => KraftColors.primary,
    EventTag.urgente => KraftColors.secondaryContainer,
    EventTag.reunion => KraftColors.tertiary,
    EventTag.nota => KraftColors.outline,
  };
}

extension NoteCategoryStyle on NoteCategory {
  IconData get icon => switch (this) {
    NoteCategory.idea => Symbols.lightbulb,
    NoteCategory.reunion => Symbols.groups,
    NoteCategory.boceto => Symbols.gesture,
  };

  Color get color => switch (this) {
    NoteCategory.idea => KraftColors.primaryContainer,
    NoteCategory.reunion => KraftColors.tertiaryContainer,
    NoteCategory.boceto => KraftColors.secondaryContainer,
  };
}
