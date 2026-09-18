import 'package:flutter/painting.dart';

import 'kraft_colors.dart';

abstract final class KraftSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

abstract final class KraftRadius {
  static const sm = 2.0;
  static const md = 4.0;
  static const lg = 8.0;
  static const xl = 12.0;
}

abstract final class KraftShadow {
  /// Sombra dura desplazada, sin desenfoque: la firma neobrutalista.
  static List<BoxShadow> hard([double offset = 3, Color? color]) => [
    BoxShadow(
      color: color ?? KraftColors.shadow,
      offset: Offset(offset, offset),
    ),
  ];

  /// Sombra suave usada en tarjetas de la página principal.
  static const soft = [
    BoxShadow(color: Color(0x14000000), offset: Offset(0, 2), blurRadius: 6),
  ];
}

abstract final class KraftBorder {
  static const width = 2.0;

  /// El borde de siempre: tinta en claro, y en oscuro un tono claro para que se siga viendo.
  static Border ink([double width = KraftBorder.width]) =>
      Border.all(color: KraftColors.border, width: width);
}

/// Ancho a partir del cual las pantallas pasan a disposición en columnas.
const kWideBreakpoint = 900.0;

/// En Mac hay espacio suficiente para una navegación persistente, sin quitar
/// altura útil al contenido. El iPad conserva la barra inferior táctil.
const kDesktopNavigationBreakpoint = 1180.0;

/// A partir de este ancho Inicio aprovecha una cuadrícula para que las tarjetas
/// no queden como un carrusel pensado para dedos.
const kDesktopContentBreakpoint = 1024.0;
