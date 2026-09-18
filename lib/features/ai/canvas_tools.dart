import 'dart:math' as math;
import 'dart:ui';

import '../../data/repositories.dart';
import '../../theme/kraft_colors.dart';
import '../../utils/text_match.dart';
import '../canvas/canvas_codec.dart';
import '../canvas/canvas_document.dart';
import '../canvas/canvas_icons.dart';
import '../canvas/canvas_items.dart';
import '../canvas/canvas_models.dart';
import 'canvas_bridge.dart';
import 'diagram_layout.dart';

typedef Json = Map<String, Object?>;

/// Herramientas MCP sobre los lienzos de KRAFT. Independientes del transporte (HTTP) para poder probarlas.
class KraftCanvasTools {
  KraftCanvasTools({required this.bridge, required this.canvases});

  final CanvasBridge bridge;
  final CanvasesRepository canvases;

  static const _colorHelp =
      'Relleno: blanco, amarillo, verde, cian, rosa, gris. Texto y líneas: negro, oliva, verde, azul, rojo. También #RRGGBB.';

  static final Json _elementSchema = {
    'type': 'object',
    'properties': {
      'ref': {
        'type': 'string',
        'description':
            'Identificador temporal tuyo para usarlo en connections/edges.',
      },
      'type': {
        'type': 'string',
        'enum': [
          'note',
          'card',
          'step',
          'shape',
          'text',
          'icon',
          'paragraph',
          'checklist',
          'link',
        ],
        'description':
            'note = nota adhesiva; card = tarjeta con icono y bullets; step = paso numerado de un flujo; '
            'shape = forma geométrica; text = título suelto; icon = icono grande; '
            'paragraph = bloque de texto largo (explicaciones, definiciones, fragmentos de código); '
            'checklist = lista de casillas (usa "bullets" para las líneas); '
            'link = tarjeta que abre otra nota (pon note_id).',
      },
      'title': {
        'type': 'string',
        'description':
            'Texto principal, concreto y obligatorio para card/step. Nunca uses "Tarjeta", "Paso" ni otro nombre genérico.',
      },
      'body': {
        'type': 'string',
        'description': 'Texto secundario (note, card, step).',
      },
      'bullets': {
        'type': 'array',
        'items': {'type': 'string'},
        'description':
            'Puntos de detalle de una tarjeta (responsabilidades, ejemplos, archivos). Frases cortas.',
      },
      'note_id': {
        'type': 'integer',
        'description':
            'Nota existente que amplía este elemento. La tarjeta queda vinculada y se puede abrir con un toque.',
      },
      'group': {
        'type': 'string',
        'description':
            'id del grupo/capa al que pertenece (ver groups en create_diagram).',
      },
      'label': {
        'type': 'string',
        'description':
            'Etiqueta corta de categoría, distinta del título, p. ej. "CLIENTE", "PASO 01" o "SEGURIDAD".',
      },
      'shape': {
        'type': 'string',
        'enum': [for (final s in ShapeKind.values) s.name],
        'description': 'Solo para type=shape. diamond sirve para decisiones.',
      },
      'icon': {
        'type': 'string',
        'enum': canvasIcons.keys.toList(),
        'description': 'Icono (card, step, note, icon).',
      },
      'color': {'type': 'string', 'description': _colorHelp},
      'size': {
        'type': 'string',
        'enum': ['S', 'M', 'L'],
        'description':
            'Jerarquía visual: L para ideas centrales, M para el flujo principal y S para detalles.',
      },
      'active': {
        'type': 'boolean',
        'description': 'Resalta un step como activo.',
      },
      'x': {
        'type': 'number',
        'description':
            'Esquina superior izquierda en coordenadas del lienzo (opcional).',
      },
      'y': {'type': 'number'},
    },
    'required': ['type'],
  };

  static final Json _groupSchema = {
    'type': 'object',
    'properties': {
      'id': {'type': 'string'},
      'title': {
        'type': 'string',
        'description': 'Nombre de la capa o fase, p. ej. "Dominio".',
      },
      'color': {'type': 'string', 'description': _colorHelp},
      'icon': {'type': 'string', 'enum': canvasIcons.keys.toList()},
    },
    'required': ['id', 'title'],
  };

  static final Json _connectionSchema = {
    'type': 'object',
    'properties': {
      'from': {
        'type': 'string',
        'description': 'ref o id del elemento de origen.',
      },
      'to': {
        'type': 'string',
        'description': 'ref o id del elemento de destino.',
      },
      'label': {'type': 'string'},
      'style': {
        'type': 'string',
        'enum': [for (final s in LinkStyle.values) s.name],
      },
      'arrow': {
        'type': 'string',
        'enum': [for (final a in LinkArrow.values) a.name],
      },
    },
    'required': ['from', 'to'],
  };

  static const Json _canvasId = {
    'type': 'integer',
    'description':
        'Lienzo a usar. Si se omite, el que está abierto en pantalla.',
  };

