import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kraft/data/db/database.dart';
import 'package:kraft/data/repositories.dart';
import 'package:kraft/features/ai/canvas_bridge.dart';
import 'package:kraft/features/ai/canvas_tools.dart';
import 'package:kraft/features/notes/note_bridge.dart';
import 'package:kraft/features/voice/assistant_engine.dart';
import 'package:kraft/features/voice/assistant_tools.dart';
import 'package:kraft/features/voice/ollama_chat.dart';

void main() {
  late AppDatabase db;
  late AssistantTools tools;
  late SettingsRepository settings;
  late CanvasBridge bridge;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), seed: false);
    settings = SettingsRepository(db);
    final canvases = CanvasesRepository(db);
    bridge = CanvasBridge(canvases);
    tools = AssistantTools(
      notes: NotesRepository(db),
      tasks: TasksRepository(db),
      projects: ProjectsRepository(db),
      workItems: WorkItemsRepository(db),
      noteBridge: NoteBridge(),
      canvasBridge: bridge,
      canvasTools: KraftCanvasTools(bridge: bridge, canvases: canvases),
    );
  });

  tearDown(() async {
    bridge.dispose();
    await db.close();
  });

  Map<String, Object?> tags([
    List<Map<String, Object?>> models = const [
      {
        'name': 'gemma4:12b',
        'capabilities': ['completion', 'tools', 'thinking'],
        'details': {'parameter_size': '11.9B'},
      },
    ],
  ]) => {'models': models};

  test('lists installed Ollama models and prefers one with tools', () async {
    await settings.set(OllamaChatEngine.modelKey, 'qwen3.5:4b');
    final engine = OllamaChatEngine(
      tools: tools,
      settings: settings,
      requester: (method, path, {body}) async => tags(),
    );
    final models = await engine.listModels();
    expect(models, hasLength(1));
    expect(models.single.name, 'gemma4:12b');
    expect(models.single.tools, isTrue);
    expect(models.single.detail, contains('herramientas'));
    expect(await engine.model, 'gemma4:12b');
    expect(await settings.get(OllamaChatEngine.modelKey), 'gemma4:12b');
  });

  test('chat uses the installed model and streams with think on', () async {
    Map<String, Object?>? lastBody;
    final engine = OllamaChatEngine(
      tools: tools,
      settings: settings,
      requester: (method, path, {body}) async {
        if (path == '/api/tags') return tags();
        lastBody = body;
        return {
          'message': {
            'role': 'assistant',
            'thinking': 'busco el tablero',
            'content': 'Hola desde gemma4',
          },
          'eval_count': 40,
          'eval_duration': 2000000000,
        };
      },
    );
    final events = await engine.send('Hola').toList();
    expect(events.whereType<AssistantFailed>(), isEmpty);
    expect(
      events.whereType<AssistantThinking>().single.text,
      'busco el tablero',
    );
    expect(events.whereType<AssistantReply>().single.text, 'Hola desde gemma4');
    expect(events.whereType<AssistantStats>().single.tokens, 40);
    expect(events.whereType<AssistantStats>().single.tokensPerSecond, 20);
    expect(lastBody!['model'], 'gemma4:12b');
    expect(lastBody!['stream'], isTrue);
    expect(lastBody!['think'], isTrue);
    expect(
      ((lastBody!['tools'] as List).first as Map)['function'],
      containsPair('name', isNotEmpty),
    );
  });

  test(
    'parses string tool arguments and sends tool_name back to Ollama',
    () async {
      var round = 0;
      Map<String, Object?>? toolMessage;
      final engine = OllamaChatEngine(
        tools: tools,
        settings: settings,
        requester: (method, path, {body}) async {
          if (path == '/api/tags') return tags();
          round++;
          if (round == 1) {
            return {
              'message': {
                'role': 'assistant',
                'tool_calls': [
                  {
                    'id': 'call1',
                    'function': {
                      'name': 'save_task',
                      'arguments': jsonEncode({'title': 'Revisar REQ-29'}),
                    },
                  },
                ],
              },
            };
          }
          toolMessage =
              (body!['messages'] as List).last as Map<String, Object?>;
          return {
            'message': {'role': 'assistant', 'content': 'Creé la tarea'},
          };
        },
      );
      final events = await engine.send('Crea una tarea').toList();
      expect(events.whereType<AssistantToolRan>().single.name, 'save_task');
      expect(events.whereType<AssistantReply>().single.text, 'Creé la tarea');
      expect(toolMessage!['role'], 'tool');
      expect(toolMessage!['tool_name'], 'save_task');
      expect(toolMessage!['tool_call_id'], 'call1');
      expect((await tools.tasks.all()).single.title, 'Revisar REQ-29');
    },
  );

  test('names installed models when the configured one is missing', () async {
    await settings.set(OllamaChatEngine.modelKey, 'llama3:8b');
    final engine = OllamaChatEngine(
      tools: tools,
      settings: settings,
      requester: (method, path, {body}) async => tags(const [
        {
          'name': 'phi4:latest',
          'capabilities': ['completion'],
        },
      ]),
    );
    expect(await engine.model, 'phi4:latest');
  });

  test('timeout becomes a readable Spanish message', () async {
    final engine = OllamaChatEngine(
      tools: tools,
      settings: settings,
      requester: (method, path, {body}) async {
        if (path == '/api/tags') return tags();
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

  test('hides replacement glyphs from the UI', () {
    expect(assistantVisibleText('ok\uFFFDbad'), 'okbad');
  });
}
