import 'dart:convert';

import 'package:drift/drift.dart';

import '../enums.dart';

class Projects extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 120)();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get kind => textEnum<ProjectKind>()();
  TextColumn get tags =>
      text().map(const TagsConverter()).withDefault(const Constant('[]'))();

  /// Miniatura empaquetada en la app; `null` usa la portada generada.
  TextColumn get imageAsset => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class Notes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get projectId => integer().nullable().references(
    Projects,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get title => text().withDefault(const Constant(''))();

  /// Texto del bloque "Idea central"; vacío oculta el bloque.
  TextColumn get keyIdea => text().withDefault(const Constant(''))();

  /// Texto plano de la nota (para buscar y para la vista previa). Se deriva de [content].
  TextColumn get body => text().withDefault(const Constant(''))();

  /// Página de la nota: bloques de texto, dibujos, diagramas y enlaces (JSON de `CanvasCodec`).
  /// Vacío en notas antiguas: se convierten desde título, idea central, texto y checklist al abrirlas.
  TextColumn get content => text().withDefault(const Constant(''))();
  TextColumn get category => textEnum<NoteCategory>()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class ChecklistItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get noteId =>
      integer().references(Notes, #id, onDelete: KeyAction.cascade)();
  TextColumn get content => text()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  IntColumn get position => integer()();
}

@DataClassName('QuickTask')
class Tasks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 200)();

  /// Contexto corto ("Pendiente para la tarde").
  TextColumn get detail => text().withDefault(const Constant(''))();
  TextColumn get label => text().nullable()();
  BoolColumn get highPriority => boolean().withDefault(const Constant(false))();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Cuándo avisar con una notificación; `null` sin recordatorio.
  DateTimeColumn get remindAt => dateTime().nullable()();

  /// Identificador del recordatorio creado en la app Recordatorios de Apple (si se sincroniza).
  TextColumn get appleReminderId => text().nullable()();

  IntColumn get projectId => integer().nullable().references(
    Projects,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// Un requerimiento puede reunir tareas ya existentes sin duplicarlas.
  IntColumn get requirementId => integer().nullable().references(
    WorkItems,
    #id,
    onDelete: KeyAction.setNull,
  )();
}

@DataClassName('CalendarEvent')
class Events extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 160)();
  TextColumn get detail => text().withDefault(const Constant(''))();
  DateTimeColumn get startsAt => dateTime()();
  TextColumn get tag => textEnum<EventTag>()();
  IntColumn get projectId => integer().nullable().references(
    Projects,
    #id,
    onDelete: KeyAction.setNull,
  )();
}

/// Lienzo guardado: el contenido va serializado en [data] (ver `CanvasCodec`).
@DataClassName('CanvasRecord')
class Canvases extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 120)();
  TextColumn get data => text().withDefault(const Constant(''))();
  IntColumn get projectId => integer().nullable().references(
    Projects,
    #id,
    onDelete: KeyAction.setNull,
  )();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Preferencias clave-valor de la app (p. ej. el servidor MCP).
@DataClassName('SettingRecord')
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

class TagsConverter extends TypeConverter<List<String>, String> {
  const TagsConverter();

  @override
  List<String> fromSql(String fromDb) =>
      (jsonDecode(fromDb) as List).cast<String>();

  @override
  String toSql(List<String> value) => jsonEncode(value);
}

/// Activities and requirements share project ownership and can be decomposed.
class WorkItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get projectId =>
      integer().references(Projects, #id, onDelete: KeyAction.cascade)();
  IntColumn get parentId => integer().nullable().references(
    WorkItems,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get acceptance => text().withDefault(const Constant(''))();
  TextColumn get kind => text().withDefault(const Constant('activity'))();
  TextColumn get status => text().withDefault(const Constant('todo'))();

  /// Columna del tablero. El estado legacy se conserva para actividades y
  /// compatibilidad de las herramientas anteriores.
  IntColumn get columnId => integer().nullable().references(
    RequirementColumns,
    #id,
    onDelete: KeyAction.setNull,
  )();
  IntColumn get position => integer().withDefault(const Constant(0))();
  TextColumn get labels =>
      text().map(const TagsConverter()).withDefault(const Constant('[]'))();
  TextColumn get priority => text().withDefault(const Constant('normal'))();
  DateTimeColumn get dueAt => dateTime().nullable()();

  /// Fecha civil para vencimientos de todo el día. Es excluyente con [dueAt].
  TextColumn get dueDay => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Estados configurables por proyecto para los requerimientos.
class RequirementColumns extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get projectId =>
      integer().references(Projects, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text().withLength(min: 1, max: 80)();
  TextColumn get color => text().withDefault(const Constant('#6C8CFF'))();

  /// Semántica estable para métricas, calendario y compatibilidad.
  TextColumn get category => text().withDefault(const Constant('todo'))();
  IntColumn get position => integer().withDefault(const Constant(0))();
}

/// Actividades planificadas vinculables a un requerimiento, sin confundirlas
/// con el registro de seguimiento.
class WorkItemLinks extends Table {
  IntColumn get workItemId =>
      integer().references(WorkItems, #id, onDelete: KeyAction.cascade)();
  IntColumn get requirementId =>
      integer().references(WorkItems, #id, onDelete: KeyAction.cascade)();
  @override
  Set<Column> get primaryKey => {workItemId, requirementId};
}

/// Registro append-only de cambios y comentarios del requerimiento.
class RequirementHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get requirementId =>
      integer().references(WorkItems, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => text().withDefault(const Constant('comment'))();
  TextColumn get message => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