  List<Json> get definitions => [
    {
      'name': 'list_canvases',
      'title': 'Listar lienzos',
      'description':
          'Lista los lienzos de KRAFT e indica cuál está abierto en pantalla.',
      'inputSchema': {'type': 'object', 'properties': <String, Object?>{}},
      'annotations': {'readOnlyHint': true},
    },
    {
      'name': 'get_canvas',
      'title': 'Leer lienzo',
      'description':
          'Devuelve los elementos (id, tipo, textos, posición y tamaño) y conexiones de un lienzo. Úsalo antes de editar algo existente.',
      'inputSchema': {
        'type': 'object',
        'properties': {'canvas_id': _canvasId},
      },
      'annotations': {'readOnlyHint': true},
    },
    {
      'name': 'create_canvas',
      'title': 'Crear lienzo',
      'description':
          'Crea un lienzo vacío y (por defecto) lo abre en pantalla para que el usuario vea cómo se construye.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'title': {'type': 'string'},
          'open': {'type': 'boolean', 'default': true},
          'project_id': {
            'type': 'integer',
            'description': 'Proyecto de destino, si corresponde.',
          },
        },
        'required': ['title'],
      },
    },
    {
      'name': 'open_canvas',
      'title': 'Abrir lienzo',
      'description': 'Abre un lienzo existente en la pantalla del iPad.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'canvas_id': {'type': 'integer'},
        },
        'required': ['canvas_id'],
      },
    },
    {
      'name': 'create_diagram',
      'title': 'Crear diagrama',
      'description':
          'Crea un diagrama completo (nodos + conexiones) y lo ordena automáticamente. Es la forma preferida de dibujar '
          'flujos, procesos, mapas mentales, arquitecturas u organigramas. Se coloca junto al contenido existente '
          'sin taparlo y se puede deshacer de una vez. Debe contar una historia visual con jerarquía L/M/S; toda card/step '
          'lleva título concreto, y cada group debe contener varios nodos.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'canvas_id': _canvasId,
          'layout': {
            'type': 'string',
            'enum': [for (final l in DiagramLayout.values) l.name],
            'description':
                'horizontal = flujo izquierda→derecha; vertical = arriba→abajo (organigramas); mindmap = raíz al centro; grid = cuadrícula.',
            'default': 'horizontal',
          },
          'title': {
            'type': 'string',
            'description': 'Título opcional que se coloca encima del diagrama.',
          },
          'nodes': {
            'type': 'array',
            'items': _elementSchema,
            'description':
                'Cada nodo necesita "ref" para poder conectarlo. Usa type=card con "bullets" para explicar '
                'responsabilidades o ejemplos; type=shape+diamond para decisiones. No omitas title en cards/steps.',
          },
          'edges': {'type': 'array', 'items': _connectionSchema},
          'groups': {
            'type': 'array',
            'items': _groupSchema,
            'description':
                'Capas o fases. Cada una se dibuja como un marco con título y los nodos con ese "group" van dentro. '
                'Ideal para arquitecturas (Presentación, Dominio, Datos) o carriles por responsable.',
          },
          'replace': {
            'type': 'boolean',
            'description':
                'Borra el diagrama anterior con el mismo título antes de dibujar el nuevo.',
          },
          'x': {
            'type': 'number',
            'description':
                'Esquina superior izquierda del diagrama (opcional).',
          },
          'y': {'type': 'number'},
        },
        'required': ['nodes'],
      },
    },
    {
      'name': 'edit_diagram',
      'title': 'Editar diagrama',
      'description':
          'Modifica el diagrama que ya existe en el lienzo en vez de crear otro: añade, cambia o quita nodos y '
          'conexiones y, si quieres, lo vuelve a ordenar. Lee antes con get_canvas para saber los ids.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'canvas_id': _canvasId,
          'diagram': {
            'type': 'string',
            'description':
                'Cuál de los diagramas del lienzo se edita (el "diagram" que devolvieron create_diagram, get_canvas o search_workspace). Sin esto se edita el último.',
          },
          'add_nodes': {'type': 'array', 'items': _elementSchema},
          'update_nodes': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'id': {'type': 'string'},
                'title': {'type': 'string'},
                'body': {'type': 'string'},
                'bullets': (_elementSchema['properties']! as Json)['bullets'],
                'label': {'type': 'string'},
                'color': {'type': 'string', 'description': _colorHelp},
                'icon': (_elementSchema['properties']! as Json)['icon'],
                'shape': (_elementSchema['properties']! as Json)['shape'],
                'note_id': (_elementSchema['properties']! as Json)['note_id'],
                'size': (_elementSchema['properties']! as Json)['size'],
                'clear_note': {
                  'type': 'boolean',
                  'description': 'Quita la nota vinculada.',
                },
              },
              'required': ['id'],
            },
          },
          'remove_ids': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'Ids de elementos o conexiones a borrar.',
          },
          'add_edges': {'type': 'array', 'items': _connectionSchema},
          'remove_edges': {'type': 'array', 'items': _connectionSchema},
          'relayout': {
            'type': 'boolean',
            'description':
                'Vuelve a ordenar todo el diagrama con las conexiones actuales.',
          },
          'layout': {
            'type': 'string',
            'enum': [for (final l in DiagramLayout.values) l.name],
          },
        },
      },
    },
    {
      'name': 'draw_sketch',
      'title': 'Dibujar a mano',
      'description':
          'Dibuja trazos a mano alzada en el lienzo (subrayar, rodear algo, una flecha suelta, un boceto simple). '
          'Los puntos van en una cuadrícula propia de 0 a 100 que se coloca y escala en el lienzo.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'canvas_id': _canvasId,
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
            'description': 'Tamaño del dibujo en el lienzo (por defecto 320).',
          },
          'x': {'type': 'number'},
          'y': {'type': 'number'},
        },
        'required': ['strokes'],
      },
    },
    {
      'name': 'add_elements',
      'title': 'Añadir elementos',
      'description':
          'Añade elementos sueltos (notas, tarjetas, formas, textos, iconos) y opcionalmente conexiones. Sin x/y se colocan en fila junto al contenido.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'canvas_id': _canvasId,
          'elements': {'type': 'array', 'items': _elementSchema},
          'connections': {'type': 'array', 'items': _connectionSchema},
        },
        'required': ['elements'],
      },
    },
    {
      'name': 'update_element',
      'title': 'Editar elemento',
      'description':
          'Cambia textos, color, icono, tamaño, forma o posición de un elemento existente (id de get_canvas).',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'canvas_id': _canvasId,
          'element_id': {'type': 'string'},
          'title': {'type': 'string'},
          'body': {'type': 'string'},
          'label': {'type': 'string'},
          'shape': (_elementSchema['properties']! as Json)['shape'],
          'icon': (_elementSchema['properties']! as Json)['icon'],
          'color': {'type': 'string', 'description': _colorHelp},
          'size': {
            'type': 'string',
            'enum': ['S', 'M', 'L'],
          },
          'active': {'type': 'boolean'},
          'note_id': (_elementSchema['properties']! as Json)['note_id'],
          'clear_note': {
            'type': 'boolean',
            'description': 'Quita la nota vinculada.',
          },
          'x': {'type': 'number'},
          'y': {'type': 'number'},
        },
        'required': ['element_id'],
      },
    },
    {
      'name': 'connect_elements',
      'title': 'Conectar elementos',
      'description':
          'Conecta dos elementos existentes con una línea que se engancha sola al contorno de cada uno. Si ya estaban conectados, actualiza etiqueta y estilo.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'canvas_id': _canvasId,
          ...(_connectionSchema['properties']! as Json),
        },
        'required': ['from', 'to'],
      },
    },
    {
      'name': 'delete_elements',
      'title': 'Borrar elementos',
      'description':
          'Borra elementos o conexiones por id. Las conexiones de un elemento borrado también desaparecen.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'canvas_id': _canvasId,
          'ids': {
            'type': 'array',
            'items': {'type': 'string'},
          },
        },
        'required': ['ids'],
      },
      'annotations': {'destructiveHint': true},
    },
  ];

  /// Ejecuta la herramienta [name]. Lanza [McpToolError] con un mensaje útil para la IA.
  Future<Json> call(String name, Json args) => switch (name) {
    'list_canvases' => _listCanvases(),
    'get_canvas' => _getCanvas(args),
    'create_canvas' => _createCanvas(args),
    'open_canvas' => _openCanvas(args),
    'create_diagram' => _createDiagram(args),
    'edit_diagram' => _editDiagram(args),
    'draw_sketch' => _drawSketch(args),
    'add_elements' => _addElements(args),
    'update_element' => _updateElement(args),
    'connect_elements' => _connect(args),
    'delete_elements' => _delete(args),
    _ => throw McpToolError('Herramienta desconocida: $name'),
  };

  bool has(String name) => definitions.any((d) => d['name'] == name);

  // ---------------------------------------------------------------------------

  Future<Json> _listCanvases() async {
    final all = await canvases.watchAll().first;
    return {
      'open_canvas_id': bridge.openCanvasId,
      'canvases': [
        for (final c in all)
          () {
            final data = CanvasCodec.decode(c.data);
            return {
              'id': c.id,
              'title': c.title,
              'elements': data.items.length,
              'connections': data.links.length,
              'drawings': data.strokes.length,
              'updated_at': c.updatedAt.toIso8601String(),
            };
          }(),
      ],
    };
  }

  Future<Json> _getCanvas(Json args) async {
    final id = bridge.resolveId(_int(args, 'canvas_id'));
    return bridge.read(id, (doc, title) {
      final bounds = doc.contentBounds;
      final ids = doc.items.map((i) => i.id).toSet();
      final invalid = doc.allLinks
          .where((l) => !ids.contains(l.from) || !ids.contains(l.to))
          .toList();
      return {
        'canvas_id': id,
        'title': title,
        'open': bridge.openCanvasId == id,
        'elements': [for (final item in doc.items) _describe(doc, item)],
        'connections': [
          for (final l in doc.links)
            {
              'id': l.id,
              'from': l.from,
              'to': l.to,
              if (l.label.isNotEmpty) 'label': l.label,
              'style': l.style.name,
              'arrow': l.arrow.name,
            },
        ],
        if (invalid.isNotEmpty)
          'invalid_connections': [
            for (final l in invalid)
              {'id': l.id, 'from': l.from, 'to': l.to, 'label': l.label},
          ],
        'drawings': doc.strokes.length,
        if (bounds != null) 'bounds': _rectJson(bounds),
      };
    });
  }

  Future<Json> _createCanvas(Json args) async {
    final title = (_string(args, 'title') ?? '').trim();
    final safeTitle = title.isEmpty
        ? 'Lienzo de IA'
        : title.substring(0, math.min(120, title.length));
    late final int id;
    try {
      id = await canvases.create(
        title: safeTitle,
        projectId: _int(args, 'project_id'),
      );
    } on ArgumentError {
      throw const McpToolError(
        'El proyecto de destino no existe. Revisa project_id.',
      );
    }
    final open = args['open'] as bool? ?? true;
    if (open) await bridge.open(id);
    return {
      'canvas_id': id,
      'title': safeTitle,
      'open': open && bridge.openCanvasId == id,
    };
  }

  Future<Json> _openCanvas(Json args) async {
    final id =
        _int(args, 'canvas_id') ??
        (throw const McpToolError('Falta canvas_id.'));
    await bridge.open(id);
    return {'canvas_id': id, 'open': bridge.openCanvasId == id};
  }

  Future<Json> _createDiagram(Json args) async {
    final nodes = _specs(args['nodes'], 'nodes');
    if (nodes.isEmpty)
      throw const McpToolError('El diagrama necesita al menos un nodo.');
    final edges = _connections(args['edges']);
    final layout =
        DiagramLayout.values.asNameMap()[_string(args, 'layout')] ??
        DiagramLayout.horizontal;
    final title = _string(args, 'title')?.trim() ?? '';
    final explicitOrigin = _offset(args);
    final groups = _groups(args['groups']);
    final replace = args['replace'] == true;

    return bridge
        .edit(
          _int(args, 'canvas_id'),
          (doc) {
            // No se duplican diagramas: basta con que hablen de lo mismo ("Arquitectura limpia calculadora"
            // y "Arquitectura tecnológica calculadora" son el mismo). Si aparece uno, se edita.
            final previous = _similarDiagram(doc, title, nodes);
            if (previous != null) {
              if (!replace) {
                final siblings = [
                  for (final item in doc.items)
                    if (item.id != previous.id &&
                        item.group != null &&
                        item.group == previous.group &&
                        item.title.isNotEmpty)
                      item.title,
                ];
                throw McpToolError(
                  'Este lienzo ya tiene el diagrama "${previous.title}" (diagram=${previous.group}) con '
                  '${siblings.length} elementos: ${siblings.take(8).join(', ')}. '
                  'No hagas otro: mejóralo con edit_diagram(diagram="${previous.group}", add_nodes/update_nodes/add_edges/remove_ids/relayout=true), '
                  'usando get_canvas antes si necesitas los ids. Sólo si el usuario pide rehacerlo desde cero, repite con replace=true.',
                );
              }
              doc.removeByIds({
                previous.id,
                for (final item in doc.items)
                  if (item.group != null && item.group == previous.group)
                    item.id,
              });
            }

            final diagram =
                'dg-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
            final refs = [
              for (final (i, n) in nodes.indexed) n.ref ?? 'n${i + 1}',
            ];
            final sizes = {
              for (final (i, n) in nodes.indexed)
                refs[i]: canvasItemSize(n.prototype),
            };
            final groupOf = {
              for (final (i, n) in nodes.indexed)
                if (n.group != null) refs[i]: n.group!,
            };
            final edgePairs = [for (final e in edges) (e.from, e.to)];

            Map<String, Offset> relative;
            var frames = <String, Rect>{};
            if (groups.isNotEmpty && groupOf.isNotEmpty) {
              final result = layoutGrouped(
                ids: refs,
                sizes: sizes,
                edges: edgePairs,
                groupOf: groupOf,
                groupOrder: [for (final g in groups) g.id],
                horizontal: layout != DiagramLayout.vertical,
              );
              relative = result.positions;
              frames = result.groups;
            } else {
              relative = layoutDiagram(
                ids: refs,
                sizes: sizes,
                edges: edgePairs,
                layout: layout,
              );
            }

            var extent = Rect.zero;
            for (final ref in refs) {
              extent = extent.expandToInclude(relative[ref]! & sizes[ref]!);
            }
            for (final rect in frames.values) {
              extent = extent.expandToInclude(rect);
            }

            final titleItem = title.isEmpty
                ? null
                : CanvasItem(
                    id: 'template',
                    type: CanvasItemType.text,
                    position: Offset.zero,
                    title: title,
                    scale: ItemScale.large,
                  );
            final titleHeight = titleItem == null
                ? 0.0
                : canvasItemSize(titleItem).height + 40;
            final origin =
                explicitOrigin ??
                _freeOrigin(
                  doc,
                  Size(extent.width, extent.height + titleHeight),
                );
            final base = origin + Offset(0, titleHeight);

            final created = <String, CanvasItem>{};
            final out = <Json>[];
            if (titleItem != null) {
              final t = doc.addItem(
                titleItem.copyWith(position: origin, group: diagram),
                select: false,
              );
              out.add({'id': t.id, 'type': 'text', 'title': title});
            }
            // Los marcos primero: se pintan detrás de los nodos.
            for (final group in groups) {
              final rect = frames[group.id];
              if (rect == null) continue;
              final frame = doc.addItem(
                CanvasItem(
                  id: 'template',
                  type: CanvasItemType.frame,
                  position: base + rect.topLeft,
                  title: group.title,
                  width: rect.width,
                  height: rect.height,
                  color: group.color,
                  iconKey: group.icon,
                  group: diagram,
                ),
                select: false,
              );
              out.add({'id': frame.id, 'type': 'frame', 'title': group.title});
            }
            for (final (i, spec) in nodes.indexed) {
              final ref = refs[i];
              final item = doc.addItem(
                spec.prototype.copyWith(
                  position: base + relative[ref]!,
                  group: diagram,
                ),
                select: false,
              );
              created[ref] = item;
              out.add({'ref': ref, ..._describe(doc, item)});
            }
            final links = _applyConnections(doc, edges, created);
            return (
              diagram: diagram,
              items: out,
              links: links.$1,
              warnings: links.$2,
              ids: [for (final o in out) o['id']! as String],
            );
          },
          reveal: (r, doc) => _boundsOf(doc, r.ids),
          summary: (r) => 'Diagrama con ${r.ids.length} elementos',
        )
        .then(
          (r) => {
            'diagram': r.diagram,
            'created': r.items,
            'connections': r.links,
            if (r.warnings.isNotEmpty) 'warnings': r.warnings,
          },
        );
  }

  /// Edita el diagrama existente: añadir, cambiar o quitar, y reordenar sin duplicar nada.
  Future<Json> _editDiagram(Json args) async {
    final adds = _specs(args['add_nodes'] ?? const [], 'add_nodes');
    final updates = [
      for (final u in (args['update_nodes'] as List? ?? const []))
        if (u is Map) u.cast<String, Object?>(),
    ];
    final removeIds = {
      for (final id in (args['remove_ids'] as List? ?? const [])) '$id',
    };
    final addEdges = _connections(args['add_edges']);
    final removeEdges = _connections(args['remove_edges']);
    final relayout = args['relayout'] == true;
    final layout = DiagramLayout.values.asNameMap()[_string(args, 'layout')];

    return bridge
        .edit(
          _int(args, 'canvas_id'),
          (doc) {
            final warnings = <String>[];
            final touched = <String>[];

            for (final update in updates) {
              final reference = _string(update, 'id') ?? '';
              final id = _resolve(doc, const {}, reference);
              final item = id == null ? null : doc.itemById(id);
              if (item == null) {
                warnings.add('No existe el elemento $reference.');
                continue;
              }
              final iconKey = _string(update, 'icon');
              final shape = _enum(ShapeKind.values, update['shape']);
              doc.updateItem(
                item.copyWith(
                  title: _string(update, 'title'),
                  subtitle: _string(update, 'body'),
                  label: _string(update, 'label'),
                  bullets: update.containsKey('bullets')
                      ? [
                          for (final b
                              in (update['bullets'] as List? ?? const []))
                            '$b',
                        ]
                      : null,
                  iconKey: iconKey != null && canvasIcons.containsKey(iconKey)
                      ? iconKey
                      : null,
                  color: _color(
                    _string(update, 'color'),
                    ink: item.type == CanvasItemType.text,
                  ),
                  shape: item.type == CanvasItemType.shape ? shape : null,
                  target: _noteTarget(update),
                  clearTarget: update['clear_note'] == true,
                  scale: _scale(_string(update, 'size')),
                ),
              );
              touched.add(item.id);
            }

            // Qué diagrama se está editando: el que pidió la IA, el de lo que acaba de tocar, o el último del lienzo.
            final asked = _string(args, 'diagram');
            if (asked != null && !doc.items.any((i) => i.group == asked)) {
              warnings.add(
                'En este lienzo no hay ningún diagrama "$asked"; se editó el último.',
              );
            }
            final group =
                (asked != null && doc.items.any((i) => i.group == asked)
                    ? asked
                    : null) ??
                touched
                    .map((id) => doc.itemById(id)?.group)
                    .whereType<String>()
                    .firstOrNull ??
                doc.items.map((i) => i.group).whereType<String>().lastOrNull;

            final created = <String, CanvasItem>{};
            for (final spec in adds) {
              final position =
                  spec.position ??
                  _freeOrigin(doc, canvasItemSize(spec.prototype));
              final item = doc.addItem(
                spec.prototype.copyWith(position: position, group: group),
                select: false,
              );
              if (spec.ref != null) created[spec.ref!] = item;
              touched.add(item.id);
            }

            final links = _applyConnections(doc, addEdges, created);
            warnings.addAll(links.$2);

            final toRemove = {
              for (final reference in removeIds)
                _resolve(doc, created, reference) ?? reference,
            };
            for (final e in removeEdges) {
              final from = created[e.from]?.id ?? e.from;
              final to = created[e.to]?.id ?? e.to;
              final link = doc.links
                  .where((l) => l.connects(from, to))
                  .firstOrNull;
              if (link == null) {
                warnings.add('No hay conexión entre ${e.from} y ${e.to}.');
              } else {
                toRemove.add(link.id);
              }
            }
            if (toRemove.isNotEmpty) doc.removeByIds(toRemove);

            final moved = relayout ? _relayout(doc, group, layout) : 0;
            return (
              updated: touched,
              links: links.$1,
              removed: toRemove.length,
              relayout: moved,
              warnings: warnings,
            );
          },
          reveal: (r, doc) => _boundsOf(doc, r.updated),
          summary: (r) => 'Diagrama actualizado',
        )
        .then(
          (r) => {
            'updated': r.updated,
            'connections': r.links,
            'removed': r.removed,
            if (r.relayout > 0) 'relayout': r.relayout,
            if (r.warnings.isNotEmpty) 'warnings': r.warnings,
          },
        );
  }

  /// Vuelve a ordenar los nodos de un diagrama (respetando sus marcos) con las conexiones actuales.
  int _relayout(CanvasDocument doc, String? group, DiagramLayout? layout) {
    bool inDiagram(CanvasItem i) =>
        group == null ? i.group == null : i.group == group;
    final frames = [
      for (final i in doc.items)
        if (i.type == CanvasItemType.frame && inDiagram(i)) i,
    ]..sort((a, b) => a.position.dy.compareTo(b.position.dy));
    final nodes = [
      for (final i in doc.items)
        if (inDiagram(i) &&
            i.type != CanvasItemType.frame &&
            i.type != CanvasItemType.text)
          i,
    ];
    if (nodes.length < 2) return 0;

    final sizes = {for (final n in nodes) n.id: doc.itemRect(n).size};
    final edges = [
      for (final l in doc.links)
        if (sizes.containsKey(l.from) && sizes.containsKey(l.to))
          (l.from, l.to),
    ];
    // La capa de cada nodo se deduce del marco que lo contiene ahora mismo.
    final groupOf = {
      for (final n in nodes)
        if (frames
                .where((f) => doc.itemRect(f).overlaps(doc.itemRect(n)))
                .firstOrNull
            case final frame?)
          n.id: frame.id,
    };
    final origin =
        _boundsOf(doc, [
          ...frames.map((f) => f.id),
          ...nodes.map((n) => n.id),
        ])?.topLeft ??
        Offset.zero;

    if (frames.isNotEmpty && groupOf.isNotEmpty) {
      final result = layoutGrouped(
        ids: [for (final n in nodes) n.id],
        sizes: sizes,
        edges: edges,
        groupOf: groupOf,
        groupOrder: [for (final f in frames) f.id],
        horizontal: layout != DiagramLayout.vertical,
      );
      for (final n in nodes) {
        doc.updateItem(n.copyWith(position: origin + result.positions[n.id]!));
      }
      for (final frame in frames) {
        final rect = result.groups[frame.id];
        if (rect == null) continue;
        doc.updateItem(
          frame.copyWith(
            position: origin + rect.topLeft,
            width: rect.width,
            height: rect.height,
          ),
        );
      }
    } else {
      final positions = layoutDiagram(
        ids: [for (final n in nodes) n.id],
        sizes: sizes,
        edges: edges,
        layout: layout ?? DiagramLayout.horizontal,
      );
      for (final n in nodes) {
        doc.updateItem(n.copyWith(position: origin + positions[n.id]!));
      }
    }
    return nodes.length;
  }

  /// Trazos a mano alzada: los puntos llegan en una cuadrícula 0–100 y se escalan al lienzo.
  Future<Json> _drawSketch(Json args) async {
    final paths = parseSketchPaths(args['strokes']);
    final size = _num(args, 'size') ?? 320;
    final explicit = _offset(args);

    return bridge
        .edit(
          _int(args, 'canvas_id'),
          (doc) {
            final origin = explicit ?? _freeOrigin(doc, Size(size, size));
            final (strokes, bounds) = placeSketchPaths(
              paths,
              origin: origin,
              size: size,
              nextId: doc.allocateStrokeId,
            );
            for (final stroke in strokes) {
              doc.addStroke(stroke);
            }
            return (strokes: strokes.length, bounds: bounds);
          },
          reveal: (r, doc) => r.bounds,
          summary: (r) => 'Dibujó ${r.strokes} trazos',
        )
        .then((r) => {'strokes': r.strokes, 'bounds': _rectJson(r.bounds)});
  }

  static List<({String id, String title, Color? color, String? icon})> _groups(
    Object? raw,
  ) {
    if (raw is! List) return const [];
    return [
      for (final g in raw)
        if (g is Map && g['id'] != null)
          (
            id: '${g['id']}',
            title: '${g['title'] ?? g['id']}',
            color: _color(g['color'] as String?, ink: false),
            icon: canvasIcons.containsKey(g['icon'])
                ? g['icon']! as String
                : null,
          ),
    ];
  }

  Future<Json> _addElements(Json args) async {
    final specs = _specs(args['elements'], 'elements');
    if (specs.isEmpty) throw const McpToolError('elements está vacío.');
    final connections = _connections(args['connections']);

    return bridge
        .edit(
          _int(args, 'canvas_id'),
          (doc) {
            // Los que no traen posición se reparten en una cuadrícula junto al contenido existente.
            final loose = [
              for (final s in specs)
                if (s.position == null) s,
            ];
            final looseRefs = [for (final (i, _) in loose.indexed) '$i'];
            final sizes = {
              for (final (i, s) in loose.indexed)
                '$i': canvasItemSize(s.prototype),
            };
            final grid = loose.isEmpty
                ? const <String, Offset>{}
                : layoutDiagram(
                    ids: looseRefs,
                    sizes: sizes,
                    edges: const [],
                    layout: loose.length <= 4
                        ? DiagramLayout.horizontal
                        : DiagramLayout.grid,
                    gapMain: 60,
                  );
            var extent = Rect.zero;
            for (final ref in looseRefs) {
              extent = extent.expandToInclude(grid[ref]! & sizes[ref]!);
            }
            final origin = _freeOrigin(doc, extent.size);

            final created = <String, CanvasItem>{};
            final out = <Json>[];
            for (final spec in specs) {
              final position =
                  spec.position ?? origin + grid['${loose.indexOf(spec)}']!;
              final item = doc.addItem(
                spec.prototype.copyWith(position: position),
                select: false,
              );
              if (spec.ref != null) created[spec.ref!] = item;
              created[item.id] = item;
              out.add({
                if (spec.ref != null) 'ref': spec.ref,
                ..._describe(doc, item),
              });
            }
            final links = _applyConnections(doc, connections, created);
            return (
              items: out,
              links: links.$1,
              warnings: links.$2,
              ids: [for (final o in out) o['id']! as String],
            );
          },
          reveal: (r, doc) => _boundsOf(doc, r.ids),
          summary: (r) => r.ids.length == 1
              ? 'Añadió 1 elemento'
              : 'Añadió ${r.ids.length} elementos',
        )
        .then(
          (r) => {
            'created': r.items,
            'connections': r.links,
            if (r.warnings.isNotEmpty) 'warnings': r.warnings,
          },
        );
  }

  Future<Json> _updateElement(Json args) async {
    final elementId =
        _string(args, 'element_id') ??
        (throw const McpToolError('Falta element_id.'));
    return bridge.edit(
      _int(args, 'canvas_id'),
      (doc) {
        final id = _resolve(doc, const {}, elementId);
        final item =
            (id == null ? null : doc.itemById(id)) ??
            (throw McpToolError(
              'No existe el elemento $elementId. Usa get_canvas para ver los ids.',
            ));
        final shape = _enum(ShapeKind.values, args['shape']);
        final isInk =
            item.type == CanvasItemType.text ||
            ((shape ?? item.shape).isStroke &&
                item.type == CanvasItemType.shape);
        final iconKey = _string(args, 'icon');
        final updated = item.copyWith(
          title: _string(args, 'title'),
          subtitle: _string(args, 'body'),
          label: _string(args, 'label'),
          iconKey: iconKey != null && canvasIcons.containsKey(iconKey)
              ? iconKey
              : null,
          color: _color(_string(args, 'color'), ink: isInk),
          scale: _scale(_string(args, 'size')),
          shape: item.type == CanvasItemType.shape ? shape : null,
          active: args['active'] as bool?,
          target: _noteTarget(args),
          clearTarget: args['clear_note'] == true,
          position: Offset(
            _num(args, 'x') ?? item.position.dx,
            _num(args, 'y') ?? item.position.dy,
          ),
        );
        doc.updateItem(updated);
        return _describe(doc, updated);
      },
      reveal: (r, doc) => _boundsOf(doc, [r['id']! as String]),
      summary: (r) => 'Editó "${r['title'] ?? r['id']}"',
    );
  }

  Future<Json> _connect(Json args) async {
    final spec = _connections([args]).single;
    return bridge.edit(_int(args, 'canvas_id'), (doc) {
      final (links, warnings) = _applyConnections(doc, [spec], const {});
      if (links.isEmpty) throw McpToolError(warnings.join(' '));
      return links.single;
    }, summary: (_) => 'Conectó dos elementos');
  }

  Future<Json> _delete(Json args) async {
    final ids = {
      for (final id in (args['ids'] as List? ?? const [])) id.toString(),
    };
    if (ids.isEmpty) throw const McpToolError('ids está vacío.');
    return bridge.edit(
      _int(args, 'canvas_id'),
      (doc) => {'deleted': doc.removeByIds(ids)},
      summary: (r) => 'Borró ${r['deleted']} elementos',
    );
  }

  // ---------------------------------------------------------------------------
  // Utilidades
  // ---------------------------------------------------------------------------

  /// Conexiones válidas creadas y avisos por las que no se pudieron crear.
  (List<Json>, List<String>) _applyConnections(
    CanvasDocument doc,
    List<_ConnectionSpec> specs,
    Map<String, CanvasItem> refs,
  ) {
    final out = <Json>[];
    final warnings = <String>[];
    for (final c in specs) {
      final from = _resolve(doc, refs, c.from);
      final to = _resolve(doc, refs, c.to);
      if (from == null || to == null) {
        warnings.add(
          'Conexión ${c.from} → ${c.to} ignorada: no existe ${from == null ? c.from : c.to}.',
        );
        continue;
      }
      if (from == to) {
        warnings.add(
          'Conexión ${c.from} → ${c.to} ignorada: un elemento no se conecta consigo mismo.',
        );
        continue;
      }
      var link = doc.addLink(
        from,
        to,
        label: c.label ?? '',
        style: c.style ?? LinkStyle.curved,
        arrow: c.arrow ?? LinkArrow.end,
      )!;
      // Ya existía: se actualiza con lo pedido.
      final wanted = link.copyWith(
        from: from,
        to: to,
        label: c.label ?? link.label,
        style: c.style ?? link.style,
        arrow: c.arrow ?? link.arrow,
      );
      if (wanted != link) {
        doc.updateLink(wanted);
        link = wanted;
      }
      out.add({
        'id': link.id,
        'from': link.from,
        'to': link.to,
        if (link.label.isNotEmpty) 'label': link.label,
      });
    }
    return (out, warnings);
  }

  /// Acepta un ref recién creado, un id del lienzo o el título del elemento (lo más natural al editar),
  /// aunque no lo escriba igual: "motor de operaciones" encuentra "Motor de Operaciones".
  static String? _resolve(
    CanvasDocument doc,
    Map<String, CanvasItem> refs,
    String reference,
  ) {
    final byRef = refs[reference]?.id ?? doc.itemById(reference)?.id;
    if (byRef != null) return byRef;
    final needle = normalize(reference.trim());
    if (needle.isEmpty) return null;
    final exact = [
      for (final i in doc.items)
        if (normalize(i.title.trim()) == needle) i,
    ];
    if (exact.length == 1) return exact.single.id;
    final wanted = keywords(reference);
    if (wanted.isEmpty) return null;
    CanvasItem? best;
    var bestScore = 0.0;
    var tie = false;
    for (final item in doc.items) {
      if (item.title.isEmpty) continue;
      final value = overlap(wanted, keywords(item.title));
      if (value > bestScore) {
        bestScore = value;
        best = item;
        tie = false;
      } else if (value == bestScore && value > 0) {
        tie = true;
      }
    }
    return bestScore >= 0.6 && !tie ? best?.id : null;
  }

  /// ¿Ya hay en el lienzo un diagrama que habla de lo mismo? Se mira el título y, si no,
  /// si los nodos que pide la IA son los que ya están dibujados.
  static CanvasItem? _similarDiagram(
    CanvasDocument doc,
    String title,
    List<_ElementSpec> nodes,
  ) {
    final heads = <String, CanvasItem>{};
    final members = <String, List<CanvasItem>>{};
    for (final item in doc.items) {
      final group = item.group;
      if (group == null) continue;
      members.putIfAbsent(group, () => []).add(item);
      if (item.type == CanvasItemType.text)
        heads.putIfAbsent(group, () => item);
    }
    if (members.isEmpty) return null;

    final wanted = keywords(title);
    final mine = keywords([for (final n in nodes) n.prototype.title].join(' '));
    CanvasItem? best;
    var bestScore = 0.0;
    for (final MapEntry(key: group, value: items) in members.entries) {
      final head = heads[group];
      var value = head == null || wanted.isEmpty
          ? 0.0
          : overlap(wanted, keywords(head.title));
      if (value < 0.5) {
        // Títulos distintos: aun así es el mismo diagrama si vuelve a dibujar los mismos nodos.
        final theirs = keywords([for (final i in items) i.title].join(' '));
        final same = overlap(mine, theirs);
        if (same >= 0.6) value = same;
      }
      if (value > bestScore) {
        bestScore = value;
        best = head ?? items.first;
      }
    }
    return bestScore >= 0.5 ? best : null;
  }

  /// Hueco libre para [size]: a la derecha del contenido existente, o centrado en el origen si está vacío.
  static Offset _freeOrigin(CanvasDocument doc, Size size) {
    final bounds = doc.contentBounds;
    if (bounds == null) return Offset(-size.width / 2, -size.height / 2);
    return Offset(bounds.right + 200, bounds.top);
  }

  static Rect? _boundsOf(CanvasDocument doc, List<String> ids) {
    Rect? r;
    for (final id in ids) {
      final item = doc.itemById(id);
      if (item == null) continue;
      final rect = doc.itemRect(item);
      r = r?.expandToInclude(rect) ?? rect;
    }
    return r;
  }

  static Json _describe(CanvasDocument doc, CanvasItem item) {
    final rect = doc.itemRect(item);
    return {
      'id': item.id,
      'type': _typeName(item.type),
      if (item.title.isNotEmpty) 'title': item.title,
      if (item.subtitle.isNotEmpty) 'body': item.subtitle,
      if (item.bullets.isNotEmpty) 'bullets': item.bullets,
      if (item.group != null) 'diagram': item.group,
      if (item.label.isNotEmpty) 'label': item.label,
      if (item.type == CanvasItemType.shape) 'shape': item.shape.name,
      if (item.iconKey != null) 'icon': item.iconKey,
      if (item.color != null) 'color': _colorName(item.color!),
      if (item.scale != ItemScale.medium) 'size': item.scale.label,
      if (item.active) 'active': true,
      if (item.target != null) 'target': item.target,
      if (item.target?.startsWith('note:') == true)
        'note_id': int.tryParse(item.target!.substring(5)),
      ..._rectJson(rect),
    };
  }

  static Json _rectJson(Rect r) => {
    'x': r.left.roundToDouble(),
    'y': r.top.roundToDouble(),
    'width': r.width.roundToDouble(),
    'height': r.height.roundToDouble(),
  };

  static String _typeName(CanvasItemType t) => switch (t) {
    CanvasItemType.sticky => 'note',
    CanvasItemType.node => 'step',
    CanvasItemType.card => 'card',
    CanvasItemType.shape => 'shape',
    CanvasItemType.text => 'text',
    CanvasItemType.icon => 'icon',
    CanvasItemType.wireframe => 'wireframe',
    CanvasItemType.paragraph => 'paragraph',
    CanvasItemType.checklist => 'checklist',
    CanvasItemType.link => 'link',
    CanvasItemType.frame => 'frame',
  };

  static List<_ElementSpec> _specs(Object? raw, String field) {
    if (raw is! List) throw McpToolError('$field debe ser una lista.');
    return [
      for (final (i, e) in raw.indexed)
        if (e is Map)
          _ElementSpec.parse(e.cast<String, Object?>(), i)
        else
          throw McpToolError('$field[$i] no es un objeto.'),
    ];
  }

  static List<_ConnectionSpec> _connections(Object? raw) {
    if (raw == null) return const [];
    if (raw is! List)
      throw const McpToolError('Las conexiones deben ser una lista.');
    return [
      for (final e in raw)
        if (e is Map)
          _ConnectionSpec(
            from: '${e['from'] ?? ''}',
            to: '${e['to'] ?? ''}',
            label: e['label'] as String?,
            style: _enum(LinkStyle.values, e['style']),
            arrow: _enum(LinkArrow.values, e['arrow']),
          ),
    ];
  }
}

