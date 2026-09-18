import 'dart:ui' show Brightness;

import 'package:flutter/painting.dart';

/// Una paleta completa de KRAFT. Hay dos: la clara (la de las vistas de Stitch)
/// y la oscura (Gruvbox). Todo el color de la app sale de aquí.
class KraftPalette {
  const KraftPalette({
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.primaryFixed,
    required this.primaryFixedDim,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.onTertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.tertiaryFixedDim,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.surface,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.inverseSurface,
    required this.inverseOnSurface,
    required this.outline,
    required this.outlineVariant,
    required this.ink,
    required this.border,
    required this.shadow,
    required this.inkFill,
    required this.onInkFill,
    required this.glass,
    required this.dots,
    required this.scrim,
    required this.brightness,
  });

  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color primaryFixed;
  final Color primaryFixedDim;
  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
  final Color tertiary;
  final Color onTertiary;
  final Color tertiaryContainer;
  final Color onTertiaryContainer;
  final Color tertiaryFixedDim;
  final Color error;
  final Color onError;
  final Color errorContainer;
  final Color onErrorContainer;
  final Color surface;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color surfaceContainerLowest;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color inverseSurface;
  final Color inverseOnSurface;
  final Color outline;
  final Color outlineVariant;

  /// Tinta del texto, los iconos y los trazos sobre el fondo. En oscuro es crema, no negro.
  final Color ink;

  /// Color del borde neobrutalista. En claro es la tinta; en oscuro, más claro para que se vea.
  final Color border;

  /// La sombra dura: siempre casi negra, también de noche.
  final Color shadow;

  /// Relleno del botón "fuerte" (guardar, hablar, pestaña activa) y su color de texto.
  final Color inkFill;
  final Color onInkFill;

  /// Fondo translúcido de las barras superior e inferior.
  final Color glass;

  /// Puntos del fondo del lienzo y velo de las hojas modales.
  final Color dots;
  final Color scrim;

  final Brightness brightness;

  /// La paleta original, tomada del `tailwind.config` de las vistas de Stitch.
  static const claro = KraftPalette(
    primary: Color(0xFF6A5F00),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFFFE600),
    // La tinta sobre el amarillo necesita contraste alto; el oliva original
    // perdía legibilidad en etiquetas pequeñas y estados de foco.
    onPrimaryContainer: Color(0xFF1C1B1B),
    primaryFixed: Color(0xFFFDE400),
    primaryFixedDim: Color(0xFFDEC800),
    secondary: Color(0xFF006D35),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFF00FA82),
    onSecondaryContainer: Color(0xFF003D20),
    tertiary: Color(0xFF006875),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFA5F1FF),
    onTertiaryContainer: Color(0xFF003D47),
    tertiaryFixedDim: Color(0xFF00DAF3),
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF93000A),
    surface: Color(0xFFFCF9F8),
    onSurface: Color(0xFF1C1B1B),
    onSurfaceVariant: Color(0xFF4B4731),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF6F3F2),
    surfaceContainer: Color(0xFFF0EDEC),
    surfaceContainerHigh: Color(0xFFEBE7E7),
    surfaceContainerHighest: Color(0xFFE5E2E1),
    inverseSurface: Color(0xFF313030),
    inverseOnSurface: Color(0xFFF3F0EF),
    outline: Color(0xFF7C775F),
    outlineVariant: Color(0xFFCDC7AA),
    ink: Color(0xFF1C1B1B),
    border: Color(0xFF1C1B1B),
    shadow: Color(0xFF1C1B1B),
    inkFill: Color(0xFF1C1B1B),
    onInkFill: Color(0xFFFFE600),
    glass: Color(0xE6FCF9F8),
    dots: Color(0x661C1B1B),
    scrim: Color(0x551C1B1B),
    brightness: Brightness.light,
  );

  /// Gruvbox oscuro: los mismos papeles, con sus colores cálidos.
  /// El amarillo sigue mandando, así que KRAFT se reconoce igual de noche.
  static const gruvbox = KraftPalette(
    primary: Color(0xFFFABD2F), // yellow brillante: se lee sobre el fondo
    onPrimary: Color(0xFF1D2021),
    primaryContainer: Color(0xFFFABD2F), // bright yellow
    onPrimaryContainer: Color(0xFF1D2021),
    primaryFixed: Color(0xFFFABD2F),
    primaryFixedDim: Color(0xFFD79921),
    secondary: Color(0xFFB8BB26), // green
    onSecondary: Color(0xFF1D2021),
    secondaryContainer: Color(0xFFB8BB26), // bright green
    onSecondaryContainer: Color(0xFF1D2021),
    tertiary: Color(0xFF8EC07C), // aqua
    onTertiary: Color(0xFF1D2021),
    tertiaryContainer: Color(0xFF8EC07C), // bright aqua
    onTertiaryContainer: Color(0xFF1D2021),
    tertiaryFixedDim: Color(0xFF83A598), // blue
    error: Color(0xFFFB4934), // bright red
    onError: Color(0xFF1D2021),
    errorContainer: Color(0xFFCC241D),
    onErrorContainer: Color(0xFFFBF1C7),
    surface: Color(0xFF282828), // bg0
    onSurface: Color(0xFFEBDBB2), // fg1
    onSurfaceVariant: Color(0xFFD5C4A1), // fg3
    surfaceContainerLowest: Color(
      0xFF32302F,
    ), // bg0_s: las tarjetas, por encima del fondo
    surfaceContainerLow: Color(0xFF3C3836), // bg1
    surfaceContainer: Color(0xFF3C3836),
    surfaceContainerHigh: Color(0xFF504945), // bg2
    surfaceContainerHighest: Color(0xFF504945), // bg3
    inverseSurface: Color(0xFFEBDBB2),
    inverseOnSurface: Color(0xFF282828),
    outline: Color(0xFFA89984), // fg4
    outlineVariant: Color(0xFF665C54), // bg3: las separaciones tienen que verse
    ink: Color(0xFFEBDBB2), // fg1: el texto y los trazos son crema, no negros
    border: Color(
      0xFFA89984,
    ), // fg4: el borde tiene que verse sobre el fondo oscuro
    shadow: Color(0xFF16181A), // la sombra dura sigue siendo casi negra
    inkFill: Color(
      0xFFEBDBB2,
    ), // el botón fuerte se invierte: crema con texto oscuro
    onInkFill: Color(0xFF1D2021),
    glass: Color(0xE6252525),
    dots: Color(0x4DEBDBB2),
    scrim: Color(0xAA16181A),
    brightness: Brightness.dark,
  );
}

