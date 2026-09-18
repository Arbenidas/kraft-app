import 'package:flutter/material.dart';

import 'kraft_colors.dart';
import 'kraft_typography.dart';

abstract final class KraftTheme {
  /// Construye el tema con la paleta que esté activa (ver [KraftColors.use]).
  static ThemeData of(Brightness brightness) {
    KraftColors.use(brightness);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: KraftColors.primary,
      onPrimary: KraftColors.onPrimary,
      primaryContainer: KraftColors.primaryContainer,
      onPrimaryContainer: KraftColors.onPrimaryContainer,
      secondary: KraftColors.secondary,
      onSecondary: KraftColors.onSecondary,
      secondaryContainer: KraftColors.secondaryContainer,
      onSecondaryContainer: KraftColors.onSecondaryContainer,
      tertiary: KraftColors.tertiary,
      onTertiary: KraftColors.onTertiary,
      tertiaryContainer: KraftColors.tertiaryContainer,
      onTertiaryContainer: KraftColors.onTertiaryContainer,
      error: KraftColors.error,
      onError: KraftColors.onError,
      errorContainer: KraftColors.errorContainer,
      onErrorContainer: KraftColors.onErrorContainer,
      surface: KraftColors.surface,
      onSurface: KraftColors.onSurface,
      onSurfaceVariant: KraftColors.onSurfaceVariant,
      surfaceContainerLowest: KraftColors.surfaceContainerLowest,
      surfaceContainerLow: KraftColors.surfaceContainerLow,
      surfaceContainer: KraftColors.surfaceContainer,
      surfaceContainerHigh: KraftColors.surfaceContainerHigh,
      surfaceContainerHighest: KraftColors.surfaceContainerHighest,
      outline: KraftColors.outline,
      outlineVariant: KraftColors.outlineVariant,
      inverseSurface: KraftColors.inverseSurface,
      onInverseSurface: KraftColors.inverseOnSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: KraftColors.surface,
      fontFamily: 'Hanken Grotesk',
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      focusColor: KraftColors.primaryContainer.withValues(alpha: 0.35),
      hoverColor: KraftColors.primaryContainer.withValues(alpha: 0.16),
      textTheme: TextTheme(
        displayLarge: KraftText.headlineXl,
        headlineLarge: KraftText.headlineLg,
        titleLarge: KraftText.headlineSm,
        bodyLarge: KraftText.bodyLg,
        bodyMedium: KraftText.bodyMd,
        bodySmall: KraftText.bodySm,
        labelLarge: KraftText.labelCode,
        labelSmall: KraftText.techBadge,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: KraftColors.onSurface,
        selectionColor: KraftColors.primaryContainer,
      ),
    );
  }

  @Deprecated('Usa KraftTheme.of(Brightness.light)')
  static ThemeData light() => of(Brightness.light);
}
