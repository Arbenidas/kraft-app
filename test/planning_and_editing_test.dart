import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kraft/data/db/database.dart';
import 'package:kraft/data/enums.dart';
import 'package:kraft/data/repositories.dart';
import 'package:kraft/features/canvas/canvas_document.dart';
import 'package:kraft/features/canvas/canvas_codec.dart';
import 'package:kraft/features/canvas/canvas_models.dart';
import 'package:kraft/features/notes/note_document.dart';
import 'package:kraft/features/notes/note_sketch_model.dart';
import 'package:kraft/features/ai/canvas_bridge.dart';
import 'package:kraft/features/ai/canvas_tools.dart';
import 'package:kraft/features/notes/note_bridge.dart';
import 'package:kraft/features/voice/assistant_tools.dart';
import 'package:kraft/features/voice/assistant_engine.dart';
import 'package:kraft/features/voice/compatible_chat.dart';
import 'package:kraft/platform/secure_store.dart';
import 'package:kraft/theme/kraft_colors.dart';

class MemoryKeys implements SecureStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  test(
    'mixed groups persist, move together, duplicate independently and ungroup with undo',
    () {
      final doc = CanvasDocument(
        items: [
          const CanvasItem(
            id: 'a',
            type: CanvasItemType.shape,
            position: Offset.zero,
          ),
          const CanvasItem(
            id: 'b',
            type: CanvasItemType.shape,
            position: Offset(300, 0),
          ),
        ],
        strokes: [
          Stroke(
            id: 1,
            points: [Offset.zero, const Offset(10, 10)],
            color: Colors.black,
            width: 3,
          ),
        ],
      );
      addTearDown(doc.dispose);
      doc.selectAll();
      doc.groupSelection();
      final encoded = CanvasCodec.decode(
        CanvasCodec.encode(CanvasData(items: doc.items, strokes: doc.strokes)),
      );
      expect(encoded.items.first.group, encoded.strokes.first.group);
      doc.clearSelection();
      doc.selectOnly(const CanvasHit.item('a'));
      expect(
        doc.selectionCount,
        1,
        reason: 'una cajita del grupo se mueve sola',
      );
      doc.selectAll();
      expect(doc.selectionCount, 3);
      doc.updateMove(const Offset(20, 30));
      doc.commitMove();
      expect(doc.items.last.position, const Offset(320, 30));
      expect(doc.strokes.first.points.first, const Offset(20, 30));
      doc.duplicateSelection();
      expect(doc.items.last.group, isNot(doc.items.first.group));
      doc.ungroupSelection();
      expect(doc.items.last.group, isNull);
      doc.undo();
      expect(doc.items.last.group, isNotNull);
    },
  );

  test('resize previews cancel, commit once and survive serialization', () {
    final doc = CanvasDocument(
      items: [
        const CanvasItem(
          id: 'a',
          type: CanvasItemType.shape,
          position: Offset.zero,
        ),
      ],
    );
    addTearDown(doc.dispose);
    doc.beginResize('a');
    doc.updateResize(2);
    doc.endResize(cancel: true);
    expect(doc.items.single.zoom, 1);
    expect(doc.canUndo, false);
    doc.beginResize('a');
    doc.updateResize(2);
    doc.updateResize(3);
    doc.endResize();
    expect(doc.items.single.zoom, 3);
    expect(
      CanvasCodec.decode(
        CanvasCodec.encode(CanvasData(items: doc.items)),
      ).items.single.zoom,
      3,
    );
    doc.undo();
    expect(doc.items.single.zoom, 1);
    expect(doc.canUndo, false);
    doc.redo();
    expect(doc.items.single.zoom, 3);
  });

  test(
    'embedded drawings survive note text edits and deep-copy serialization',
    () {
      final note = NoteDocument(
        text: 'Title',
        sketches: [
          NoteSketch(
            id: 's',
            data: CanvasData(
              items: [
                const CanvasItem(
                  id: 'a',
                  type: CanvasItemType.shape,
                  position: Offset(10, 20),
                ),
              ],
            ),
          ),
        ],
      );
      final copy = NoteDocument.decode(note.copyWith(text: 'Changed').encode());
      expect(copy.text, 'Changed');
      expect(copy.sketches.single.data.items.single.id, 'a');
      expect(
        identical(
          copy.sketches.single.data.items,
          note.sketches.single.data.items,
        ),
        false,
      );
    },
  );

  test(
    'foreground chooser maintains contrast for arbitrary fills in both themes',
    () {
      for (final brightness in Brightness.values) {
        KraftColors.use(brightness);
        for (final fill in [
          KraftColors.primaryContainer,
          KraftColors.secondaryContainer,
          KraftColors.surfaceContainerHigh,
          Colors.white,
          Colors.black,
          const Color(0xFF888888),
        ]) {
          final a = KraftColors.onColor(fill).computeLuminance();
          final b = fill.computeLuminance();
          final ratio = ((a > b ? a : b) + .05) / ((a < b ? a : b) + .05);
          expect(ratio, greaterThanOrEqualTo(4.5));
        }
      }
      KraftColors.use(Brightness.light);
    },
  );

  group('planning persistence and tool loop', () {
    late AppDatabase db;
    late WorkItemsRepository work;
    late ProjectsRepository projects;
    late AssistantTools tools;
    late CanvasBridge bridge;
    setUp(() {
      db = AppDatabase(NativeDatabase.memory(), seed: false);
      work = WorkItemsRepository(db);
      projects = ProjectsRepository(db);
      final canvases = CanvasesRepository(db);
      bridge = CanvasBridge(canvases);
      tools = AssistantTools(
        notes: NotesRepository(db),
        tasks: TasksRepository(db),
        projects: projects,
        workItems: work,
        noteBridge: NoteBridge(),
        canvasBridge: bridge,
        canvasTools: KraftCanvasTools(bridge: bridge, canvases: canvases),
      );
    });
    tearDown(() async {
      bridge.dispose();
      await db.close();
    });
    test(
      'review distinguishes empty notes, bounded drawings and incomplete canvas links',
      () async {
        final n = await tools.notes.create();
        final (empty, _) = await tools.call('review_artifact', {
          'kind': 'note',
          'id': n,
        });
        expect(empty['errors'], contains('La nota está vacía.'));
        final drawing = NoteDocument(
          sketches: [
            NoteSketch(
              id: 's',
              data: const CanvasData(
                items: [
                  CanvasItem(
                    id: 'shape',
                    type: CanvasItemType.shape,
                    position: Offset.zero,
                  ),
                ],
              ),
            ),
          ],
        );
        await tools.notes.saveContent(
          n,
          title: '',
          content: drawing.encode(),
          body: '',
        );
        final (visual, _) = await tools.call('review_artifact', {
          'kind': 'note',
          'id': n,
        });
        expect(visual['errors'], isEmpty);
        expect(visual['warnings'], isNotEmpty);
        final c = await tools.canvasTools.canvases.create(
          data: CanvasCodec.encode(
            const CanvasData(
              items: [
                CanvasItem(
                  id: 'a',
                  type: CanvasItemType.card,
                  position: Offset.zero,
                ),
              ],
              links: [CanvasLink(id: 'broken', from: 'a', to: 'missing')],
            ),
          ),
        );
        final (canvas, _) = await tools.call('review_artifact', {
          'kind': 'canvas',
          'id': c,
        });
        expect(canvas['structurally_valid'], false);
        expect(canvas['error_count'], 1);
        expect(canvas['warning_count'], 2);
      },
    );

    test(
      'workspace lookup and creation keep artefacts in their project',
      () async {
        final p = await projects.create(
          title: 'Calculadora científica',
          kind: ProjectKind.lienzo,
        );
        final (found, _) = await tools.call('search_workspace', {
          'query': 'mi proyecto calculadora',
        });
        expect((found['projects'] as List).single['project_id'], p);
        final (note, _) = await tools.call('create_note', {
          'project_id': p,
          'title': 'Decisiones',
          'text': 'Usar operaciones exactas.',
        });
        expect((await tools.notes.get(note['note_id'] as int))!.projectId, p);
        final (canvas, _) = await tools.call('create_canvas', {
          'project_id': p,
          'title': 'Arquitectura',
          'open': false,
        });
        expect(
          (await tools.canvasTools.canvases.get(
            canvas['canvas_id'] as int,
          ))!.projectId,
          p,
        );
        final (review, _) = await tools.call('review_artifact', {
          'kind': 'canvas',
          'id': canvas['canvas_id'],
        });
        expect(review['errors'], contains('El lienzo está vacío.'));
        final (invalid, _) = await tools.call('create_note', {
          'project_id': 999,
          'title': 'Invalid',
          'text': 'Never stored',
        });
        expect(invalid, contains('error'));
        expect(await tools.notes.watchAll().first, hasLength(1));
      },
    );

    test(
      'the assistant creates a project before saving its requirements',
      () async {
        final (project, action) = await tools.call('create_project', {
          'title': 'Craft',
          'description': 'Sincronización entre dispositivos.',
          'kind': 'lienzo',
          'tags': ['#sync', '#ipad'],
        });
        final id = project['project_id'] as int;
        expect(project['created'], true);
        expect(action!.label, 'Proyecto creado: Craft');
        expect((await projects.watchOne(id).first)!.title, 'Craft');

        final (requirement, _) = await tools.call('save_project_work', {
          'project_id': id,
          'kind': 'requirement',
          'title': 'Sincronizar lienzos',
          'acceptance': 'Los cambios aparecen en el segundo dispositivo.',
        });
        expect(requirement['saved'], true);
        expect(
          tools.compactDefinitions.map((definition) => definition['name']),
          contains('create_project'),
        );
      },
    );

    test(
      'artifact review identifies missing acceptance and clears it after correction',
      () async {
        final p = await projects.create(
          title: 'Review',
          kind: ProjectKind.nota,
        );
        final id = await work.create(
          projectId: p,
          title: 'Login',
          kind: 'requirement',
        );
        final (before, _) = await tools.call('review_artifact', {
          'kind': 'project',
          'id': p,
        });
        expect(before['warnings'], hasLength(2));
        await tools.call('save_project_work', {
          'id': id,
          'project_id': p,
          'title': 'Login',
          'kind': 'requirement',
          'description': 'Login with email',
          'acceptance': 'Invalid passwords rejected',
        });
        final (after, _) = await tools.call('review_artifact', {
          'kind': 'project',
          'id': p,
        });
        expect(after['warnings'], isEmpty);
        expect(after['structurally_valid'], true);
        final (missing, _) = await tools.call('review_artifact', {
          'kind': 'canvas',
          'id': 999,
        });
        expect(missing, contains('error'));
        expect(
          tools.compactDefinitions.map((t) => t['name']),
          contains('review_artifact'),
        );
      },
    );

    test(
      'requirements support children and reject cross-project parents',
      () async {
        final p = await projects.create(title: 'App', kind: ProjectKind.nota);
        final other = await projects.create(
          title: 'Other',
          kind: ProjectKind.nota,
        );
        final parent = await work.create(
          projectId: p,
          title: 'Auth',
          kind: 'requirement',
          acceptance: 'Login works',
        );
        final child = await work.create(
          projectId: p,
          title: 'Reset',
          kind: 'requirement',
          parentId: parent,
        );
        expect((await work.get(child))!.parentId, parent);
        await expectLater(
          work.create(
            projectId: other,
            title: 'Invalid',
            kind: 'requirement',
            parentId: parent,
          ),
          throwsArgumentError,
        );
        expect(
          tools.compactDefinitions.map((t) => t['name']),
          containsAll(['list_project_work', 'save_project_work']),
        );
        final (result, _) = await tools.call('save_project_work', {
          'project_id': p,
          'kind': 'activity',
          'title': 'Build',
          'due_at': '2026-10-01',
        });
        expect(result['saved'], true);
        expect(
          (await work.get(result['id'] as int))!.dueAt,
          DateTime(2026, 10, 1),
        );
      },
    );
    test(
      'compatible engine executes tools and returns matching tool results',
      () async {
        final p = await projects.create(title: 'App', kind: ProjectKind.nota);
        final keys = MemoryKeys();
        await keys.write('assistant.deepseek.apiKey', 'test-key');
        var requests = 0;
        final engine = CompatibleChatEngine(
          id: 'deepseek',
          label: 'DeepSeek',
          baseUrl: 'https://api.deepseek.com',
          defaultModel: 'test',
          settings: SettingsRepository(db),
          tools: tools,
          store: keys,
          sender: (uri, key, body) async {
            requests++;
            if (requests == 1)
              return {
                'choices': [
                  {
                    'message': {
                      'role': 'assistant',
                      'content': null,
                      'reasoning_content': 'internal',
                      'tool_calls': [
                        {
                          'id': 'call1',
                          'type': 'function',
                          'function': {
                            'name': 'save_project_work',
                            'arguments': jsonEncode({
                              'project_id': p,
                              'kind': 'requirement',
                              'title': 'Offline',
                            }),
                          },
                        },
                      ],
                    },
                  },
                ],
              };
            final messages = body['messages'] as List;
            expect((messages.last as Map)['tool_call_id'], 'call1');
            expect(
              jsonDecode((messages.last as Map)['content'] as String)['saved'],
              true,
            );
            return {
              'choices': [
                {
                  'message': {'role': 'assistant', 'content': 'Guardado'},
                },
              ],
            };
          },
        );
        final events = await engine.send('Requerimiento offline').toList();
        expect(events.whereType<AssistantFailed>(), isEmpty);
        expect(
          events.whereType<AssistantToolRan>().single.name,
          'save_project_work',
        );
        expect(events.whereType<AssistantReply>().single.text, 'Guardado');
        expect(
          (await work.watchAll(projectId: p).first).single.title,
          'Offline',
        );
      },
    );

    test('OpenRouter hides TimeoutException from the chat', () async {
      final keys = MemoryKeys();
      await keys.write('assistant.openrouter.apiKey', 'test-key');
      final engine = CompatibleChatEngine(
        id: 'openrouter',
        label: 'OpenRouter',
        baseUrl: 'https://openrouter.ai/api/v1',
        defaultModel: 'openrouter/free',
        settings: SettingsRepository(db),
        tools: tools,
        store: keys,
        sender: (uri, key, body) async {
          throw TimeoutException(
            'Future not completed',
            const Duration(minutes: 3),
          );
        },
      );
      final failed = (await engine.send('Hola').toList())
          .whereType<AssistantFailed>()
          .single;
      expect(failed.message, isNot(contains('TimeoutException')));
      expect(failed.message, isNot(contains('0:03:00')));
      expect(failed.message, contains('tardó demasiado'));
    });

    test(
      'legacy requirements without a column are placed on the board',
      () async {
        final p = await projects.create(title: 'App', kind: ProjectKind.nota);
        await db
            .into(db.workItems)
            .insert(
              WorkItemsCompanion.insert(
                projectId: p,
                title: 'Login legado',
                kind: const Value('requirement'),
              ),
            );
        final columns = await work.ensureDefaultColumns(p);
        final item = (await work.watchAll(projectId: p).first).single;
        expect(item.columnId, columns.first.id);
        expect(
          columns.firstWhere((c) => c.id == item.columnId).title,
          'Por hacer',
        );
      },
    );

    test(
      'save_project_work moves a requirement to En curso on the board',
      () async {
        final p = await projects.create(title: 'App', kind: ProjectKind.nota);
        final (created, _) = await tools.call('save_project_work', {
          'project_id': '$p',
          'kind': 'requirement',
          'title': 'Modo offline',
        });
        final id = created['id'] as int;
        final before = await work.get(id);
        final (moved, _) = await tools.call('save_project_work', {
          'id': '$id',
          'project_id': '$p',
          'kind': 'requirement',
          'status': 'doing',
        });
        expect(moved['saved'], true);
        final after = await work.get(id);
        expect(after!.status, 'doing');
        expect(after.columnId, isNot(before!.columnId));
        final columns = await work.watchColumns(p).first;
        expect(
          columns.firstWhere((c) => c.id == after.columnId).title,
          'En curso',
        );
      },
    );

    test('save_task creates and completes a requirement checkbox', () async {
      final p = await projects.create(title: 'App', kind: ProjectKind.nota);
      final requirement = await work.create(
        projectId: p,
        title: 'Gestión',
        kind: 'requirement',
      );
      expect(
        tools.compactDefinitions.map((definition) => definition['name']),
        containsAll(['save_task', 'list_project_work']),
      );
      final (created, action) = await tools.call('save_task', {
        'requirement_id': '$requirement',
        'title': 'Editar criterios',
      });
      expect(created['saved'], true);
      expect(created['requirement_id'], requirement);
      expect(action!.label, 'Tarea: Editar criterios');
      final listed = await tools.call('list_project_work', {'project_id': p});
      final tasks = (listed.$1['tasks'] as List).cast<Map>();
      expect(tasks, hasLength(1));
      expect(tasks.single['title'], 'Editar criterios');
      expect(tasks.single['done'], false);
      final (done, _) = await tools.call('save_task', {
        'id': created['id'],
        'done': true,
      });
      expect(done['done'], true);
      expect((await tools.tasks.get(created['id'] as int))!.done, isTrue);
    });

    test('requirement tools read, batch-create, open and delete', () async {
      String? openedView;
      int? openedProject;
      int? openedRequirement;
      tools.openViewHandler = (view, projectId, {int? requirementId}) async {
        openedView = view;
        openedProject = projectId;
        openedRequirement = requirementId;
      };
      final p = await projects.create(title: 'App', kind: ProjectKind.nota);
      final requirement = await work.create(
        projectId: p,
        title: 'Login',
        kind: 'requirement',
        description: 'Entrar con correo',
      );
      expect(
        tools.compactDefinitions.map((definition) => definition['name']),
        containsAll([
          'get_requirement',
          'save_tasks',
          'open_requirement',
          'delete_work',
        ]),
      );

      final (batch, action) = await tools.call('save_tasks', {
        'requirement_id': requirement,
        'titles': ['Pantalla', 'Validar correo', 'Sesión'],
      });
      expect(batch['saved'], true);
      expect(batch['count'], 3);
      expect(action!.label, contains('3 tareas'));

      final listed = await tools.call('get_requirement', {
        'requirement_id': requirement,
      });
      final item = listed.$1['item'] as Map;
      expect(item['title'], 'Login');
      expect(item['description'], 'Entrar con correo');
      final tasks = (listed.$1['tasks'] as List).cast<Map>();
      expect(tasks.map((task) => task['title']), [
        'Pantalla',
        'Validar correo',
        'Sesión',
      ]);

      final (opened, _) = await tools.call('open_requirement', {
        'requirement_id': requirement,
      });
      expect(openedView, 'requirement');
      expect(openedProject, p);
      expect(openedRequirement, requirement);
      expect(opened['requirement_id'], requirement);

      final taskId = tasks.first['id'] as int;
      final (deletedTask, _) = await tools.call('delete_work', {
        'task_id': taskId,
      });
      expect(deletedTask['deleted'], true);
      expect(await tools.tasks.get(taskId), isNull);

      final (deletedReq, _) = await tools.call('delete_work', {
        'requirement_id': requirement,
      });
      expect(deletedReq['deleted'], true);
      expect(deletedReq['tasks_removed'], 2);
      expect(await work.get(requirement), isNull);
    });
  });
}
