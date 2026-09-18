import 'dart:math' as math;
import 'package:drift/drift.dart' show Value;
import 'dart:ui' show Offset, Rect;

import 'package:flutter/foundation.dart';

import '../../data/db/database.dart';
import '../../data/enums.dart';
import '../../data/repositories.dart';
import '../ai/canvas_bridge.dart';
import '../ai/canvas_tools.dart';
import '../canvas/canvas_codec.dart';
import '../canvas/canvas_models.dart';
import '../notes/note_bridge.dart';
import '../notes/note_document.dart';
import '../notes/note_sketch_model.dart';
import '../notes/note_text.dart';
import '../../utils/dates.dart';
import '../../utils/text_match.dart';
import '../reminders/reminder_field.dart';

/// Algo que hizo el asistente, para enseñarlo en el panel (con acceso directo si se puede abrir).
@immutable
class AssistantAction {
  const AssistantAction(this.label, {this.open, this.explanation});

  final String label;
  final Future<void> Function()? open;
  final GuidedExplanation? explanation;
}

enum ExplanationTarget { canvas, note }

@immutable
class ExplanationStep {
  const ExplanationStep({required this.focus, required this.narration});

  /// Id del elemento del lienzo o frase exacta de la nota.
  final String focus;
  final String narration;
}

@immutable
class GuidedExplanation {
  const GuidedExplanation({
    required this.target,
    required this.documentId,
    required this.steps,
  });

  final ExplanationTarget target;
  final int documentId;
  final List<ExplanationStep> steps;
}

/// Herramientas del asistente de voz: notas, recordatorios y lienzos.
class AssistantTools {
  AssistantTools({
    required this.notes,
    required this.tasks,
    this.projects,
    this.workItems,
    required this.noteBridge,
    required this.canvasBridge,
    required this.canvasTools,
    this.openViewHandler,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final NotesRepository notes;
  final TasksRepository tasks;
  final ProjectsRepository? projects;
  final WorkItemsRepository? workItems;
  final NoteBridge noteBridge;
  final CanvasBridge canvasBridge;
  final KraftCanvasTools canvasTools;

  /// Navega a una vista de KRAFT. [requirementId] abre el tablero y el detalle de ese requerimiento.
  Future<void> Function(String view, int? projectId, {int? requirementId})?
  openViewHandler;
  final DateTime Function() _clock;

  /// Herramientas de lienzo que tienen sentido por voz.
  static const _canvasToolNames = {
    'list_canvases',
    'get_canvas',
    'create_canvas',
    'open_canvas',
    'create_diagram',
    'edit_diagram',
    'add_elements',
    'update_element',
    'connect_elements',
    'delete_elements',
    'draw_sketch',
  };

  static const Map<String, Object?> _tasksSchema = {
    'type': 'array',
    'items': {'type': 'string'},
    'description':
        'Tareas pendientes, una por elemento (se muestran como casillas).',
  };

  /// Las herramientas imprescindibles, para modelos con poco contexto (Gemma en el iPad).
  /// Incluye `list_canvases`, `create_canvas` y `open_canvas` a propósito: sin ellas, cuando no hay
  /// lienzo abierto el modelo recibe un error que le pide crearlo y no tiene con qué, así que
  /// sólo le queda preguntar al usuario.
  static const coreToolNames = {
    'review_artifact',
    'create_project',
    'list_project_work',
    'get_requirement',
    'save_project_work',
    'save_task',
    'save_tasks',
    'open_requirement',
    'delete_work',
    'search_workspace',
    'create_note',
    'append_to_note',
    'replace_note_text',
    'sketch_note',
    'create_reminder',
    'list_reminders',
    'list_canvases',
    'create_canvas',
    'open_canvas',
    'open_view',
    'close_view',
    'get_canvas',
    'create_diagram',
    'edit_diagram',
    'read_note',
    'explain_canvas',
    'explain_note',
  };

  /// Versión reducida: sólo lo esencial, descripciones cortas y sin listas de opciones largas.
  /// Un modelo local no tiene sitio para el catálogo entero.
  List<Map<String, Object?>> get compactDefinitions => [
    for (final tool in definitions)
      if (coreToolNames.contains(tool['name'])) _shrink(tool),
  ];

  static Map<String, Object?> _shrink(Map<String, Object?> tool) {
    // La navegación debe seguir disponible en los modelos locales, pero su
    // catálogo completo desperdicia contexto en instrucciones que el modelo
    // grande sí aprovecha. Conservamos los destinos y el identificador.
    if (tool['name'] == 'open_view') {
      return {
        'name': 'open_view',
        'description': 'Navega por KRAFT.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'view': {
              'type': 'string',
              'enum': [
                'home',
                'calendar',
                'projects',
                'project',
                'requirement',
                'notes',
                'canvases',
                'graph',
                'settings',
              ],
            },
            'project_id': {'type': 'integer'},
            'requirement_id': {'type': 'integer'},
          },
          'required': ['view'],
        },
      };
    }

