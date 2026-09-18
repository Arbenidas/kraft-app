import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kraft/data/db/database.dart';
import 'package:kraft/data/repositories.dart';
import 'package:kraft/features/ai/ai_providers.dart';
import 'package:kraft/features/ai/canvas_bridge.dart';
import 'package:kraft/features/ai/canvas_tools.dart';
import 'package:kraft/features/ai/diagram_layout.dart';
import 'package:kraft/features/ai/mcp_server.dart';
import 'package:kraft/features/canvas/canvas_codec.dart';
import 'package:kraft/features/canvas/canvas_items.dart';
import 'package:kraft/features/canvas/canvas_models.dart';
import 'package:kraft/theme/kraft_colors.dart';
import 'package:kraft/features/canvas/canvas_screen.dart';
import 'package:kraft/features/notes/note_bridge.dart';
import 'package:kraft/features/voice/assistant_tools.dart';

import 'helpers.dart';

const _flow = {
  'layout': 'horizontal',
  'title': 'Onboarding',
  'nodes': [
    {
      'ref': 'inicio',
      'type': 'step',
      'title': 'Descarga',
      'icon': 'smartphone',
    },
    {
      'ref': 'registro',
      'type': 'card',
      'title': 'Registro',
      'color': 'verde',
      'note_id': 42,
    },
    {'ref': 'decide', 'type': 'shape', 'shape': 'diamond', 'title': '¿Email?'},
    {'ref': 'fin', 'type': 'note', 'title': 'Listo', 'color': 'amarillo'},
  ],
  'edges': [
    {'from': 'inicio', 'to': 'registro'},
    {'from': 'registro', 'to': 'decide'},
    {'from': 'decide', 'to': 'fin', 'label': 'sí'},
    {'from': 'decide', 'to': 'nada'},
  ],
};

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  test(
    'layout horizontal: cada nivel queda a la derecha del anterior y sin solaparse',
    () {
      final sizes = {
        for (final id in ['a', 'b', 'c', 'd']) id: const Size(200, 120),
      };
      final p = layoutDiagram(
        ids: sizes.keys.toList(),
        sizes: sizes,
        edges: const [('a', 'b'), ('a', 'c'), ('b', 'd'), ('c', 'd')],
        layout: DiagramLayout.horizontal,
      );
      expect(p['b']!.dx, greaterThan(p['a']!.dx + 200));
      expect(p['d']!.dx, greaterThan(p['b']!.dx + 200));
      expect(p['b']!.dx, p['c']!.dx);
      expect((p['b']! & sizes['b']!).overlaps(p['c']! & sizes['c']!), isFalse);
      expect(p.values.map((o) => o.dx).reduce((a, b) => a < b ? a : b), 0);

      final mind = layoutDiagram(
        ids: sizes.keys.toList(),
        sizes: sizes,
        edges: const [('a', 'b'), ('a', 'c'), ('a', 'd')],
        layout: DiagramLayout.mindmap,
      );
      expect(mind['b']!.dx, greaterThan(mind['a']!.dx), reason: 'rama derecha');
      expect(mind['c']!.dx, lessThan(mind['a']!.dx), reason: 'rama izquierda');
    },
  );

  group('protocolo', () {
    late AppDatabase db;
    late CanvasesRepository repo;
    late CanvasBridge bridge;
    late AssistantTools assistantTools;
    late McpProtocol protocol;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory(), seed: false);
      repo = CanvasesRepository(db);
      bridge = CanvasBridge(repo);
      assistantTools = AssistantTools(
        notes: NotesRepository(db),
        tasks: TasksRepository(db),
        projects: ProjectsRepository(db),
        workItems: WorkItemsRepository(db),
        noteBridge: NoteBridge(),
        canvasBridge: bridge,
        canvasTools: KraftCanvasTools(bridge: bridge, canvases: repo),
      );
      protocol = McpProtocol(assistantTools);
    });
    tearDown(() async {
      bridge.dispose();
      await db.close();
    });

    Future<Map<String, Object?>> rpc(
      String method, [
      Map<String, Object?>? params,
    ]) async => (await protocol.handle({
      'jsonrpc': '2.0',
      'id': 1,
      'method': method,
      'params': ?params,
    }))!;

    Future<Map<String, Object?>> tool(
      String name,
      Map<String, Object?> args,
    ) async {
      final result =
          (await rpc('tools/call', {
                'name': name,
                'arguments': args,
              }))['result']!
              as Map<String, Object?>;
      final text =
          ((result['content']! as List).single as Map)['text']! as String;
      if (result['isError'] == true) throw McpToolError(text);
      return jsonDecode(text) as Map<String, Object?>;
    }

    test('initialize negocia versión y lista las herramientas', () async {
      final init =
          (await rpc('initialize', {
                'protocolVersion': '2025-03-26',
                'clientInfo': {'name': 'test'},
              }))['result']!
              as Map;
      expect(init['protocolVersion'], '2025-03-26');
      expect(
        await protocol.handle({
          'jsonrpc': '2.0',
          'method': 'notifications/initialized',
        }),
        isNull,
      );

      final tools =
          ((await rpc('tools/list'))['result']! as Map)['tools']! as List;
      expect(
        tools.map((t) => (t as Map)['name']),
        containsAll([
          'create_diagram',
          'add_elements',
          'get_canvas',
          'connect_elements',
          'save_task',
          'save_tasks',
          'delete_work',
        ]),
      );
      expect((await rpc('nope'))['error'], isNotNull);
    });

    test(
      'MCP crea, edita y elimina una subtarea de un requerimiento',
      () async {
        final project = await tool('create_project', {'title': 'Proyecto MCP'});
        final projectId = project['project_id']! as int;
        final requirement = await tool('save_project_work', {
          'project_id': projectId,
          'kind': 'requirement',
          'title': 'Tarea principal',
        });
        final requirementId = requirement['id']! as int;

        final created = await tool('save_task', {
          'project_id': projectId,
          'requirement_id': requirementId,
          'title': 'Investigar alternativa',
        });
        final taskId = created['task_id']! as int;
        final edited = await tool('save_task', {
          'task_id': taskId,
          'title': 'Investigar alternativa y documentar',
          'done': true,
        });
        expect(edited['done'], isTrue);

        final detail = await tool('get_requirement', {
          'requirement_id': requirementId,
        });
        expect(
          (detail['tasks']! as List).single,
          containsPair('task_id', taskId),
        );
        await tool('delete_work', {'task_id': taskId});
        expect(await TasksRepository(db).get(taskId), isNull);
      },
    );

    test('close_view pide al navegador cerrar la vista actual', () async {
      String? requestedView;
      assistantTools.openViewHandler = (view, _, {int? requirementId}) async {
        requestedView = view;
      };

      expect(await tool('close_view', const {}), {'closed': true});
      expect(requestedView, 'close');
    });

    test(
      'create_diagram en un lienzo cerrado lo ordena, conecta y guarda',
      () async {
        final id = await repo.create(title: 'Producto');
        final result = await tool('create_diagram', {
          'canvas_id': id,
          ..._flow,
        });

        expect(result['created'], hasLength(5), reason: 'título + 4 nodos');
        expect(result['connections'], hasLength(3));
        expect((result['warnings']! as List).single, contains('nada'));

        final saved = CanvasCodec.decode((await repo.get(id))!.data);
        expect(saved.items, hasLength(5));
        expect(saved.links.firstWhere((l) => l.label == 'sí'), isNotNull);
        final byTitle = {for (final i in saved.items) i.title: i};
        expect(
          byTitle['Registro']!.position.dx,
          greaterThan(byTitle['Descarga']!.position.dx),
        );
        expect(
          byTitle['¿Email?']!.position.dx,
          greaterThan(byTitle['Registro']!.position.dx),
        );
        expect(
          saved.viewCenter,
          isNotNull,
          reason: 'al abrirlo se ve el diagrama',
        );

        // Un segundo diagrama no tapa el primero.
        final again = await tool('add_elements', {
          'canvas_id': id,
          'elements': [
            {'type': 'note', 'title': 'Otra idea'},
          ],
        });
        final note = (again['created']! as List).single as Map;
        final firstRight = saved.items
            .map((i) => i.position.dx)
            .reduce((a, b) => a > b ? a : b);
        expect(note['x']! as num, greaterThan(firstRight));

        final read = await tool('get_canvas', {'canvas_id': id});
        expect(read['elements'], hasLength(6));
        final registro = (read['elements']! as List).cast<Map>().firstWhere(
          (e) => e['title'] == 'Registro',
        );
        expect(registro['color'], 'verde');
        expect(registro['note_id'], 42);
        expect(
          saved.items.firstWhere((i) => i.title == 'Registro').target,
          'note:42',
        );

        await tool('update_element', {
          'canvas_id': id,
          'element_id': registro['id'],
          'title': 'Alta',
          'clear_note': true,
        });
        final cleared = CanvasCodec.decode(
          (await repo.get(id))!.data,
        ).items.firstWhere((i) => i.title == 'Alta');
        expect(cleared.target, isNull);
        final deleted = await tool('delete_elements', {
          'canvas_id': id,
          'ids': [registro['id']],
        });
        expect(
          deleted['deleted'],
          3,
          reason: 'el elemento y sus dos conexiones',
        );
      },
    );

    test(
      'una tarjeta sin title recibe un nombre útil y conserva su jerarquía',
      () async {
        final id = await repo.create(title: 'Passkeys');
        await tool('create_diagram', {
          'canvas_id': id,
          'nodes': [
            {
              'ref': 'gestor_nativo',
              'type': 'card',
              'label': 'GESTOR NATIVO',
              'body': 'Credential Manager y ASAuthorizationController',
              'size': 'L',
            },
          ],
        });

        final item = CanvasCodec.decode(
          (await repo.get(id))!.data,
        ).items.single;
        expect(item.title, 'Credential Manager y ASAuthorizationController');
        expect(item.title, isNot('Tarjeta'));
        expect(item.subtitle, isEmpty);
        expect(item.scale, ItemScale.large);
      },
    );

    test(
      'un diagrama con capas dibuja marcos y no se duplica; edit_diagram lo modifica',
      () async {
        final id = await repo.create(title: 'Arquitectura');
        Future<Map<String, Object?>> architecture({bool replace = false}) =>
            tool('create_diagram', {
              'canvas_id': id,
              'title': 'Arquitectura limpia',
              if (replace) 'replace': true,
              'groups': [
                {'id': 'ui', 'title': 'Presentación', 'color': 'cian'},
                {'id': 'dominio', 'title': 'Dominio', 'color': 'amarillo'},
                {'id': 'datos', 'title': 'Datos', 'color': 'verde'},
              ],
              'nodes': [
                {
                  'ref': 'pantalla',
                  'type': 'card',
                  'group': 'ui',
                  'title': 'CalculadoraPage',
                  'bullets': ['Teclado', 'Muestra el resultado'],
                },
                {
                  'ref': 'caso',
                  'type': 'card',
                  'group': 'dominio',
                  'title': 'CalcularOperacion',
                  'bullets': ['Valida', 'Devuelve Result'],
                },
                {
                  'ref': 'repo',
                  'type': 'card',
                  'group': 'datos',
                  'title': 'HistorialRepository',
                  'bullets': ['SQLite'],
                },
              ],
              'edges': [
                {'from': 'pantalla', 'to': 'caso', 'label': 'usa'},
                {'from': 'caso', 'to': 'repo', 'label': 'guarda'},
              ],
            });

        await architecture();
        final saved = CanvasCodec.decode((await repo.get(id))!.data);
        expect(
          saved.items.where((i) => i.type == CanvasItemType.frame),
          hasLength(3),
          reason: 'un marco por capa',
        );
        final card = saved.items.firstWhere(
          (i) => i.title == 'CalculadoraPage',
        );
        expect(card.bullets, ['Teclado', 'Muestra el resultado']);
        expect(saved.links, hasLength(2));

        // Cada capa contiene sus tarjetas.
        Rect rect(CanvasItem i) => i.position & canvasItemSize(i);
        final ui = saved.items.firstWhere((i) => i.title == 'Presentación');
        expect(rect(ui).contains(rect(card).center), isTrue);

        // Pedir lo mismo otra vez no duplica: obliga a editar.
        expect(
          architecture(),
          throwsA(
            isA<McpToolError>().having(
              (e) => e.message,
              'message',
              contains('edit_diagram'),
            ),
          ),
        );

        // Y tampoco cambiándole el nombre al mismo tema (el caso real: "limpia" → "tecnológica").
        expect(
          tool('create_diagram', {
            'canvas_id': id,
            'title': 'Arquitectura Tecnológica Calculadora',
            'nodes': [
              {'ref': 'a', 'type': 'card', 'title': 'Interfaz de Usuario'},
              {'ref': 'b', 'type': 'card', 'title': 'Controller'},
            ],
            'edges': [
              {'from': 'a', 'to': 'b'},
            ],
          }),
          throwsA(
            isA<McpToolError>().having(
              (e) => e.message,
              'message',
              contains('Arquitectura limpia'),
            ),
          ),
        );

        // Editar: añade un nodo, cambia otro y reordena.
        final edited = await tool('edit_diagram', {
          'canvas_id': id,
          'add_nodes': [
            {
              'ref': 'modelo',
              'type': 'card',
              'title': 'Operacion',
              'bullets': ['Entidad inmutable'],
            },
          ],
          'update_nodes': [
            {
              'id': card.id,
              'bullets': ['Teclado', 'Historial', 'Accesibilidad'],
            },
          ],
          'add_edges': [
            {'from': 'CalcularOperacion', 'to': 'modelo'},
          ],
          'relayout': true,
        });
        expect(edited['warnings'], anyOf(isNull, isEmpty));
        final after = CanvasCodec.decode((await repo.get(id))!.data);
        expect(
          after.items.firstWhere((i) => i.id == card.id).bullets,
          hasLength(3),
        );
        expect(after.items.where((i) => i.title == 'Operacion'), hasLength(1));
        expect(
          after.items.where((i) => i.title == 'CalculadoraPage'),
          hasLength(1),
          reason: 'no duplica',
        );
        expect(after.links, hasLength(3));
      },
    );

    test('draw_sketch dibuja trazos escalados en el lienzo', () async {
      final id = await repo.create(title: 'Boceto');
      final result = await tool('draw_sketch', {
        'canvas_id': id,
        'size': 200,
        'x': 0,
        'y': 0,
        'strokes': [
          {
            'points': [
              [0, 0],
              [50, 50],
              [100, 0],
            ],
            'color': 'rojo',
            'width': 4,
          },
        ],
      });
      expect(result['strokes'], 1);
      final saved = CanvasCodec.decode((await repo.get(id))!.data);
      expect(saved.strokes.single.points, [
        const Offset(0, 0),
        const Offset(100, 100),
        const Offset(200, 0),
      ]);
      expect(saved.strokes.single.color, KraftColors.error);
    });

    test('sin lienzo abierto ni canvas_id devuelve un error útil', () async {
      expect(
        () => tool('add_elements', {
          'elements': [
            {'type': 'note'},
          ],
        }),
        throwsA(
          isA<McpToolError>().having(
            (e) => e.message,
            'message',
            contains('canvas_id'),
          ),
        ),
      );
      expect(
        () => tool('add_elements', {
          'canvas_id': 1,
          'elements': [
            {'type': 'robot'},
          ],
        }),
        throwsA(isA<McpToolError>()),
      );
    });
  });

  // flutter_test sustituye HttpClient por uno falso que siempre da 400: aquí hace falta el real.
  test(
    'servidor HTTP: exige el token y responde JSON-RPC',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final db = AppDatabase(NativeDatabase.memory(), seed: false);
      addTearDown(db.close);
      final repo = CanvasesRepository(db);
      final bridge = CanvasBridge(repo);
      addTearDown(bridge.dispose);
      final server = McpHttpServer(
        McpProtocol(
          AssistantTools(
            notes: NotesRepository(db),
            tasks: TasksRepository(db),
            projects: ProjectsRepository(db),
            workItems: WorkItemsRepository(db),
            noteBridge: NoteBridge(),
            canvasBridge: bridge,
            canvasTools: KraftCanvasTools(bridge: bridge, canvases: repo),
          ),
        ),
        token: 'secreto',
      );
      await server.start(port: 0, address: InternetAddress.loopbackIPv4);
      addTearDown(server.stop);
      final client = HttpClient();
      addTearDown(client.close);
      final url = Uri.parse('http://127.0.0.1:${server.port}/mcp');

      Future<(int, String)> post(Object body, {String? token}) async {
        final req = await client.postUrl(url);
        req.headers.contentType = ContentType.json;
        if (token != null) req.headers.set('Authorization', 'Bearer $token');
        req.write(jsonEncode(body));
        final res = await req.close();
        return (res.statusCode, await res.transform(utf8.decoder).join());
      }

      final ping = {'jsonrpc': '2.0', 'id': 7, 'method': 'ping'};
      expect((await post(ping)).$1, HttpStatus.unauthorized);
      expect((await post(ping, token: 'otro')).$1, HttpStatus.unauthorized);

      final (status, body) = await post(ping, token: 'secreto');
      expect(status, HttpStatus.ok);
      expect(jsonDecode(body), {
        'jsonrpc': '2.0',
        'id': 7,
        'result': <String, Object?>{},
      });

      expect(
        (await post({
          'jsonrpc': '2.0',
          'method': 'notifications/initialized',
        }, token: 'secreto')).$1,
        HttpStatus.accepted,
      );
    }, _RealHttp()),
  );

  testWidgets(
    'con el lienzo abierto la IA dibuja en vivo y se deshace de una vez',
    (tester) async {
      await pumpKraft(tester, size: const Size(1366, 1024));
      await openCanvasEditor(tester);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(CanvasScreen)),
      );
      final tools = container.read(mcpControllerProvider).tools;
      await tester.runAsync(
        () => tools.call('create_diagram', {
          'layout': 'vertical',
          'nodes': [
            {'ref': 'a', 'type': 'card', 'title': 'Idea IA'},
            {'ref': 'b', 'type': 'card', 'title': 'Prototipo IA'},
          ],
          'edges': [
            {'from': 'a', 'to': 'b'},
          ],
        }),
      );
      await tester.pump();
      expect(find.textContaining('IA · Diagrama'), findsOneWidget);
      await settle(tester);

      expect(find.text('Idea IA'), findsOneWidget);
      expect(find.text('Prototipo IA'), findsOneWidget);

      await tester.tap(find.byTooltip('Deshacer'));
      await tester.pumpAndSettle();
      expect(find.text('Idea IA'), findsNothing);
      expect(find.text('Prototipo IA'), findsNothing);
      expect(find.text('2. BIOMETRÍA'), findsOneWidget);
    },
  );
}

class _RealHttp extends HttpOverrides {}