class _ElementSpec {
  const _ElementSpec(this.ref, this.prototype, this.position, this.group);

  final String? ref;
  final CanvasItem prototype;
  final Offset? position;

  /// Capa o carril al que pertenece dentro del diagrama.
  final String? group;

  static _ElementSpec parse(Json json, int index) {
    final rawType = (_string(json, 'type') ?? '').toLowerCase();
    final rawRef = _string(json, 'ref');
    final shapeFromType = _enum(
      ShapeKind.values,
      rawType == 'circle' ? 'ellipse' : rawType,
    );
    final type = switch (rawType) {
      'note' || 'nota' || 'sticky' => CanvasItemType.sticky,
      'card' || 'tarjeta' => CanvasItemType.card,
      'step' || 'node' || 'paso' || 'process' => CanvasItemType.node,
      'text' ||
      'texto' ||
      'title' ||
      'titulo' ||
      'título' => CanvasItemType.text,
      'icon' || 'icono' => CanvasItemType.icon,
      'shape' || 'forma' => CanvasItemType.shape,
      'paragraph' || 'parrafo' || 'párrafo' => CanvasItemType.paragraph,
      'checklist' || 'tareas' || 'lista' => CanvasItemType.checklist,
      'link' || 'enlace' => CanvasItemType.link,
      _ when shapeFromType != null || rawType == 'circle' =>
        CanvasItemType.shape,
      _ => throw McpToolError(
        'Elemento $index: tipo "$rawType" desconocido '
        '(note, card, step, shape, text, icon, paragraph, checklist, link).',
      ),
    };
    final shape =
        _enum(
          ShapeKind.values,
          json['shape'] == 'circle' ? 'ellipse' : json['shape'],
        ) ??
        shapeFromType ??
        ShapeKind.rectangle;
    final isInk =
        type == CanvasItemType.text ||
        (type == CanvasItemType.shape && shape.isStroke);
    final iconKey = _string(json, 'icon');
    final rawTitle = (_string(json, 'title') ?? '').trim();
    final body = _string(json, 'body') ?? _string(json, 'subtitle') ?? '';
    final rawLabel = (_string(json, 'label') ?? '').trim();
    final bullets = [
      for (final b in (json['bullets'] as List? ?? const [])) '$b',
    ];

    // Estos dos guardan su contenido en `title`, no en `subtitle`:
    // el párrafo, el texto entero; la lista, una tarea por línea.
    final parsedTitle = switch (type) {
      CanvasItemType.paragraph => [
        rawTitle,
        body,
      ].where((t) => t.trim().isNotEmpty).join('\n\n'),
      CanvasItemType.checklist when bullets.isNotEmpty => bullets.join('\n'),
      _ => rawTitle,
    };
    final needsConcreteTitle =
        type == CanvasItemType.card || type == CanvasItemType.node;
    final bodyAsTitle =
        needsConcreteTitle &&
        parsedTitle.isEmpty &&
        body.trim().isNotEmpty &&
        body.trim().length <= 72;
    final labelAsTitle =
        needsConcreteTitle && parsedTitle.isEmpty && !bodyAsTitle;
    final title = bodyAsTitle
        ? body.trim()
        : labelAsTitle && rawLabel.isNotEmpty
        ? rawLabel
        : needsConcreteTitle && parsedTitle.isEmpty
        ? _diagramTitle(body, rawRef)
        : parsedTitle;
    final subtitle = bodyAsTitle ? '' : body;
    final label = labelAsTitle && title == rawLabel ? '' : rawLabel;

    final prototype = CanvasItem(
      id: 'template',
      type: type,
      position: Offset.zero,
      title: type == CanvasItemType.sticky && title.isEmpty
          ? 'Nueva idea'
          : title,
      subtitle: type == CanvasItemType.paragraph ? '' : subtitle,
      label: label.isNotEmpty
          ? label
          : (type == CanvasItemType.sticky ? 'NOTA' : ''),
      iconKey: iconKey != null && canvasIcons.containsKey(iconKey)
          ? iconKey
          : (type == CanvasItemType.icon ? 'star' : null),
      color: _color(_string(json, 'color'), ink: isInk),
      scale: _scale(_string(json, 'size')) ?? ItemScale.medium,
      shape: shape,
      active: json['active'] as bool? ?? false,
      bullets: type == CanvasItemType.checklist ? const [] : bullets,
      checks: type == CanvasItemType.checklist
          ? List.filled(bullets.length, false)
          : const [],
      target: _noteTarget(json),
    );
    return _ElementSpec(
      rawRef,
      prototype,
      _offset(json),
      _string(json, 'group'),
    );
  }
}

