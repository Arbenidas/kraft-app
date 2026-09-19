import 'package:flutter/painting.dart';

import 'kraft_colors.dart';

/// Escala tipográfica de Stitch: Space Grotesk (titulares),
/// Hanken Grotesk (cuerpo) y JetBrains Mono (etiquetas técnicas).
/// Los estilos se construyen al vuelo porque el color depende de la paleta activa.
abstract final class KraftText {
  static const _headline = 'Space Grotesk';
  static const _body = 'Hanken Grotesk';
  static const _mono = 'JetBrains Mono';

  static TextStyle get headlineXl => TextStyle(
    fontFamily: _headline,
    fontSize: 40,
    height: 48 / 40,
    letterSpacing: -1.2,
    fontWeight: FontWeight.w700,
    color: KraftColors.onSurface,
  );

  static TextStyle get headlineLg => TextStyle(
    fontFamily: _headline,
    fontSize: 32,
    height: 40 / 32,
    letterSpacing: -0.64,
    fontWeight: FontWeight.w700,
    color: KraftColors.onSurface,
  );

  static TextStyle get headlineSm => TextStyle(
    fontFamily: _headline,
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w600,
    color: KraftColors.onSurface,
  );

  static TextStyle get bodyLg => TextStyle(
    fontFamily: _body,
    fontSize: 17,
    height: 26 / 17,
    fontWeight: FontWeight.w400,
    color: KraftColors.onSurface,
  );

  static TextStyle get bodyMd => TextStyle(
    fontFamily: _body,
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w400,
    color: KraftColors.onSurface,
  );

  static TextStyle get bodySm => TextStyle(
    fontFamily: _body,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w500,
    color: KraftColors.onSurfaceVariant,
  );

  static TextStyle get labelCode => TextStyle(
    fontFamily: _mono,
    fontSize: 13,
    height: 16 / 13,
    letterSpacing: 0.26,
    fontWeight: FontWeight.w500,
    color: KraftColors.onSurface,
  );

  static TextStyle get techBadge => TextStyle(
    fontFamily: _mono,
    fontSize: 11,
    height: 14 / 11,
    letterSpacing: 0.55,
    fontWeight: FontWeight.w700,
    color: KraftColors.onSurface,
  );
}
