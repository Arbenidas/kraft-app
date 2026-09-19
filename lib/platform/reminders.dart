import 'package:flutter/services.dart';

/// Notificaciones locales y app Recordatorios (ver `KraftReminders` en `AppDelegate.swift`).
abstract interface class ReminderPlatform {
  Future<bool> authorizeNotifications();
  Future<void> schedule({
    required String id,
    required String title,
    required String body,
    required DateTime at,
  });
  Future<void> cancel(List<String> ids);
  Future<bool> authorizeReminders();

  /// Crea o actualiza el recordatorio de Apple y devuelve su identificador (`null` sin permiso).
  Future<String?> saveReminder({
    String? identifier,
    required String title,
    String notes,
    DateTime? at,
    bool done,
  });
  Future<void> deleteReminder(String identifier);
}

class ChannelReminderPlatform implements ReminderPlatform {
  const ChannelReminderPlatform();

  static const channel = MethodChannel('kraft/reminders');

  /// Sin plataforma nativa (tests, escritorio) las llamadas no hacen nada.
  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<bool> authorizeNotifications() async =>
      await _call<bool>('authorizeNotifications') ?? false;

  @override
  Future<void> schedule({
    required String id,
    required String title,
    required String body,
    required DateTime at,
  }) => _call<bool>('schedule', {
    'id': id,
    'title': title,
    'body': body,
    'at': at.millisecondsSinceEpoch,
  });

  @override
  Future<void> cancel(List<String> ids) => _call<void>('cancel', {'ids': ids});

  @override
  Future<bool> authorizeReminders() async =>
      await _call<bool>('authorizeReminders') ?? false;

  @override
  Future<String?> saveReminder({
    String? identifier,
    required String title,
    String notes = '',
    DateTime? at,
    bool done = false,
  }) => _call<String>('saveReminder', {
    'identifier': identifier,
    'title': title,
    'notes': notes,
    'at': at?.millisecondsSinceEpoch,
    'done': done,
  });

  @override
  Future<void> deleteReminder(String identifier) =>
      _call<void>('deleteReminder', {'identifier': identifier});
}
