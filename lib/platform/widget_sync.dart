import 'dart:async';
import 'package:flutter/services.dart';
import '../data/db/database.dart';

/// Puente mínimo hacia el App Group que comparten los widgets de Apple. Si la
/// extensión todavía no está instalada (por ejemplo en tests), no afecta la app.
abstract final class WidgetSync {
  static const _channel = MethodChannel('kraft/widgets');

  static Future<void> sync({
    required List<QuickTask> tasks,
    required List<WorkItem> work,
  }) async {
    final pending = <Map<String, Object?>>[
      for (final task in tasks.where((task) => !task.done).take(8))
        {'id': 'task-${task.id}', 'title': task.title, 'kind': 'Tarea'},
      for (final item in work.where((item) => item.status != 'done').take(8))
        {
          'id': 'work-${item.id}',
          'title': item.title,
          'kind': item.kind == 'requirement' ? 'Requerimiento' : 'Actividad',
        },
    ].take(8).toList();
    try {
      await _channel.invokeMethod<void>('syncPending', {'items': pending});
    } on MissingPluginException {
      /* plataforma no Apple/test */
    }
  }

  static void registerCaptureHandler(Future<void> Function() handler) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'capture') await handler();
    });
  }
}