    return {
      for (final MapEntry(:key, :value) in tool.entries)
        if (key != 'annotations' && key != 'title')
          key: switch (key) {
            'description' => _short('$value', 68),
            'inputSchema' => _shrinkSchema(
              (value! as Map).cast<String, Object?>(),
            ),
            _ => value,
          },
    };
  }

  /// Listas de nodos y conexiones: es donde el esquema se repite y se dispara de tamaño.
  static const _nodeLists = {
    'nodes',
    'add_nodes',
    'update_nodes',
    'elements',
    'edges',
    'add_edges',
    'connections',
  };

  /// Acabados que un modelo local no va a usar bien (colores, iconos, posiciones a mano).
  /// Quitarlos de los nodos deja sitio para describir lo que sí importa.
  static const _trimmedFromNodes = {
    'icon',
    'color',
    'size',
    'scale',
    'active',
    'x',
    'y',
    'style',
    'arrow',
  };

  /// Se recortan las descripciones de los parámetros, pero no se borran: sin ellas el modelo
  /// local sólo ve `remind_at: string` y no puede adivinar que espera una fecha ISO.
  static Map<String, Object?> _shrinkSchema(
    Map<String, Object?> schema, {
    bool inNodes = false,
  }) => {
    for (final MapEntry(:key, :value) in schema.entries)
      if (!(key == 'enum' && (value! as List).length > 8))
        key: switch (key) {
          'description' => _short('$value', 80),
          'items' => _shrinkSchema(
            (value! as Map).cast<String, Object?>(),
            inNodes: inNodes,
          ),
          'properties' => {
            for (final MapEntry(key: name, value: sub)
                in (value! as Map).cast<String, Object?>().entries)
              if (!(inNodes && _trimmedFromNodes.contains(name)))
                name: _shrinkSchema(
                  (sub! as Map).cast<String, Object?>(),
                  inNodes: inNodes || _nodeLists.contains(name),
                ),
          },
          _ => value,
        },
  };

  static String _short(String text, [int limit = 110]) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.length <= limit) return clean;
    final cut = clean.substring(0, limit);
    final stop = cut.lastIndexOf('. ');
    return stop > 40 ? cut.substring(0, stop + 1) : '$cut…';
  }

  List<Map<String, Object?>> get definitions => [
    {
      'name': 'review_artifact',
      'description':
          'Relee y revisa una nota, lienzo o proyecto. Devuelve errores y advertencias estructurales para corregir.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'kind': {
            'type': 'string',
            'enum': ['note', 'canvas', 'project'],
          },
          'id': {'type': 'integer'},
        },
        'required': ['kind', 'id'],
      },
      'annotations': {'readOnlyHint': true},
    },
    if (workItems != null) ...[
      {
        'name': 'create_project',
        'description':
            'Crea un proyecto nuevo y devuelve project_id. Úsalo antes de crear requisitos, actividades, notas o lienzos para un proyecto que aún no existe.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'title': {'type': 'string'},
            'description': {'type': 'string'},
            'kind': {
              'type': 'string',
              'enum': [for (final kind in ProjectKind.values) kind.name],
              'description': 'lienzo, stylus o nota; si se omite, lienzo.',
            },
            'tags': {
              'type': 'array',
              'items': {'type': 'string'},
            },
          },
          'required': ['title'],
        },
      },
      {
        'name': 'list_project_work',
        'description':
            'Lista proyectos y sus actividades o requerimientos persistidos. Usa sus ids antes de crear o desglosar.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'project_id': {'type': 'integer'},
          },
        },
      },
      {
        'name': 'save_project_work',
        'description':
            'Crea o actualiza una actividad o requerimiento. status todo/doing/done mueve el tablero a Por hacer, En curso o Terminado. parent_id desglosa. No inventes fechas ni uses acceptance como lista de tareas.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'id': {
              'type': 'integer',
              'description': 'Solo para actualizar un elemento existente.',
            },
            'project_id': {'type': 'integer'},
            'parent_id': {'type': 'integer'},
            'title': {
              'type': 'string',
              'description':
                  'Obligatorio al crear; al actualizar se puede omitir.',
            },
            'description': {'type': 'string'},
            'acceptance': {
              'type': 'string',
              'description':
                  'Criterios verificables de aceptación, no las casillas de tarea.',
            },
            'kind': {
              'type': 'string',
              'enum': ['activity', 'requirement'],
            },
            'status': {
              'type': 'string',
              'enum': ['todo', 'doing', 'done'],
              'description':
                  'todo = Por hacer, doing = En curso, done = Terminado.',
            },
            'due_at': {
              'type': 'string',
              'description': 'Fecha ISO 8601, omitir si no se conoce.',
            },
          },
          'required': ['project_id', 'kind'],
        },
      },
      {
        'name': 'save_task',
        'description':
            'Crea o actualiza una tarea-casilla. Para un requerimiento pasa requirement_id. Con id y done=true la marca hecha. No sustituyas esto con criterios de aceptación.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'id': {
              'type': 'integer',
              'description':
                  'Solo para actualizar o completar una tarea existente.',
            },
            'project_id': {'type': 'integer'},
            'requirement_id': {
              'type': 'integer',
              'description': 'Requerimiento al que pertenece la casilla.',
            },
            'title': {'type': 'string', 'description': 'Obligatorio al crear.'},
            'detail': {'type': 'string'},
            'done': {
              'type': 'boolean',
              'description': 'true la marca terminada.',
            },
          },
        },
      },
      {
        'name': 'get_requirement',
        'description':
            'Lee un requerimiento y sus tareas-casilla. Úsalo antes de editar, listar tareas o profundizar.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'requirement_id': {
              'type': 'integer',
              'description': 'Id del requerimiento (REQ-n).',
            },
          },
          'required': ['requirement_id'],
        },
      },
      {
        'name': 'save_tasks',
        'description':
            'Crea varias tareas-casilla de un requerimiento de un golpe. No las pongas en acceptance.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'requirement_id': {'type': 'integer'},
            'titles': {
              'type': 'array',
              'items': {'type': 'string'},
              'description': 'Títulos de las casillas, en orden.',
            },
          },
          'required': ['requirement_id', 'titles'],
        },
      },
      {
        'name': 'open_requirement',
        'description':
            'Abre el tablero del proyecto y el detalle de un requerimiento.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'requirement_id': {'type': 'integer'},
          },
          'required': ['requirement_id'],
        },
      },
      {
        'name': 'delete_work',
        'description':
            'Borra un requerimiento (y sus casillas) o una tarea. Pasa requirement_id o task_id.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'requirement_id': {'type': 'integer'},
            'task_id': {'type': 'integer'},
          },
        },
      },
    ],
    {
      'name': 'search_workspace',
      'description':
          'Busca en KRAFT (proyectos, notas, tareas, lienzos y diagramas) lo que el usuario nombra de memoria: "mi proyecto de la calculadora", "la nota de la reunión". Devuelve los ids para trabajar con ellos.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'Las palabras que usó el usuario, tal cual.',
          },
        },
        'required': ['query'],
      },
    },
    {
      'name': 'create_note',
      'description':
          'Crea una nota y la abre. title y text son obligatorios: en text va el contenido completo (secciones "## ", ejemplos). No dejes el artículo solo en el chat.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'title': {'type': 'string'},
          'text': {
            'type': 'string',
            'description':
                'El contenido, con saltos de línea. Una línea que empieza por "## " es un título de sección; '
                'una que empieza por "☐ " es una tarea con casilla. Úsalo para dar estructura: varias secciones, '
                'y dentro párrafos con explicaciones y ejemplos adecuados al objetivo.',
          },
          'tasks': _tasksSchema,
          'project_id': {
            'type': 'integer',
            'description': 'Proyecto de destino, si corresponde.',
          },
          'category': {
            'type': 'string',
            'enum': [for (final c in NoteCategory.values) c.name],
            'description': 'idea, reunion o boceto.',
          },
        },
        'required': ['title', 'text'],
      },
    },
    {
      'name': 'append_to_note',
      'description':
          'Añade texto o tareas al final de una nota. Sin note_id usa la nota abierta en pantalla.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'note_id': {'type': 'integer'},
          'text': {'type': 'string'},
          'tasks': _tasksSchema,
        },
      },
    },
    {
      'name': 'replace_note_text',
      'description':
          'Reescribe el texto de una nota existente sin perder dibujos, enlaces ni bocetos. Primero usa read_note y pasa exactamente el texto leído en expected_text. Si alguien editó la nota mientras trabajabas, guarda una propuesta en vez de sobrescribir.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'note_id': {'type': 'integer'},
          'expected_text': {'type': 'string'},
          'text': {'type': 'string'},
        },
        'required': ['note_id', 'expected_text', 'text'],
      },
    },
    {
      'name': 'sketch_note',
      'description':
          'Dibuja en una nota. Para un boceto o pequeño diagrama usa embedded=true: se guarda en un recuadro independiente. Para subrayar sobre el texto usa embedded=false. Sin note_id usa la nota abierta.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'note_id': {'type': 'integer'},
          'embedded': {
            'type': 'boolean',
            'description':
                'true para un boceto en un recuadro propio de la nota.',
          },
          'strokes': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'points': {
                  'type': 'array',
                  'description':
                      'Puntos [[x, y], …] de 0 a 100. Un trazo por línea continua.',
                  'items': {
                    'type': 'array',
                    'items': {'type': 'number'},
                  },
                },
                'color': {
                  'type': 'string',
                  'description':
                      'negro, amarillo, verde, azul, rojo o #RRGGBB.',
                },
                'width': {
                  'type': 'number',
                  'description': 'Grosor en puntos (2–8).',
                },
              },
              'required': ['points'],
            },
          },
          'size': {
            'type': 'number',
            'description':
                'Lado del dibujo en la página, 80–724 (por defecto 320).',
          },
          'x': {
            'type': 'number',
            'description':
                'Esquina del dibujo en la página. Sin x e y va debajo de lo escrito.',
          },
          'y': {'type': 'number'},
        },
        'required': ['strokes'],
      },
    },
    {
      'name': 'find_notes',
      'description':
          'Busca notas por texto. Sin query devuelve las más recientes.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
        },
      },
    },
    {
      'name': 'read_note',
      'description': 'Lee el contenido completo de una nota.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'note_id': {'type': 'integer'},
        },
        'required': ['note_id'],
      },
    },
    {
      'name': 'focus_note_text',
      'description':
          'Señala una frase de la nota abierta antes de explicarla en voz. Usa una frase exacta que venga de read_note; no modifica la nota.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'note_id': {'type': 'integer'},
          'phrase': {
            'type': 'string',
            'description': 'Frase exacta y breve a seleccionar.',
          },
        },
        'required': ['note_id', 'phrase'],
      },
      'annotations': {'readOnlyHint': true},
    },
    {
      'name': 'open_note',
      'description': 'Abre una nota en pantalla.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'note_id': {'type': 'integer'},
        },
        'required': ['note_id'],
      },
    },
    {
      'name': 'open_view',
      'description':
          'Abre una vista principal de KRAFT. Úsala cuando el usuario diga “ve a”, “muéstrame” o “abre” una sección. Para un proyecto usa view=project y project_id.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'view': {
            'type': 'string',
            'enum': [
              'home',
              'calendar',
              'projects',
              'project',
              'notes',
              'canvases',
              'graph',
              'settings',
            ],
          },
          'project_id': {
            'type': 'integer',
            'description': 'Obligatorio sólo cuando view=project.',
          },
          'requirement_id': {
            'type': 'integer',
            'description': 'Si se pasa, abre ese requerimiento en el tablero.',
          },
        },
        'required': ['view'],
      },
      'annotations': {'readOnlyHint': true},
    },
    {
      'name': 'close_view',
      'description':
          'Cierra la ventana modal o vista abierta en KRAFT. Úsala cuando el usuario pida cerrar la pestaña, detalle o requerimiento actual.',
      'inputSchema': {'type': 'object', 'properties': {}},
    },
    {
      'name': 'create_reminder',
      'description':
          'Crea una tarea y, si hay fecha u hora, un recordatorio con notificación en el iPad. Interpreta "mañana a las 9" con la fecha actual.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'title': {'type': 'string'},
          'remind_at': {
            'type': 'string',
            'description':
                'Fecha y hora local ISO 8601, p. ej. 2026-09-16T09:00:00.',
          },
          'detail': {'type': 'string'},
          'high_priority': {'type': 'boolean'},
          'project_id': {'type': 'integer'},
          'requirement_id': {
            'type': 'integer',
            'description': 'Si la tarea pertenece a un requerimiento.',
          },
        },
        'required': ['title'],
      },
    },
    {
      'name': 'list_reminders',
      'description': 'Lista las tareas pendientes con su recordatorio.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'include_done': {'type': 'boolean'},
        },
      },
    },
    {
      'name': 'complete_reminder',
      'description':
          'Marca una tarea o recordatorio como hecha. Usa el task_id de list_project_work, save_task o list_reminders.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'task_id': {'type': 'integer'},
        },
        'required': ['task_id'],
      },
    },
    for (final tool in canvasTools.definitions)
      if (_canvasToolNames.contains(tool['name'])) tool,
    {
      'name': 'focus_canvas_item',
      'description':
          'Selecciona y centra un elemento del lienzo abierto antes de explicar ese paso. Usa element_id que devolvió get_canvas; no modifica el diagrama.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'canvas_id': {'type': 'integer'},
          'element_id': {'type': 'string'},
        },
        'required': ['element_id'],
      },
      'annotations': {'readOnlyHint': true},
    },
    {
      'name': 'explain_canvas',
      'description':
          'Prepara una explicación guiada del lienzo: KRAFT enfocará cada elemento y leerá su explicación en voz, en el orden indicado. Usa ids de get_canvas.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'canvas_id': {'type': 'integer'},
          'steps': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'element_id': {'type': 'string'},
                'explanation': {
                  'type': 'string',
                  'description':
                      'Una o dos frases naturales para decir en voz.',
                },
              },
              'required': ['element_id', 'explanation'],
            },
          },
        },
        'required': ['steps'],
      },
      'annotations': {'readOnlyHint': true},
    },
    {
      'name': 'explain_note',
      'description':
          'Prepara una explicación guiada de una nota: KRAFT seleccionará cada frase y leerá su explicación en voz.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'note_id': {'type': 'integer'},
          'steps': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'phrase': {
                  'type': 'string',
                  'description': 'Frase exacta de read_note.',
                },
                'explanation': {
                  'type': 'string',
                  'description': 'Una o dos frases para decir en voz.',
                },
              },
              'required': ['phrase', 'explanation'],
            },
          },
        },
        'required': ['note_id', 'steps'],
      },
      'annotations': {'readOnlyHint': true},
    },
  ];

  /// Ejecuta [name]; devuelve el resultado para la IA y lo que se enseña al usuario.
  Future<(Map<String, Object?>, AssistantAction?)> call(
    String name,
    Map<String, Object?> args,
  ) async {
    try {
      return switch (name) {
        'review_artifact' => (await _reviewArtifact(args), null),
        'create_project' => await _createProject(args),
        'list_project_work' => (await _listProjectWork(args), null),
        'get_requirement' => (await _getRequirement(args), null),
        'save_project_work' => await _saveProjectWork(args),
        'save_task' => await _saveTask(args),
        'save_tasks' => await _saveTasks(args),
        'open_requirement' => await _openRequirement(args),
        'delete_work' => await _deleteWork(args),
        'search_workspace' => (await _searchWorkspace(args), null),
        'create_note' => await _createNote(args),
        'append_to_note' => await _appendToNote(args),
        'replace_note_text' => await _replaceNoteText(args),
        'sketch_note' => await _sketchNote(args),
        'find_notes' => (await _findNotes(args), null),
        'read_note' => (await _readNote(args), null),
        'focus_note_text' => await _focusNoteText(args),
        'open_note' => await _openNote(args),
        'open_view' => await _openView(args),
        'close_view' => await _closeView(),
        'create_reminder' => await _createReminder(args),
        'list_reminders' => (await _listReminders(args), null),
        'complete_reminder' => await _completeReminder(args),
        'focus_canvas_item' => await _focusCanvasItem(args),
        'explain_canvas' => await _explainCanvas(args),
        'explain_note' => await _explainNote(args),
        _ when _canvasToolNames.contains(name) => await _canvas(name, args),
        _ => throw McpToolError('Herramienta desconocida: $name'),
      };
    } on McpToolError catch (e) {
      return (<String, Object?>{'error': e.message}, null);
    } on ArgumentError {
      return (
        {
          'error':
              'Parámetros inválidos. Revisa el esquema y los identificadores.',
        },
        null,
      );
    } on TypeError {
      return (
        {
          'error':
              'Tipos de parámetros incorrectos. Usa números para ids y cadenas para texto.',
        },
        null,
      );
    } on FormatException {
      return (
        {'error': 'Formato inválido. Corrige los parámetros según el esquema.'},
        null,
      );
    }
  }

  Future<Map<String, Object?>> _reviewArtifact(
    Map<String, Object?> args,
  ) async {
    final id = _int(args['id']) ?? (throw const McpToolError('Falta id.'));
    final kind = args['kind'];
    final errors = <String>[];
    final warnings = <String>[];
    var count = 0;
    switch (kind) {
      case 'note':
        final note = await _readNote({'note_id': id});
        final text = (note['text'] as String? ?? '').trim();
        count = text.isEmpty ? 0 : text.split(RegExp(r'\s+')).length;
        final live = noteBridge.live;
        final record = await notes.get(id);
        final document = record == null
            ? const NoteDocument()
            : NoteDocument.decode(record.content, legacy: record);
        final hasDrawing =
            (live != null &&
                live.noteId == id &&
                live.noteStrokes.isNotEmpty) ||
            document.strokes.isNotEmpty ||
            document.sketches.any(
              (s) => s.data.items.isNotEmpty || s.data.strokes.isNotEmpty,
            );
        if (text.isEmpty && !hasDrawing) errors.add('La nota está vacía.');
        if (text.isEmpty && hasDrawing)
          warnings.add(
            'Nota visual sin texto. Comprueba que el dibujo cumpla el objetivo.',
          );
        if (text.contains('TODO') || text.contains('[pendiente]'))
          warnings.add('Hay marcadores pendientes en el texto.');
      case 'canvas':
        final data = await canvasTools.call('get_canvas', {'canvas_id': id});
        final elements = (data['elements'] as List).cast<Map>();
        final links = <Map>[
          ...(data['connections'] as List).cast<Map>(),
          ...((data['invalid_connections'] as List?) ?? const []).cast<Map>(),
        ];
        final ids = elements.map((e) => e['id']).toSet();
        count = elements.length;
        if (elements.isEmpty && data['drawings'] == 0)
          errors.add('El lienzo está vacío.');
        for (final e in elements) {
          if (['card', 'step'].contains(e['type']) &&
              '${e['title'] ?? ''}'.trim().isEmpty) {
            warnings.add(
              'El elemento ${e['id']} necesita un título específico.',
            );
          }
        }
        for (final link in links) {
          if (!ids.contains(link['from']) || !ids.contains(link['to']))
            errors.add('Conexión ${link['id']} con un extremo inexistente.');
          if ('${link['label'] ?? ''}'.trim().isEmpty)
            warnings.add(
              'Conexión ${link['id']} sin etiqueta: comprueba que su significado sea claro.',
            );
        }
        if (elements.length > 1 && links.isEmpty)
          warnings.add(
            'No hay conexiones. Comprueba si corresponde a un flujo o arquitectura.',
          );
      case 'project':
        if (projects == null || await projects!.watchOne(id).first == null)
          throw const McpToolError('El proyecto no existe.');
        final data = await _listProjectWork({'project_id': id});
        final items = (data['items'] as List).cast<Map>();
        count = items.length;
        final seen = <String>{};
        for (final item in items) {
          final title = '${item['title']}'.trim().toLowerCase();
          if (!seen.add('${item['kind']}:${item['parent_id']}:$title'))
            warnings.add(
              'Posible duplicado: ${item['title']} (${item['id']}).',
            );
          if ('${item['description']}'.trim().isEmpty)
            warnings.add('Falta descripción en ${item['id']}.');
          if (item['kind'] == 'requirement' &&
              '${item['acceptance']}'.trim().isEmpty)
            warnings.add('Faltan criterios de aceptación en ${item['id']}.');
        }
        if (items.isEmpty)
          warnings.add('El proyecto no tiene actividades ni requerimientos.');
      default:
        throw const McpToolError('kind debe ser note, canvas o project.');
    }
    return {
      'kind': kind,
      'id': id,
      'checked': count,
      'errors': errors.take(20).toList(),
      'warnings': warnings.take(20).toList(),
      'error_count': errors.length,
      'warning_count': warnings.length,
      'structurally_valid': errors.isEmpty,
      'next_step':
          'Relee el contenido y verifica que cumple el objetivo del usuario; esta revisión no valida exactitud semántica.',
    };
  }

  Future<Map<String, Object?>> _listProjectWork(
    Map<String, Object?> args,
  ) async {
    final repo = workItems;
    if (repo == null) throw const McpToolError('Planificación no disponible.');
    final projectId = _int(args['project_id']);
    final projectList = await projects!.watchAll().first;
    final targets = projectId == null
        ? projectList
        : projectList.where((p) => p.id == projectId).toList();
    final columnsByProject = <int, List<RequirementColumn>>{};
    for (final project in targets) {
      columnsByProject[project.id] = await repo.ensureDefaultColumns(
        project.id,
      );
    }
    String? columnTitle(WorkItem item) => columnsByProject[item.projectId]
        ?.where((column) => column.id == item.columnId)
        .firstOrNull
        ?.title;
    return {
      'projects': [
        for (final p in projectList) {'id': p.id, 'title': p.title},
      ],
      'columns': [
        for (final project in targets)
          for (final column in columnsByProject[project.id] ?? const [])
            {
              'id': column.id,
              'project_id': project.id,
              'title': column.title,
              'category': column.category,
            },
      ],
      'items': [
        for (final w in await repo.watchAll(projectId: projectId).first)
          {
            'id': w.id,
            'project_id': w.projectId,
            'parent_id': w.parentId,
            'kind': w.kind,
            'title': w.title,
            'description': w.description,
            'acceptance': w.acceptance,
            'status': w.status,
            'column_id': w.columnId,
            'column': columnTitle(w),
            'due_at': w.dueAt?.toIso8601String(),
          },
      ],
      'tasks': [
        for (final t in await tasks.watchAll(projectId: projectId).first)
          {
            'id': t.id,
            'task_id': t.id,
            'title': t.title,
            'done': t.done,
            'project_id': t.projectId,
            'requirement_id': t.requirementId,
          },
      ],
    };
  }

  Future<(Map<String, Object?>, AssistantAction?)> _createProject(
    Map<String, Object?> args,
  ) async {
    final repo = projects;
    if (repo == null) throw const McpToolError('Proyectos no disponibles.');
    final title = (args['title'] as String? ?? '').trim();
    if (title.isEmpty)
      throw const McpToolError('Falta el título del proyecto.');
    final kindName = args['kind'] as String? ?? ProjectKind.lienzo.name;
    final kind = ProjectKind.values.asNameMap()[kindName];
    if (kind == null)
      throw const McpToolError('kind debe ser lienzo, stylus o nota.');
    final rawTags = args['tags'];
    final tags = rawTags is List
        ? rawTags
              .whereType<String>()
              .map((tag) => tag.trim())
              .where((tag) => tag.isNotEmpty)
              .take(12)
              .toList()
        : const <String>[];
    final id = await repo.create(
      title: title,
      kind: kind,
      description: (args['description'] as String? ?? '').trim(),
      tags: tags,
    );
    return (
      {'project_id': id, 'title': title, 'kind': kind.name, 'created': true},
      AssistantAction(
        'Proyecto creado: $title',
        open: openViewHandler == null ? null : () => openViewHandler!('project', id),
      ),
    );
  }

  Future<(Map<String, Object?>, AssistantAction?)> _saveProjectWork(
    Map<String, Object?> args,
  ) async {
    final repo = workItems;
    if (repo == null) throw const McpToolError('Planificación no disponible.');
    final projectId = _int(args['project_id']);
    final title = (args['title'] as String? ?? '').trim();
    if (projectId == null) throw const McpToolError('Falta project_id.');
    if (await projects!.watchOne(projectId).first == null)
      throw const McpToolError('El proyecto no existe.');
    final kind = args['kind'] as String? ?? 'activity';
    final date = args['due_at'] == null
        ? null
        : DateTime.tryParse('${args['due_at']}');
    if (args['due_at'] != null && date == null)
      throw const McpToolError('due_at debe ser una fecha ISO válida.');
    var id = _int(args['id']);
    try {
      if (id == null) {
        if (title.isEmpty) throw const McpToolError('Falta el título.');
        id = await repo.create(
          projectId: projectId,
          title: title,
          kind: kind,
          description: args['description'] as String? ?? '',
          acceptance: args['acceptance'] as String? ?? '',
          parentId: _int(args['parent_id']),
          dueAt: date,
          status: args['status'] as String? ?? 'todo',
        );
      } else {
        final old = await repo.get(id);
        if (old == null || old.projectId != projectId || old.kind != kind)
          throw const McpToolError('Elemento o proyecto incorrecto.');
        await repo.update(
          old.copyWith(
            title: title.isEmpty ? old.title : title,
            description: args['description'] as String?,
            acceptance: args['acceptance'] as String?,
            status: args['status'] as String?,
            dueAt: args.containsKey('due_at')
                ? Value(date)
                : const Value.absent(),
          ),
        );
      }
    } on ArgumentError catch (e) {
      throw McpToolError('$e');
    }
    final saved = await repo.get(id);
    final isRequirement = kind == 'requirement';
    return (
      {
        'id': id,
        'project_id': projectId,
        'saved': true,
        'status': saved?.status,
        'column_id': saved?.columnId,
      },
      AssistantAction(
        isRequirement
            ? 'Requerimiento guardado: ${saved?.title ?? title}'
            : 'Actividad guardada: ${saved?.title ?? title}',
        open: openViewHandler == null
            ? null
            : () => openViewHandler!(
                  isRequirement ? 'requirements' : 'activities',
                  projectId,
                  requirementId: id,
                ),
      ),
    );
  }

  Future<(Map<String, Object?>, AssistantAction?)> _saveTask(
    Map<String, Object?> args,
  ) async {
    final id = _int(args['id']) ?? _int(args['task_id']);
    final title = (args['title'] as String? ?? '').trim();
    var projectId = _int(args['project_id']);
    final requirementId = _int(args['requirement_id']);
    if (requirementId != null) {
      final repo = workItems;
      if (repo == null)
        throw const McpToolError('Planificación no disponible.');
      final requirement = await repo.get(requirementId);
      if (requirement == null || requirement.kind != 'requirement') {
        throw const McpToolError('El requerimiento no existe.');
      }
      projectId ??= requirement.projectId;
      if (projectId != requirement.projectId) {
        throw const McpToolError(
          'La tarea debe ser del mismo proyecto que el requerimiento.',
        );
      }
    }
    if (projectId != null &&
        (projects == null ||
            await projects!.watchOne(projectId).first == null)) {
      throw const McpToolError('El proyecto no existe.');
    }

    if (id != null) {
      final old =
          await tasks.get(id) ??
          (throw McpToolError('No existe la tarea $id.'));
      final next = old.copyWith(
        title: title.isEmpty ? old.title : title,
        detail: args['detail'] is String
            ? args['detail'] as String
            : old.detail,
        projectId: Value(projectId ?? old.projectId),
        requirementId: Value(requirementId ?? old.requirementId),
      );
      if (next != old) await tasks.update(next);
      if (args.containsKey('done')) {
        await tasks.setDone(await tasks.get(id) ?? next, args['done'] == true);
      }
      final saved = await tasks.get(id) ?? next;
      return (
        {
          'id': id,
          'task_id': id,
          'saved': true,
          'done': saved.done,
          'requirement_id': saved.requirementId,
        },
        AssistantAction(
          saved.done ? 'Hecho: ${saved.title}' : 'Tarea: ${saved.title}',
        ),
      );
    }

    if (title.isEmpty) throw const McpToolError('Falta el título de la tarea.');
    final created = await tasks.create(
      title: title,
      detail: args['detail'] as String? ?? '',
      projectId: projectId,
      requirementId: requirementId,
    );
    if (args['done'] == true) {
      final createdTask = await tasks.get(created);
      if (createdTask != null) await tasks.setDone(createdTask, true);
    }
    return (
      {
        'id': created,
        'task_id': created,
        'saved': true,
        'requirement_id': requirementId,
      },
      AssistantAction('Tarea: $title'),
    );
  }

  Future<WorkItem> _requirementOf(int? id) async {
    final repo = workItems;
    if (repo == null) throw const McpToolError('Planificación no disponible.');
    if (id == null) throw const McpToolError('Falta requirement_id.');
    final item = await repo.get(id);
    if (item == null || item.kind != 'requirement') {
      throw const McpToolError('El requerimiento no existe.');
    }
    return item;
  }

  Map<String, Object?> _requirementPayload(WorkItem item) => {
    'id': item.id,
    'requirement_id': item.id,
    'project_id': item.projectId,
    'parent_id': item.parentId,
    'title': item.title,
    'description': item.description,
    'acceptance': item.acceptance,
    'status': item.status,
    'column_id': item.columnId,
    'due_at': item.dueAt?.toIso8601String(),
  };

  Map<String, Object?> _taskPayload(QuickTask task) => {
    'id': task.id,
    'task_id': task.id,
    'title': task.title,
    'detail': task.detail,
    'done': task.done,
    'project_id': task.projectId,
    'requirement_id': task.requirementId,
  };

  Future<Map<String, Object?>> _getRequirement(
    Map<String, Object?> args,
  ) async {
    final item = await _requirementOf(
      _int(args['requirement_id']) ?? _int(args['id']),
    );
    final taskList = [...await tasks.watchForRequirement(item.id).first]
      ..sort((a, b) => a.id.compareTo(b.id));
    return {
      'item': _requirementPayload(item),
      'tasks': [for (final task in taskList) _taskPayload(task)],
    };
  }

  List<String> _taskTitles(Map<String, Object?> args) {
    final titles = args['titles'];
    if (titles is List) {
      return [
        for (final raw in titles)
          if ('$raw'.trim().isNotEmpty) '$raw'.trim(),
      ];
    }
    final tasks = args['tasks'];
    if (tasks is List) {
      return [
        for (final raw in tasks)
          if (raw is Map && '${raw['title'] ?? ''}'.trim().isNotEmpty)
            '${raw['title']}'.trim()
          else if ('$raw'.trim().isNotEmpty)
            '$raw'.trim(),
      ];
    }
    return const [];
  }

  Future<(Map<String, Object?>, AssistantAction?)> _saveTasks(
    Map<String, Object?> args,
  ) async {
    final item = await _requirementOf(_int(args['requirement_id']));
    final titles = _taskTitles(args).take(20).toList();
    if (titles.isEmpty) {
      throw const McpToolError('Pasa titles con al menos una tarea.');
    }
    final created = <Map<String, Object?>>[];
    for (final title in titles) {
      final id = await tasks.create(
        title: title,
        projectId: item.projectId,
        requirementId: item.id,
      );
      created.add({'id': id, 'task_id': id, 'title': title});
    }
    return (
      {
        'saved': true,
        'requirement_id': item.id,
        'project_id': item.projectId,
        'count': created.length,
        'tasks': created,
      },
      AssistantAction(
        created.length == 1
            ? 'Tarea: ${titles.single}'
            : '${created.length} tareas en ${item.title}',
      ),
    );
  }

  Future<(Map<String, Object?>, AssistantAction?)> _openRequirement(
    Map<String, Object?> args,
  ) async {
    final item = await _requirementOf(
      _int(args['requirement_id']) ?? _int(args['id']),
    );
    return _showRequirement(item);
  }

  Future<(Map<String, Object?>, AssistantAction?)> _showRequirement(
    WorkItem item,
  ) async {
    final handler = openViewHandler;
    if (handler == null) {
      throw const McpToolError('KRAFT no puede navegar a vistas ahora mismo.');
    }
    await handler('requirement', item.projectId, requirementId: item.id);
    return (
      {
        'view': 'requirement',
        'project_id': item.projectId,
        'requirement_id': item.id,
      },
      AssistantAction('Abrió: ${item.title}'),
    );
  }

  Future<(Map<String, Object?>, AssistantAction?)> _deleteWork(
    Map<String, Object?> args,
  ) async {
    final requirementId = _int(args['requirement_id']);
    final taskId = _int(args['task_id']);
    if (requirementId != null) {
      final item = await _requirementOf(requirementId);
      final linked = await tasks.watchForRequirement(item.id).first;
      for (final task in linked) {
        await tasks.delete(task.id);
      }
      await workItems!.delete(item.id);
      return (
        {
          'deleted': true,
          'requirement_id': item.id,
          'tasks_removed': linked.length,
        },
        AssistantAction('Borrado: ${item.title}'),
      );
    }
    if (taskId != null) {
      final task =
          await tasks.get(taskId) ??
          (throw McpToolError('No existe la tarea $taskId.'));
      await tasks.delete(task.id);
      return (
        {'deleted': true, 'task_id': task.id},
        AssistantAction('Borrada: ${task.title}'),
      );
    }
    throw const McpToolError('Indica requirement_id o task_id.');
  }

  // ---- Buscar en todo KRAFT ----

  /// Lo que el usuario nombra de memoria casi nunca coincide palabra por palabra con el título:
  /// se puntúa cada nota, tarea, lienzo y diagrama por las palabras que comparten.
  Future<Map<String, Object?>> _searchWorkspace(
    Map<String, Object?> args,
  ) async {
    final query = (args['query'] as String? ?? '').trim();
    if (query.isEmpty) throw const McpToolError('Dime qué buscar.');
    final wanted = keywords(query);
    if (wanted.isEmpty)
      throw McpToolError('"$query" no tiene palabras con las que buscar.');

    final foundProjects = <(double, Map<String, Object?>)>[];
    if (projects != null) {
      for (final project in await projects!.watchAll().first) {
        final hit = score(wanted, '${project.title} ${project.description}');
        if (hit >= 0.5) {
          foundProjects.add((
            hit,
            {
              'project_id': project.id,
              'title': project.title,
              'description': project.description,
            },
          ));
        }
      }
    }

    final foundNotes = <(double, Map<String, Object?>)>[];
    for (final note in await notes.watchAll().first) {
      final hit = math.max(
        score(wanted, note.title) * 1.2,
        score(wanted, note.body),
      );
      if (hit < 0.5) continue;
      foundNotes.add((
        hit,
        {
          'note_id': note.id,
          'title': note.title.isEmpty ? 'Nota sin título' : note.title,
          'preview': note.body.length > 160
              ? '${note.body.substring(0, 160)}…'
              : note.body,
        },
      ));
    }

    final foundTasks = <(double, Map<String, Object?>)>[];
    for (final task in await tasks.all()) {
      final hit = score(wanted, '${task.title} ${task.detail}');
      if (hit < 0.5) continue;
      foundTasks.add((
        hit,
        {
          'task_id': task.id,
          'title': task.title,
          if (task.remindAt != null)
            'remind_at': task.remindAt!.toIso8601String(),
          'done': task.done,
        },
      ));
    }

    final foundCanvases = <(double, Map<String, Object?>)>[];
    for (final record in await canvasTools.canvases.watchAll().first) {
      final data = CanvasCodec.decode(record.data);
      final diagrams = <String, Map<String, Object?>>{};
      var best = score(wanted, record.title) * 1.2;
      final matches = <String>[];
      for (final item in data.items) {
        final text = [item.title, item.subtitle, ...item.bullets].join(' ');
        final hit = score(wanted, text);
        if (hit >= 0.5) {
          best = math.max(best, hit);
          if (item.title.isNotEmpty && matches.length < 6)
            matches.add(item.title);
        }
        // Los diagramas se identifican por su grupo: se anota el título grande de cada uno.
        if (item.group case final group?
            when item.type == CanvasItemType.text) {
          diagrams.putIfAbsent(
            group,
            () => {'diagram': group, 'title': item.title},
          );
        }
      }
      if (best < 0.5) continue;
      foundCanvases.add((
        best,
        {
          'canvas_id': record.id,
          'title': record.title,
          if (diagrams.isNotEmpty) 'diagrams': diagrams.values.toList(),
          if (matches.isNotEmpty) 'matches': matches,
        },
      ));
    }

    List<Map<String, Object?>> top(
      List<(double, Map<String, Object?>)> list,
      int limit,
    ) {
      list.sort((a, b) => b.$1.compareTo(a.$1));
      return [for (final (_, json) in list.take(limit)) json];
    }

    final result = <String, Object?>{
      if (foundProjects.isNotEmpty) 'projects': top(foundProjects, 5),
      if (foundNotes.isNotEmpty) 'notes': top(foundNotes, 5),
      if (foundTasks.isNotEmpty) 'tasks': top(foundTasks, 5),
      if (foundCanvases.isNotEmpty) 'canvases': top(foundCanvases, 5),
    };
    if (result.isEmpty) {
      return {
        'found': false,
        'hint':
            'No hay nada sobre "$query" en KRAFT todavía. Ofrécele crearlo.',
      };
    }
    return result;
  }

  // ---- Notas ----

  static String _compose(Map<String, Object?> args, {String? title}) {
    final text = (args['text'] as String? ?? '').trim();
    final taskLines = [
      for (final t in (args['tasks'] as List? ?? const []))
        '$checkboxOpen ${'$t'.trim()}',
    ];
    return [?title, if (text.isNotEmpty) text, ...taskLines].join('\n');
  }

  Future<int?> _validatedProjectId(Map<String, Object?> args) async {
    if (args['project_id'] == null) return null;
    final id = _int(args['project_id']);
    if (id == null ||
        projects == null ||
        await projects!.watchOne(id).first == null) {
      throw const McpToolError(
        'El proyecto de destino no existe. Usa list_project_work para obtener su id.',
      );
    }
    return id;
  }

  Future<(Map<String, Object?>, AssistantAction?)> _createNote(
    Map<String, Object?> args,
  ) async {
    final title = (args['title'] as String? ?? '').trim();
    if (title.isEmpty) throw const McpToolError('La nota necesita un título.');
    final text = (args['text'] as String? ?? '').trim();
    final tasks = args['tasks'] as List? ?? const [];
    if (text.isEmpty && tasks.isEmpty) {
      throw const McpToolError(
        'Falta el contenido. Pasa text con la guía completa (secciones ##), no solo el título.',
      );
    }
    final category =
        NoteCategory.values.asNameMap()[args['category']] ?? NoteCategory.idea;
    final projectId = await _validatedProjectId(args);
    final id = await notes.create(category: category, projectId: projectId);
    final doc = NoteDocument(text: _compose(args, title: title));
    await notes.saveContent(
      id,
      title: doc.title,
      content: doc.encode(),
      body: doc.body,
    );
    Future<void> open() async => noteBridge.openHandler?.call(id);
    await open();
    return (
      <String, Object?>{'note_id': id, 'title': title},
      AssistantAction('Nota creada: $title', open: open),
    );
  }

  Future<(Map<String, Object?>, AssistantAction?)> _appendToNote(
    Map<String, Object?> args,
  ) async {
    final live = noteBridge.live;
    final id =
        _int(args['note_id']) ??
        live?.noteId ??
        (throw const McpToolError(
          'No hay ninguna nota abierta. Indica note_id (usa find_notes) o crea una con create_note.',
        ));
    final addition = _compose(args);
    if (addition.isEmpty) throw const McpToolError('No hay nada que añadir.');
    if (live != null && live.noteId == id) {
      live.appendText(addition);
      await live.persist();
    } else {
      final note =
          await notes.get(id) ?? (throw McpToolError('No existe la nota $id.'));
      final doc = NoteDocument.decode(
        note.content,
        legacy: note,
        checklist: await notes.checklist(id),
      );
      final updated = doc.copyWith(
        text: doc.text.trim().isEmpty
            ? addition
            : '${doc.text.trimRight()}\n$addition',
      );
      await notes.saveContent(
        id,
        title: updated.title,
        content: updated.encode(),
        body: updated.body,
      );
    }
    return (
      <String, Object?>{'note_id': id, 'appended': addition},
      AssistantAction(
        'Añadido a la nota',
        open: () async => noteBridge.openHandler?.call(id),
      ),
    );
  }

  Future<(Map<String, Object?>, AssistantAction?)> _replaceNoteText(
    Map<String, Object?> args,
  ) async {
    final id =
        _int(args['note_id']) ?? (throw const McpToolError('Falta note_id.'));
    final expected = args['expected_text'] as String? ?? '';
    final replacement = (args['text'] as String? ?? '').trim();
    if (replacement.isEmpty)
      throw const McpToolError('La nota nueva no puede estar vacía.');
    final live = noteBridge.live;
    if (live != null && live.noteId == id) {
      if (!live.replaceTextIfUnchanged(expected, replacement)) {
        throw const McpToolError(
          'La nota cambió mientras se preparaba la propuesta. Revísala antes de aplicar el cambio.',
        );
      }
      await live.persist();
    } else {
      final note =
          await notes.get(id) ?? (throw McpToolError('No existe la nota $id.'));
      final doc = NoteDocument.decode(
        note.content,
        legacy: note,
        checklist: await notes.checklist(id),
      );
      if (doc.text != expected) {
        throw const McpToolError(
          'La nota cambió mientras se preparaba la propuesta. Léela otra vez antes de guardar.',
        );
      }
      final updated = doc.copyWith(text: replacement);
      await notes.saveContent(
        id,
        title: updated.title,
        content: updated.encode(),
        body: updated.body,
      );
    }
    return (
      {'note_id': id, 'replaced': true},
      AssistantAction(
        'Nota desarrollada',
        open: () async => noteBridge.openHandler?.call(id),
      ),
    );
  }

  /// Boceto a mano sobre la página de una nota. Los trazos llegan en la misma cuadrícula 0–100
  /// que en el lienzo; aquí se colocan debajo de lo que ya hay escrito y dibujado.
  Future<(Map<String, Object?>, AssistantAction?)> _sketchNote(
    Map<String, Object?> args,
  ) async {
    final paths = parseSketchPaths(args['strokes']);
    final size = ((args['size'] as num?)?.toDouble() ?? 320).clamp(
      80.0,
      NotePage.textWidth,
    );
    final live = noteBridge.live;
    final id =
        _int(args['note_id']) ??
        live?.noteId ??
        (throw const McpToolError(
          'No hay ninguna nota abierta. Indica note_id (usa find_notes) o crea una con create_note.',
        ));
    if (args['embedded'] == true) {
      var nextId = 1;
      final (strokes, _) = placeSketchPaths(
        paths,
        origin: const Offset(16, 16),
        size: 280,
        nextId: () => nextId++,
      );
      final sketch = NoteSketch(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        data: CanvasData(strokes: strokes),
      );
      if (live != null && live.noteId == id && live is LiveSketchNote) {
        (live as LiveSketchNote).addSketch(sketch);
        await live.persist();
      } else {
        final note =
            await notes.get(id) ??
            (throw McpToolError('No existe la nota $id.'));
        final doc = NoteDocument.decode(
          note.content,
          legacy: note,
          checklist: await notes.checklist(id),
        );
        final updated = doc.copyWith(sketches: [...doc.sketches, sketch]);
        await notes.saveContent(
          id,
          title: updated.title,
          content: updated.encode(),
          body: updated.body,
        );
      }
      return (
        {'note_id': id, 'sketch_id': sketch.id, 'embedded': true},
        AssistantAction('Boceto insertado en la nota'),
      );
    }
    final x = (args['x'] as num?)?.toDouble();
    final y = (args['y'] as num?)?.toDouble();
    final explicit = x == null || y == null ? null : Offset(x, y);

    Rect place(NoteDocument doc, void Function(List<Stroke>) apply) {
      var next = doc.strokes.fold(0, (m, s) => math.max(m, s.id)) + 1;
      final (strokes, bounds) = placeSketchPaths(
        paths,
        origin: explicit ?? NotePage.sketchOrigin(doc, size),
        size: size,
        nextId: () => next++,
      );
      apply(strokes);
      return bounds;
    }

    final Rect bounds;
    if (live != null && live.noteId == id) {
      bounds = place(
        NoteDocument(text: live.noteText, strokes: live.noteStrokes),
        live.addStrokes,
      );
      await live.persist();
    } else {
      final note =
          await notes.get(id) ?? (throw McpToolError('No existe la nota $id.'));
      final doc = NoteDocument.decode(
        note.content,
        legacy: note,
        checklist: await notes.checklist(id),
      );
      late final NoteDocument updated;
      bounds = place(
        doc,
        (strokes) =>
            updated = doc.copyWith(strokes: [...doc.strokes, ...strokes]),
      );
      await notes.saveContent(
        id,
        title: updated.title,
        content: updated.encode(),
        body: updated.body,
      );
    }

    return (
      <String, Object?>{
        'note_id': id,
        'strokes': paths.length,
        'bounds': {
          'x': bounds.left.round(),
          'y': bounds.top.round(),
          'width': bounds.width.round(),
          'height': bounds.height.round(),
        },
      },
      AssistantAction(
        'Boceto en la nota',
        open: () async => noteBridge.openHandler?.call(id),
      ),
    );
  }

  Future<Map<String, Object?>> _findNotes(Map<String, Object?> args) async {
    final found = await notes
        .watchAll(query: args['query'] as String? ?? '')
        .first;
    return {
      'notes': [
        for (final n in found.take(8))
          {
            'note_id': n.id,
            'title': n.title.isEmpty ? 'Nota sin título' : n.title,
            'preview': n.body.length > 140
                ? '${n.body.substring(0, 140)}…'
                : n.body,
          },
      ],
    };
  }

  Future<Map<String, Object?>> _readNote(Map<String, Object?> args) async {
    final id =
        _int(args['note_id']) ?? (throw const McpToolError('Falta note_id.'));
    final live = noteBridge.live;
    if (live != null && live.noteId == id)
      return {'note_id': id, 'text': live.noteText};
    final note =
        await notes.get(id) ?? (throw McpToolError('No existe la nota $id.'));
    return {
      'note_id': id,
      'text': NoteDocument.decode(
        note.content,
        legacy: note,
        checklist: await notes.checklist(id),
      ).text,
    };
  }

  Future<(Map<String, Object?>, AssistantAction?)> _focusNoteText(
    Map<String, Object?> args,
  ) async {
    final id =
        _int(args['note_id']) ?? (throw const McpToolError('Falta note_id.'));
    final phrase = (args['phrase'] as String? ?? '').trim();
    if (phrase.isEmpty)
      throw const McpToolError('Falta la frase que quieres señalar.');
    final live = noteBridge.live;
    if (live == null || live.noteId != id) {
      throw const McpToolError(
        'Abre primero esa nota con open_note para poder señalarla.',
      );
    }
    if (!live.noteText.toLowerCase().contains(phrase.toLowerCase())) {
      throw const McpToolError(
        'La frase no aparece en la nota abierta; usa una frase exacta de read_note.',
      );
    }
    live.focusText(phrase);
    return (
      {'note_id': id, 'focused': phrase},
      AssistantAction('Explicando: $phrase'),
    );
  }

  Future<(Map<String, Object?>, AssistantAction?)> _openNote(
    Map<String, Object?> args,
  ) async {
    final id =
        _int(args['note_id']) ?? (throw const McpToolError('Falta note_id.'));
    if (await notes.get(id) == null)
      throw McpToolError('No existe la nota $id.');
    await noteBridge.openHandler?.call(id);
    return (<String, Object?>{'note_id': id, 'open': true}, null);
  }

  Future<(Map<String, Object?>, AssistantAction?)> _openView(
    Map<String, Object?> args,
  ) async {
    const labels = {
      'home': 'Inicio',
      'calendar': 'Calendario',
      'projects': 'Proyectos',
      'project': 'Proyecto',
      'requirement': 'Requerimiento',
      'notes': 'Notas',
      'canvases': 'Lienzos',
      'graph': 'Grafo',
      'settings': 'Ajustes',
    };
    final view = (args['view'] as String? ?? '').trim().toLowerCase();
    if (!labels.containsKey(view)) {
      throw const McpToolError('La vista indicada no existe en KRAFT.');
    }
    final projectId = _int(args['project_id']);
    final requirementId = _int(args['requirement_id']);
    if (view == 'requirement') {
      if (requirementId == null) {
        throw const McpToolError(
          'Para abrir un requerimiento falta requirement_id.',
        );
      }
      return _showRequirement(await _requirementOf(requirementId));
    }
    if (view == 'project' && projectId == null) {
      throw const McpToolError('Para abrir un proyecto falta project_id.');
    }
    if (requirementId != null) {
      return _showRequirement(await _requirementOf(requirementId));
    }
    final handler = openViewHandler;
    if (handler == null) {
      throw const McpToolError('KRAFT no puede navegar a vistas ahora mismo.');
    }
    await handler(view, projectId);
    final label = view == 'project' ? 'Proyecto #$projectId' : labels[view]!;
    return (
      {'view': view, if (projectId != null) 'project_id': projectId},
      AssistantAction('Abrió: $label'),
    );
  }

  Future<(Map<String, Object?>, AssistantAction?)> _closeView() async {
    final handler = openViewHandler;
    if (handler == null) {
      throw const McpToolError('KRAFT no puede cerrar la vista ahora mismo.');
    }
    await handler('close', null);
    return (
      <String, Object?>{'closed': true},
      AssistantAction('Cerró la vista actual'),
    );
  }

  // ---- Recordatorios ----

  Future<(Map<String, Object?>, AssistantAction?)> _createReminder(
    Map<String, Object?> args,
  ) async {
    final title = (args['title'] as String? ?? '').trim();
    if (title.isEmpty)
      throw const McpToolError('El recordatorio necesita un título.');
    final raw = args['remind_at'] as String?;
    final at = raw == null || raw.isEmpty
        ? null
        : DateTime.tryParse(raw)?.toLocal();
    if (raw != null && raw.isNotEmpty && at == null)
      throw McpToolError('No entiendo la fecha "$raw". Usa ISO 8601.');
    if (at != null && !at.isAfter(_clock()))
      throw const McpToolError('Esa hora ya pasó. Pregunta al usuario otra.');
    final requirementId = _int(args['requirement_id']);
    var projectId = await _validatedProjectId(args);
    if (requirementId != null) {
      final requirement = await workItems?.get(requirementId);
      if (requirement == null || requirement.kind != 'requirement') {
        throw const McpToolError('El requerimiento no existe.');
      }
      projectId ??= requirement.projectId;
      if (projectId != requirement.projectId) {
        throw const McpToolError(
          'La tarea debe ser del mismo proyecto que el requerimiento.',
        );
      }
    }
    final id = await tasks.create(
      title: title,
      detail: (args['detail'] as String? ?? '').trim(),
      highPriority: args['high_priority'] == true,
      remindAt: at,
      projectId: projectId,
      requirementId: requirementId,
    );
    final label = at == null
        ? title
        : '$title · ${reminderLabel(at, now: _clock())}';
    return (
      <String, Object?>{'task_id': id, 'remind_at': at?.toIso8601String()},
      AssistantAction('Recordatorio: $label'),
    );
  }

  Future<Map<String, Object?>> _listReminders(Map<String, Object?> args) async {
    final includeDone = args['include_done'] == true;
    return {
      'tasks': [
        for (final t in await tasks.all())
          if (includeDone || !t.done)
            {
              'task_id': t.id,
              'title': t.title,
              if (t.remindAt != null)
                'remind_at': t.remindAt!.toIso8601String(),
              'done': t.done,
              'project_id': t.projectId,
              'requirement_id': t.requirementId,
            },
      ],
    };
  }

  Future<(Map<String, Object?>, AssistantAction?)> _completeReminder(
    Map<String, Object?> args,
  ) async {
    final id =
        _int(args['task_id']) ?? (throw const McpToolError('Falta task_id.'));
    final task =
        await tasks.get(id) ?? (throw McpToolError('No existe la tarea $id.'));
    await tasks.setDone(task, true);
    return (
      <String, Object?>{'task_id': id, 'done': true},
      AssistantAction('Hecho: ${task.title}'),
    );
  }

  Future<(Map<String, Object?>, AssistantAction?)> _focusCanvasItem(
    Map<String, Object?> args,
  ) async {
    final id = _int(args['canvas_id']);
    final itemId = (args['element_id'] as String? ?? '').trim();
    if (itemId.isEmpty) throw const McpToolError('Falta element_id.');
    await canvasBridge.focusItem(id, itemId);
    return (
      {
        'canvas_id': canvasBridge.resolveId(id),
        'element_id': itemId,
        'focused': true,
      },
      AssistantAction('Explicando elemento'),
    );
  }

  Future<(Map<String, Object?>, AssistantAction?)> _explainCanvas(
    Map<String, Object?> args,
  ) async {
    final id = canvasBridge.resolveId(_int(args['canvas_id']));
    final raw = args['steps'];
    if (raw is! List || raw.isEmpty)
      throw const McpToolError('Faltan los pasos de la explicación.');
    final existing = await canvasBridge.read(
      id,
      (doc, _) => {for (final item in doc.items) item.id},
    );
    final steps = <ExplanationStep>[];
    for (final value in raw.take(16)) {
      if (value is! Map) continue;
      final elementId = '${value['element_id'] ?? ''}'.trim();
      final narration = '${value['explanation'] ?? ''}'.trim();
      if (elementId.isEmpty ||
          narration.isEmpty ||
          !existing.contains(elementId))
        continue;
      steps.add(ExplanationStep(focus: elementId, narration: narration));
    }
    if (steps.isEmpty)
      throw const McpToolError(
        'Ningún paso coincide con los elementos del lienzo. Usa get_canvas otra vez.',
      );
    await canvasBridge.open(id);
    return (
      {'canvas_id': id, 'steps': steps.length, 'ready': true},
      AssistantAction(
        'Explicación guiada · ${steps.length} pasos',
        explanation: GuidedExplanation(
          target: ExplanationTarget.canvas,
          documentId: id,
          steps: steps,
        ),
      ),
    );
  }

  Future<(Map<String, Object?>, AssistantAction?)> _explainNote(
    Map<String, Object?> args,
  ) async {
    final id =
        _int(args['note_id']) ?? (throw const McpToolError('Falta note_id.'));
    final note =
        await notes.get(id) ?? (throw McpToolError('No existe la nota $id.'));
    final document = NoteDocument.decode(
      note.content,
      legacy: note,
      checklist: await notes.checklist(id),
    );
    final raw = args['steps'];
    if (raw is! List || raw.isEmpty)
      throw const McpToolError('Faltan los pasos de la explicación.');
    final steps = <ExplanationStep>[];
    for (final value in raw.take(16)) {
      if (value is! Map) continue;
      final phrase = '${value['phrase'] ?? ''}'.trim();
      final narration = '${value['explanation'] ?? ''}'.trim();
      if (phrase.isEmpty ||
          narration.isEmpty ||
          !document.text.toLowerCase().contains(phrase.toLowerCase()))
        continue;
      steps.add(ExplanationStep(focus: phrase, narration: narration));
    }
    if (steps.isEmpty)
      throw const McpToolError(
        'Ninguna frase coincide con la nota. Usa read_note y copia frases exactas.',
      );
    await noteBridge.openHandler?.call(id);
    return (
      {'note_id': id, 'steps': steps.length, 'ready': true},
      AssistantAction(
        'Explicación guiada · ${steps.length} pasos',
        explanation: GuidedExplanation(
          target: ExplanationTarget.note,
          documentId: id,
          steps: steps,
        ),
      ),
    );
  }

  // ---- Lienzos ----

  Future<(Map<String, Object?>, AssistantAction?)> _canvas(
    String name,
    Map<String, Object?> args,
  ) async {
    if (name == 'create_canvas') await _validatedProjectId(args);
    final result = await canvasTools.call(name, args);
    final id = result['canvas_id'] as int? ?? canvasBridge.openCanvasId;
    final action = switch (name) {
      'create_canvas' => AssistantAction('Lienzo creado: ${result['title']}'),
      'create_diagram' => AssistantAction(
        'Diagrama con ${(result['created'] as List?)?.length ?? 0} elementos',
        open: id == null ? null : () async => canvasBridge.open(id),
      ),
      'edit_diagram' => AssistantAction('Diagrama actualizado'),
      'add_elements' => AssistantAction(
        'Añadidos ${(result['created'] as List?)?.length ?? 0} elementos al lienzo',
      ),
      'draw_sketch' => AssistantAction(
        'Dibujó ${result['strokes'] ?? ''} trazos',
      ),
      _ => null,
    };
    return (result, action);
  }

  /// Resumen de lo que hay guardado, para que el asistente sepa de qué le hablan sin buscar a ciegas.
  String _workspace = '';

  /// Relee el espacio de trabajo antes de responder (títulos recientes y cuántas cosas hay).
  Future<void> refresh() async {
    try {
      final recentNotes = await notes.watchAll().first;
      final recentCanvases = await canvasTools.canvases.watchAll().first;
      final pending = [
        for (final t in await tasks.all())
          if (!t.done) t,
      ];
      String list(Iterable<String> items) =>
          items.isEmpty ? 'ninguna' : items.join(', ');
      final projectList = await projects?.watchAll().first;
      _workspace = [
        if (projectList != null)
          'Proyectos: ${list([for (final p in projectList.take(8)) '${p.id} "${p.title}"'])}. Usa list_project_work para ver alcance y pendientes.',
        'Notas (${recentNotes.length}): ${list([for (final n in recentNotes.take(6)) '${n.id} "${n.title.isEmpty ? 'sin título' : n.title}"'])}.',
        'Lienzos (${recentCanvases.length}): ${list([for (final c in recentCanvases.take(6)) '${c.id} "${c.title}"'])}.',
        'Tareas pendientes: ${pending.length}${pending.isEmpty ? '' : ' (${list([for (final t in pending.take(4)) t.title])})'}.',
      ].join(' ');
    } on Object {
      // Si la base de datos no está lista, el asistente sigue funcionando sin el resumen.
      _workspace = '';
    }
  }

  /// Contexto para las instrucciones: fecha, lo que está abierto y lo que existe.
  String context({bool compact = false}) {
    final now = _clock();
    final offset = now.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final zone =
        '$sign${offset.inHours.abs().toString().padLeft(2, '0')}:${(offset.inMinutes.abs() % 60).toString().padLeft(2, '0')}';
    final open = [
      if (noteBridge.live case final note?) 'Nota abierta: id ${note.noteId}.',
      if (canvasBridge.live case final canvas?)
        'Lienzo abierto: id ${canvas.canvasId} "${canvas.canvasTitle}".',
    ];
    final inventory = compact
        ? ' En KRAFT hay un inventario de proyectos y notas: no lo analices ni lo pegues si el usuario pide otro tema.'
        : (_workspace.isEmpty ? '' : '\nEn KRAFT: $_workspace');
    return 'Ahora es ${longDay(now)} de ${now.year}, ${hhmm(now)} (${now.toIso8601String()} hora local, UTC$zone). '
        '${open.isEmpty ? 'No hay nada abierto.' : open.join(' ')}'
        '$inventory';
  }

  static int? _int(Object? v) =>
      v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
}
