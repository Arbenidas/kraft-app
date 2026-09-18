import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kraft/data/db/database.dart';
import 'package:kraft/data/repositories.dart';
import 'package:kraft/features/reminders/reminder_field.dart';
import 'package:kraft/features/reminders/reminder_service.dart';
import 'package:kraft/platform/reminders.dart';

class _FakePlatform implements ReminderPlatform {
  final calls = <String>[];
  final scheduled = <String, DateTime>{};
  bool remindersGranted = true;
  var _nextApple = 0;

  @override
  Future<bool> authorizeNotifications() async => true;

  @override
  Future<void> schedule({required String id, required String title, required String body, required DateTime at}) async {
    calls.add('schedule $id $title');
    scheduled[id] = at;
  }

  @override
  Future<void> cancel(List<String> ids) async {
    calls.add('cancel ${ids.join(',')}');
    ids.forEach(scheduled.remove);
  }

  @override
  Future<bool> authorizeReminders() async => remindersGranted;

  @override
  Future<String?> saveReminder({String? identifier, required String title, String notes = '', DateTime? at, bool done = false}) async {
    calls.add('apple ${identifier ?? 'new'} $title done=$done');
    return identifier ?? 'apple-${++_nextApple}';
  }

  @override
  Future<void> deleteReminder(String identifier) async => calls.add('apple-delete $identifier');
}

void main() {
  late AppDatabase db;
  late TasksRepository tasks;
  late _FakePlatform platform;
  late ReminderService service;
  final now = DateTime(2026, 9, 15, 10);

  Future<void> flush() => Future<void>.delayed(const Duration(milliseconds: 30));

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), seed: false);
    tasks = TasksRepository(db);
    platform = _FakePlatform();
    service = ReminderService(tasks: tasks, settings: SettingsRepository(db), platform: platform, clock: () => now);
    await service.start();
    await flush();
  });

  tearDown(() async {
    service.dispose();
    await db.close();
  });

  test('programar al crear, reprogramar al cambiar y cancelar al completar o borrar', () async {
    final id = await tasks.create(title: 'Llamar al cliente', remindAt: now.add(const Duration(hours: 2)));
    await flush();
    expect(platform.scheduled[ReminderService.notificationId(id)], now.add(const Duration(hours: 2)));

    final task = (await tasks.get(id))!;
    await tasks.update(task.copyWith(title: 'Llamar a Ana'));
    await flush();
    expect(platform.calls.last, 'schedule task-$id Llamar a Ana');

    await tasks.setDone((await tasks.get(id))!, true);
    await flush();
    expect(platform.scheduled, isEmpty);

    await tasks.delete(id);
    await flush();
    expect(platform.calls.last, 'cancel task-$id');
  });

  test('un recordatorio en el pasado no se programa', () async {
    await tasks.create(title: 'Ayer', remindAt: now.subtract(const Duration(hours: 1)));
    await flush();
    expect(platform.scheduled, isEmpty);
  });

  test('con Recordatorios de Apple guarda el identificador y lo borra con la tarea', () async {
    expect(await service.setAppleSync(true), isTrue);
    final id = await tasks.create(title: 'Comprar lápices', remindAt: now.add(const Duration(days: 1)));
    await flush();
    await flush();
    expect((await tasks.get(id))!.appleReminderId, 'apple-1');
    expect(platform.calls.where((c) => c.startsWith('apple ')), hasLength(1), reason: 'guardar el id no vuelve a sincronizar');

    await tasks.setDone((await tasks.get(id))!, true);
    await flush();
    expect(platform.calls.last, 'apple apple-1 Comprar lápices done=true');

    await tasks.delete(id);
    await flush();
    expect(platform.calls.last, 'apple-delete apple-1');
  });

  test('sin permiso de Recordatorios no se activa la sincronización', () async {
    platform.remindersGranted = false;
    expect(await service.setAppleSync(true), isFalse);
    expect(service.appleSync, isFalse);
  });

  test('etiqueta legible del recordatorio', () {
    expect(reminderLabel(DateTime(2026, 9, 15, 18), now: now), 'Hoy · 18:00');
    expect(reminderLabel(DateTime(2026, 9, 16, 9), now: now), 'Mañana · 09:00');
    expect(reminderLabel(DateTime(2026, 9, 18, 10, 30), now: now), 'Viernes, 18 Septiembre · 10:30');
  });
}
