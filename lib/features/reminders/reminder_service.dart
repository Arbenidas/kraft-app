import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/db/database.dart';
import '../../data/repositories.dart';
import '../../platform/reminders.dart';

/// Mantiene las notificaciones (y, si se activa, la app Recordatorios) al día con las tareas.
/// Escucha la tabla de tareas: da igual desde dónde se creen o cambien (hoja, lista, voz, deshacer).
class ReminderService extends ChangeNotifier {
  ReminderService({
    required TasksRepository tasks,
    required SettingsRepository settings,
    ReminderPlatform platform = const ChannelReminderPlatform(),
    DateTime Function()? clock,
  }) : _tasks = tasks,
       _settings = settings,
       _platform = platform,
       _clock = clock ?? DateTime.now;

  final TasksRepository _tasks;
  final SettingsRepository _settings;
  final ReminderPlatform _platform;
  final DateTime Function() _clock;

  static const appleSyncKey = 'reminders.appleSync';

  StreamSubscription<List<QuickTask>>? _subscription;
  Map<int, _TaskState>? _known;
  Future<void> _queue = Future.value();
  bool _appleSync = false;
  bool _notificationsAsked = false;

  bool get appleSync => _appleSync;

  static String notificationId(int taskId) => 'task-$taskId';

  Future<void> start() async {
    _appleSync = await _settings.get(appleSyncKey) == 'true';
    notifyListeners();
    _subscription = _tasks.watchAll().listen(
      (list) => _queue = _queue.then((_) => _reconcile(list)),
    );
  }

  /// Pide permiso de notificaciones la primera vez que se pone un recordatorio.
  Future<bool> ensureNotificationPermission() async {
    if (_notificationsAsked) return true;
    _notificationsAsked = true;
    return _platform.authorizeNotifications();
  }

  /// Activa o desactiva la copia en Recordatorios de Apple. Devuelve `false` si iOS no dio permiso.
  Future<bool> setAppleSync(bool enabled) async {
    if (enabled && !await _platform.authorizeReminders()) return false;
    _appleSync = enabled;
    await _settings.set(appleSyncKey, '$enabled');
    notifyListeners();
    if (enabled) {
      for (final task in await _tasks.all()) {
        if (task.remindAt != null) await _syncApple(task);
      }
    }
    return true;
  }

  Future<void> _reconcile(List<QuickTask> list) async {
    final next = {for (final t in list) t.id: _TaskState.of(t)};
    final previous = _known;
    _known = next;

    if (previous == null) {
      // Al arrancar se reprograman los avisos pendientes; Recordatorios sólo se toca cuando algo cambia.
      for (final task in list) {
        await _syncNotification(task);
      }
      return;
    }
    for (final task in list) {
      if (previous[task.id] == next[task.id]) continue;
      await _syncNotification(task);
      if (_appleSync) await _syncApple(task);
    }
    for (final entry in previous.entries) {
      if (next.containsKey(entry.key)) continue;
      await _platform.cancel([notificationId(entry.key)]);
      final appleId = entry.value.appleId;
      if (_appleSync && appleId != null)
        await _platform.deleteReminder(appleId);
    }
  }

  Future<void> _syncNotification(QuickTask task) async {
    final at = task.remindAt;
    if (task.done || at == null || !at.isAfter(_clock())) {
      await _platform.cancel([notificationId(task.id)]);
      return;
    }
    await _platform.schedule(
      id: notificationId(task.id),
      title: task.title,
      body: task.detail.isEmpty ? 'Recordatorio de KRAFT' : task.detail,
      at: at,
    );
  }

  Future<void> _syncApple(QuickTask task) async {
    final appleId = task.appleReminderId;
    if (task.remindAt == null) {
      if (appleId != null) {
        await _platform.deleteReminder(appleId);
        await _tasks.setAppleReminderId(task.id, null);
      }
      return;
    }
    final saved = await _platform.saveReminder(
      identifier: appleId,
      title: task.title,
      notes: task.detail,
      at: task.remindAt,
      done: task.done,
    );
    if (saved != null && saved != appleId)
      await _tasks.setAppleReminderId(task.id, saved);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

/// Lo que importa para avisar; el identificador de Apple se guarda aparte para no provocar bucles.
@immutable
class _TaskState {
  const _TaskState(
    this.title,
    this.detail,
    this.remindAt,
    this.done,
    this.appleId,
  );

  factory _TaskState.of(QuickTask t) =>
      _TaskState(t.title, t.detail, t.remindAt, t.done, t.appleReminderId);

  final String title;
  final String detail;
  final DateTime? remindAt;
  final bool done;
  final String? appleId;

  @override
  bool operator ==(Object other) =>
      other is _TaskState &&
      other.title == title &&
      other.detail == detail &&
      other.remindAt == remindAt &&
      other.done == done;

  @override
  int get hashCode => Object.hash(title, detail, remindAt, done);
}
