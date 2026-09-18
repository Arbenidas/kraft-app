import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Iconos disponibles en el lienzo, guardados por clave.
/// Se guardan por nombre y no por `codePoint`: así sobreviven al tree-shaking de iconos del build de release.
const canvasIcons = <String, (IconData, String)>{
  'star': (Symbols.star, 'Estrella'),
  'favorite': (Symbols.favorite, 'Corazón'),
  'check_circle': (Symbols.check_circle, 'Hecho'),
  'cancel': (Symbols.cancel, 'Descartado'),
  'warning': (Symbols.warning, 'Alerta'),
  'help': (Symbols.help, 'Duda'),
  'lightbulb': (Symbols.lightbulb, 'Idea'),
  'bolt': (Symbols.bolt, 'Rápido'),
  'flag': (Symbols.flag, 'Hito'),
  'push_pin': (Symbols.push_pin, 'Pin'),
  'rocket_launch': (Symbols.rocket_launch, 'Lanzamiento'),
  'target': (Symbols.target, 'Objetivo'),
  'person': (Symbols.person, 'Persona'),
  'groups': (Symbols.groups, 'Equipo'),
  'chat': (Symbols.chat, 'Comentario'),
  'mail': (Symbols.mail, 'Correo'),
  'calendar_today': (Symbols.calendar_today, 'Fecha'),
  'schedule': (Symbols.schedule, 'Tiempo'),
  'smartphone': (Symbols.smartphone, 'Móvil'),
  'tablet_mac': (Symbols.tablet_mac, 'iPad'),
  'desktop_windows': (Symbols.desktop_windows, 'Escritorio'),
  'cloud': (Symbols.cloud, 'Nube'),
  'database': (Symbols.database, 'Datos'),
  'lock': (Symbols.lock, 'Seguridad'),
  'fingerprint': (Symbols.fingerprint, 'Biometría'),
  'settings': (Symbols.settings, 'Ajustes'),
  'search': (Symbols.search, 'Buscar'),
  'image': (Symbols.image, 'Imagen'),
  'draw': (Symbols.draw, 'Boceto'),
  'palette': (Symbols.palette, 'Color'),
  'attach_money': (Symbols.attach_money, 'Dinero'),
  'shopping_cart': (Symbols.shopping_cart, 'Compra'),
};

IconData? canvasIcon(String? key) => key == null ? null : canvasIcons[key]?.$1;