String _diagramTitle(String body, String? ref) {
  final firstLine = body
      .trim()
      .split(RegExp(r'[\n.!?]'))
      .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '')
      .trim();
  if (firstLine.isNotEmpty) {
    return firstLine.length <= 64
        ? firstLine
        : '${firstLine.substring(0, 61).trimRight()}…';
  }
  final words = (ref ?? '')
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty);
  final title = words
      .map(
        (word) => word.length == 1
            ? word.toUpperCase()
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');
  return title.isEmpty ? 'Detalle del diagrama' : title;
}

class _ConnectionSpec {
  const _ConnectionSpec({
    required this.from,
    required this.to,
    this.label,
    this.style,
    this.arrow,
  });

  final String from;
  final String to;
  final String? label;
  final LinkStyle? style;
  final LinkArrow? arrow;
}

String? _string(Json json, String key) {
  final v = json[key];
  return v == null ? null : '$v';
}

double? _num(Json json, String key) {
  final v = json[key];
  return v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
}

int? _int(Json json, String key) {
  final v = json[key];
  return v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
}

String? _noteTarget(Json json) {
  final id = _int(json, 'note_id');
  return id == null ? null : 'note:$id';
}

Offset? _offset(Json json) {
  final x = _num(json, 'x'), y = _num(json, 'y');
  return x == null || y == null ? null : Offset(x, y);
}