/// El color activo de la app. Cambia de paleta con [use] y la app se redibuja entera
/// (ver `KraftApp`), así que todo lo que lee estos valores se actualiza solo.
abstract final class KraftColors {
  static KraftPalette active = KraftPalette.claro;

  static void use(Brightness brightness) {
    active = brightness == Brightness.dark
        ? KraftPalette.gruvbox
        : KraftPalette.claro;
  }

  /// Choose the foreground with the highest WCAG contrast, including custom fills.
  static Color onColor(Color background) {
    final opaque = Color.alphaBlend(background, surface);
    const dark = Color(0xFF16181A), light = Color(0xFFFFFCF2);
    final lum = opaque.computeLuminance();
    final darkRatio = (lum + 0.05) / (dark.computeLuminance() + 0.05);
    final lightRatio = (light.computeLuminance() + 0.05) / (lum + 0.05);
    return darkRatio >= lightRatio ? dark : light;
  }

  static bool get isDark => active.brightness == Brightness.dark;

  static Color get primary => active.primary;
  static Color get onPrimary => active.onPrimary;
  static Color get primaryContainer => active.primaryContainer;
  static Color get onPrimaryContainer => active.onPrimaryContainer;
  static Color get primaryFixed => active.primaryFixed;
  static Color get primaryFixedDim => active.primaryFixedDim;

  static Color get secondary => active.secondary;
  static Color get onSecondary => active.onSecondary;
  static Color get secondaryContainer => active.secondaryContainer;
  static Color get onSecondaryContainer => active.onSecondaryContainer;

  static Color get tertiary => active.tertiary;
  static Color get onTertiary => active.onTertiary;
  static Color get tertiaryContainer => active.tertiaryContainer;
  static Color get onTertiaryContainer => active.onTertiaryContainer;
  static Color get tertiaryFixedDim => active.tertiaryFixedDim;

  static Color get error => active.error;
  static Color get onError => active.onError;
  static Color get errorContainer => active.errorContainer;
  static Color get onErrorContainer => active.onErrorContainer;

  static Color get surface => active.surface;
  static Color get onSurface => active.onSurface;
  static Color get onSurfaceVariant => active.onSurfaceVariant;
  static Color get surfaceContainerLowest => active.surfaceContainerLowest;
  static Color get surfaceContainerLow => active.surfaceContainerLow;
  static Color get surfaceContainer => active.surfaceContainer;
  static Color get surfaceContainerHigh => active.surfaceContainerHigh;
  static Color get surfaceContainerHighest => active.surfaceContainerHighest;
  static Color get inverseSurface => active.inverseSurface;
  static Color get inverseOnSurface => active.inverseOnSurface;

  static Color get outline => active.outline;
  static Color get outlineVariant => active.outlineVariant;

  /// Tinta de las sombras duras y de los rellenos oscuros.
  static Color get ink => active.ink;

  /// Color del borde neobrutalista.
  static Color get border => active.border;

  /// Sombra dura (casi negra en las dos paletas).
  static Color get shadow => active.shadow;

  /// Botón fuerte: relleno y color de su texto.
  static Color get inkFill => active.inkFill;
  static Color get onInkFill => active.onInkFill;

  /// Barras translúcidas, puntos del lienzo y velo de las hojas.
  static Color get glass => active.glass;
  static Color get dots => active.dots;
  static Color get scrim => active.scrim;
}
