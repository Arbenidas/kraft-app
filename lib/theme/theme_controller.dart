import 'package:flutter/material.dart';

import '../data/repositories.dart';

/// Claro, oscuro (Gruvbox) o lo que diga el sistema. Se recuerda entre sesiones.
class ThemeController extends ChangeNotifier {
  ThemeController(this._settings);

  final SettingsRepository _settings;

  static const key = 'theme.mode';

  ThemeMode mode = ThemeMode.system;

  Future<void> load() async {
    mode = switch (await _settings.get(key)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    notifyListeners();
  }

  Future<void> set(ThemeMode next) async {
    if (next == mode) return;
    mode = next;
    notifyListeners();
    await _settings.set(key, next.name);
  }

  /// El brillo que toca pintar ahora mismo.
  Brightness brightness(Brightness system) => switch (mode) {
    ThemeMode.light => Brightness.light,
    ThemeMode.dark => Brightness.dark,
    ThemeMode.system => system,
  };

  String get label => switch (mode) {
    ThemeMode.light => 'Claro',
    ThemeMode.dark => 'Gruvbox',
    ThemeMode.system => 'Como el sistema',
  };
}