T? _enum<T extends Enum>(List<T> values, Object? raw) =>
    raw == null ? null : values.asNameMap()['$raw'.toLowerCase()];

ItemScale? _scale(String? raw) => switch (raw?.toUpperCase()) {
  'S' || 'SMALL' => ItemScale.small,
  'M' || 'MEDIUM' => ItemScale.medium,
  'L' || 'LARGE' => ItemScale.large,
  _ => null,
};

final _fillAliases = {
  'blanco': KraftColors.surfaceContainerLowest,
  'white': KraftColors.surfaceContainerLowest,
  'amarillo': KraftColors.primaryContainer,
  'yellow': KraftColors.primaryContainer,
  'verde': KraftColors.secondaryContainer,
  'green': KraftColors.secondaryContainer,
  'menta': KraftColors.secondaryContainer,
  'cian': KraftColors.tertiaryContainer,
  'cyan': KraftColors.tertiaryContainer,
  'azul': KraftColors.tertiaryContainer,
  'blue': KraftColors.tertiaryContainer,
  'rosa': KraftColors.errorContainer,
  'pink': KraftColors.errorContainer,
  'rojo': KraftColors.errorContainer,
  'red': KraftColors.errorContainer,
  'gris': KraftColors.surfaceContainerHigh,
  'gray': KraftColors.surfaceContainerHigh,
  'grey': KraftColors.surfaceContainerHigh,
};

final _inkAliases = {
  'negro': KraftColors.ink,
  'black': KraftColors.ink,
  'oliva': KraftColors.primary,
  'olive': KraftColors.primary,
  'amarillo': KraftColors.primary,
  'yellow': KraftColors.primary,
  'verde': KraftColors.secondary,
  'green': KraftColors.secondary,
  'azul': KraftColors.tertiary,
  'blue': KraftColors.tertiary,
  'cian': KraftColors.tertiary,
  'cyan': KraftColors.tertiary,
  'rojo': KraftColors.error,
  'red': KraftColors.error,
  'rosa': KraftColors.error,
  'pink': KraftColors.error,
};

Color? _color(String? raw, {required bool ink}) {
  if (raw == null) return null;
  final key = raw.trim().toLowerCase();
  final named = (ink ? _inkAliases : _fillAliases)[key];
  if (named != null) return named;
  final hex = RegExp(r'^#?([0-9a-f]{6})$').firstMatch(key)?.group(1);
  return hex == null ? null : Color(0xFF000000 | int.parse(hex, radix: 16));
}

String _colorName(Color color) {
  for (final (c, name) in [...canvasFillColors, ...canvasInkColors]) {
    if (c == color) return name.toLowerCase();
  }
  return '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}

/// Un trazo pedido por la IA, todavía en su cuadrícula propia de 0 a 100.
class SketchPath {
  const SketchPath({
    required this.points,
    required this.color,
    required this.width,
  });

  final List<Offset> points;
  final Color color;
  final double width;
}

/// Lee el `strokes` que manda la IA (puntos `[[x, y], …]` de 0 a 100, color y grosor).
/// Lo comparten el lienzo (`draw_sketch`) y las notas (`sketch_note`).
List<SketchPath> parseSketchPaths(Object? raw) {
  if (raw is! List || raw.isEmpty)
    throw const McpToolError('Faltan los trazos (strokes).');
  final paths = <SketchPath>[];
  for (final stroke in raw) {
    if (stroke is! Map) continue;
    final points = [
      for (final p in (stroke['points'] as List? ?? const []))
        if (p is List && p.length >= 2)
          Offset((p[0]! as num).toDouble(), (p[1]! as num).toDouble()),
    ];
    if (points.length < 2) continue;
    paths.add(
      SketchPath(
        points: points,
        color: _color(stroke['color'] as String?, ink: true) ?? KraftColors.ink,
        width: ((stroke['width'] as num?)?.toDouble() ?? 3).clamp(1.0, 12.0),
      ),
    );
  }
  if (paths.isEmpty)
    throw const McpToolError('Cada trazo necesita al menos dos puntos.');
  return paths;
}

/// Escala la cuadrícula 0–100 a [size] y la coloca en [origin]. Devuelve los trazos y lo que ocupan.
(List<Stroke>, Rect) placeSketchPaths(
  List<SketchPath> paths, {
  required Offset origin,
  required double size,
  required int Function() nextId,
}) {
  final scale = size / 100;
  var bounds = Rect.fromLTWH(origin.dx, origin.dy, 1, 1);
  final strokes = <Stroke>[];
  for (final path in paths) {
    final points = [for (final p in path.points) origin + p * scale];
    for (final p in points) {
      bounds = bounds.expandToInclude(
        Rect.fromCircle(center: p, radius: path.width),
      );
    }
    strokes.add(
      Stroke(
        id: nextId(),
        points: points,
        color: path.color,
        width: path.width,
      ),
    );
  }
  return (strokes, bounds);
}
