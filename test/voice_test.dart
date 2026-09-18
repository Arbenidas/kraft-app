import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kraft/data/db/database.dart';
import 'package:kraft/data/repositories.dart';
import 'package:kraft/features/ai/canvas_bridge.dart';
import 'package:kraft/features/ai/canvas_tools.dart';
import 'package:kraft/features/canvas/canvas_document.dart';
import 'package:kraft/features/canvas/canvas_models.dart';
import 'package:kraft/features/notes/note_bridge.dart';
import 'package:kraft/features/notes/note_document.dart';
import 'package:kraft/features/voice/assistant_engine.dart';
import 'package:kraft/features/voice/assistant_tools.dart';
import 'package:kraft/features/voice/gemini_chat.dart';
import 'package:kraft/features/voice/gemini_models.dart';
import 'package:kraft/features/voice/live_protocol.dart';
import 'package:kraft/features/voice/live_transport.dart';
import 'package:kraft/features/voice/voice_controller.dart';
import 'package:kraft/platform/secure_store.dart';
import 'package:kraft/platform/voice_audio.dart';

class _MemoryStore implements SecureStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _FakeAudio implements VoiceAudio {
  final mic = StreamController<Uint8List>.broadcast();
  final played = <Uint8List>[];
  List<MicrophoneDevice> devices = const [
    MicrophoneDevice(id: 'studio', name: 'Micrófono de estudio'),
  ];
  String? startedWith;
  var cleared = 0;
  var running = false;

  @override
  Future<List<MicrophoneDevice>> microphones() async => devices;

  MicrophoneStart startResult = MicrophoneStart.ok;

  @override
  Future<MicrophoneStart> start({String? microphoneId}) async {
    startedWith = microphoneId;
    running = startResult == MicrophoneStart.ok;
    return startResult;
  }

  @override
  Future<void> stop() async => running = false;

  @override
  Stream<Uint8List> get microphone => mic.stream;

  @override
  Future<void> play(Uint8List pcm) async => played.add(pcm);

  @override
  Future<void> clear() async => cleared++;
}

class _FakeTransport implements LiveTransport {
  final incoming = StreamController<Map<String, Object?>>.broadcast();
  final sent = <Map<String, Object?>>[];
  Uri? url;

  @override
  Stream<Map<String, Object?>> get messages => incoming.stream;

  @override
  void send(Map<String, Object?> message) => sent.add(message);

  @override
  Future<void> close() async {}

  @override
  String? get closeReason => null;
}

class _FakeEngine implements AssistantEngine {
  _FakeEngine({this.id = 'fake'});
  @override
  final String id;

  @override
  String get label => 'Motor de prueba';

  @override
  Future<bool> isReady() async => true;

  @override
  void reset() {}

  @override
  Stream<AssistantEvent> send(String message) async* {
    yield const AssistantToolRan(
      'create_reminder',
      AssistantAction('Recordatorio creado'),
    );
    yield const AssistantDelta('He');
    yield const AssistantDelta('cho');
    yield const AssistantReply('Hecho');
  }
}

class _LiveNote implements LiveNote {
  String text = 'Ideas de voz';
  List<Stroke> strokes = const [];
  var persisted = 0;
  String? focused;

  @override
  int get noteId => 1;

  @override
  String get noteText => text;

  @override
  void appendText(String addition) => text = '$text\n$addition';

  @override
  bool replaceTextIfUnchanged(String expected, String replacement) {
    if (text != expected) return false;
    text = replacement;
    return true;
  }

  @override
  List<Stroke> get noteStrokes => strokes;

  @override
  void addStrokes(List<Stroke> added) => strokes = [...strokes, ...added];

  @override
  void focusText(String phrase) => focused = phrase;

  @override
  Future<void> persist() async => persisted++;
}

class _LiveCanvas implements LiveCanvas {
  _LiveCanvas(this.canvasId, this.document);

  @override
  final int canvasId;

  @override
  String get canvasTitle => 'Tema de estudio';

  @override
  final CanvasDocument document;

  String? focused;

  @override
  Future<void> get ready async {}

  @override
  Future<void> persist() async {}

  @override
  void reveal(Rect world) {}

  @override
  void announceRemoteEdit(String summary) {}

  @override
  void focusItem(String itemId) => focused = itemId;
}

void main() {
  late AppDatabase db;
  late AssistantTools tools;
  late NoteBridge notes;
  late CanvasBridge canvasBridge;
  late CanvasesRepository canvases;
  final now = DateTime(2026, 9, 15, 10);

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), seed: false);
    notes = NoteBridge();
    canvases = CanvasesRepository(db);
    canvasBridge = CanvasBridge(canvases);
    tools = AssistantTools(
      notes: NotesRepository(db),
      tasks: TasksRepository(db),
      noteBridge: notes,
      canvasBridge: canvasBridge,
      canvasTools: KraftCanvasTools(bridge: canvasBridge, canvases: canvases),
      clock: () => now,
    );
  });
  tearDown(() => db.close());

  group('protocolo', () {
    test(
      'las herramientas se declaran con tipos de Gemini y sin claves no soportadas',
      () {
        final setup = LiveProtocol.setup(
          model: 'gemini-3.8-live',
          systemInstruction: 'hola',
          tools: tools.definitions,
        );
        final body = setup['setup']! as Map<String, Object?>;
        expect(body['model'], 'models/gemini-3.8-live');
        final declarations =
            ((body['tools']! as List).single as Map)['functionDeclarations']!
                as List;
        final names = [for (final d in declarations) (d as Map)['name']];
        expect(
          names,
          containsAll([
            'create_note',
            'create_reminder',
            'create_diagram',
            'edit_diagram',
            'draw_sketch',
            'explain_canvas',
            'explain_note',
          ]),
        );
        final json = jsonEncode(declarations);
        expect(json, isNot(contains('"object"')));
        expect(json, isNot(contains('"default"')));
        expect(json, isNot(contains('annotations')));
        expect(json, contains('"OBJECT"'));
      },
    );

    test(
      'extended thinking configures reasoning and asynchronous tools only on supported model',
      () {
        final advanced =
            LiveProtocol.setup(
                  model: LiveModel.live38Thinking.id,
                  systemInstruction: 'Test',
                  tools: tools.definitions,
                )['setup']
                as Map;
        expect((advanced['generationConfig'] as Map)['thinkingConfig'], {
          'thinkingLevel': 'HIGH',
        });
        final declarations =
            ((advanced['tools'] as List).single as Map)['functionDeclarations']
                as List;
        expect(
          declarations.every((d) => (d as Map)['behavior'] == 'NON_BLOCKING'),
          isTrue,
        );
        final standard =
            LiveProtocol.setup(
                  model: LiveModel.live38.id,
                  systemInstruction: 'Test',
                  tools: tools.definitions,
                )['setup']
                as Map;
        expect(
          (standard['generationConfig'] as Map).containsKey('thinkingConfig'),
          isFalse,
        );
        expect(
          LiveProtocol.endpoint('key', extendedThinking: true).path,
          contains('v1alpha'),
        );
        for (final message in <Map<String, Object?>>[
          {'interactionStatus': 'IN_PROGRESS'},
          {
            'serverContent': {
              'turnComplete': true,
              'interactionStatus': 'IN_PROGRESS',
            },
          },
        ]) {
          expect(
            LiveProtocol.parse(
              message,
            ).whereType<LiveInteractionStatus>().single.inProgress,
            isTrue,
          );
        }
        expect(
          LiveProtocol.parse({
            'interactionStatus': 'IDLE',
          }).whereType<LiveInteractionStatus>().single.inProgress,
          isFalse,
        );
      },
    );

    test('la versión compacta cabe en el contexto de un modelo local', () {
      final full = jsonEncode(tools.definitions);
      final compact = jsonEncode(tools.compactDefinitions);
      expect(compact.length, lessThan(full.length ~/ 2));
      // Sin catálogos largos (los 32 iconos) ni descripciones kilométricas.
      expect(compact, isNot(contains('smartphone')));
      expect(
        tools.compactDefinitions.map((t) => t['name']),
        containsAll([
          'create_note',
          'create_reminder',
          'edit_diagram',
          'explain_canvas',
          'explain_note',
          // Sin estas tres, al no haber lienzo abierto el modelo local se queda sin salida.
          'list_canvases',
          'create_canvas',
          'open_canvas',
          'sketch_note',
        ]),
      );
      // Los parámetros siguen explicados: es lo que el modelo pequeño no puede adivinar.
      expect(compact, contains('ISO 8601'));
      // Pero sin los acabados que no va a usar bien.
      final nodes =
          ((tools.compactDefinitions.firstWhere(
                        (t) => t['name'] == 'create_diagram',
                      )['inputSchema']!
                      as Map)['properties']!
                  as Map)['nodes']!
              as Map;
      final nodeProps = ((nodes['items']! as Map)['properties']! as Map).keys;
      expect(nodeProps, containsAll(['ref', 'type', 'title', 'bullets']));
      expect(nodeProps, isNot(contains('icon')));
      expect(nodeProps, isNot(contains('x')));
      // Regla de oro: unos 4 caracteres por token, y el modelo local tiene 8192.
      expect(compact.length ~/ 4, lessThan(3200));
      final local = GeminiChatEngine.instructions(tools, compact: true);
      expect(local, contains('inventario'));
      expect(local, isNot(contains('Antes de cambiar, lee')));
    });

    test('interpreta audio, transcripciones, interrupciones y llamadas', () {
      final events = LiveProtocol.parse({
        'serverContent': {
          'modelTurn': {
            'parts': [
              {
                'inlineData': {
                  'data': base64Encode([1, 2, 3, 4]),
                  'mimeType': 'audio/pcm;rate=24000',
                },
              },
            ],
          },
          'outputTranscription': {'text': 'Listo'},
          'interrupted': true,
        },
      });
      expect(events.whereType<LiveAudio>().single.pcm, [1, 2, 3, 4]);
      expect(events.whereType<LiveTranscript>().single.text, 'Listo');
      expect(events.whereType<LiveInterrupted>(), hasLength(1));

      final call =
          LiveProtocol.parse({
                'toolCall': {
                  'functionCalls': [
                    {
                      'id': 'c1',
                      'name': 'create_note',
                      'args': {'title': 'Plan'},
                    },
                  ],
                },
              }).single
              as LiveToolCall;
      expect(call.args['title'], 'Plan');
    });
  });

  group('herramientas', () {
    test('open_view navega a la vista y proyecto solicitados', () async {
      String? openedView;
      int? openedProject;
      tools.openViewHandler = (view, projectId, {int? requirementId}) async {
        openedView = view;
        openedProject = projectId;
      };

      final (result, action) = await tools.call('open_view', {
        'view': 'project',
        'project_id': 42,
      });

      expect(openedView, 'project');
      expect(openedProject, 42);
      expect(result, {'view': 'project', 'project_id': 42});
      expect(action!.label, 'Abrió: Proyecto #42');
    });

    test('create_note compone el documento y abre la nota', () async {
      int? opened;
      notes.openHandler = (id) async => opened = id;
      final (result, action) = await tools.call('create_note', {
        'title': 'App de viajes',
        'text': 'Planear rutas con amigos.',
        'tasks': ['Bocetar pantalla', 'Buscar APIs de mapas'],
      });
      final id = result['note_id']! as int;
      expect(opened, id);
      expect(action!.label, contains('App de viajes'));
      final note = (await NotesRepository(db).get(id))!;
      expect(
        NoteDocument.decode(note.content).text,
        'App de viajes\nPlanear rutas con amigos.\n☐ Bocetar pantalla\n☐ Buscar APIs de mapas',
      );
      expect(note.title, 'App de viajes');
    });

    test('create_note rechaza una nota solo con título', () async {
      final (result, action) = await tools.call('create_note', {
        'title': 'Guía de APIs REST',
      });
      expect(action, isNull);
      expect(result['error'], contains('contenido'));
    });

    test('append_to_note escribe en la nota abierta en vivo', () async {
      final live = _LiveNote();
      notes.attach(live);
      await tools.call('append_to_note', {
        'text': 'Otra idea',
        'tasks': ['Probar'],
      });
      expect(live.text, 'Ideas de voz\nOtra idea\n☐ Probar');
      expect(live.persisted, 1);
    });

    test(
      'sketch_note dibuja sobre la nota abierta, debajo del texto',
      () async {
        final live = _LiveNote()..text = 'Fotosíntesis\nLa hoja capta la luz.';
        notes.attach(live);

        final (result, action) = await tools.call('sketch_note', {
          'strokes': [
            {
              'points': [
                [0, 0],
                [100, 0],
              ],
              'color': 'verde',
            },
          ],
          'size': 200,
        });

        expect(result['note_id'], 1);
        expect(result['strokes'], 1);
        expect(live.strokes, hasLength(1));
        // Empieza en el margen izquierdo y por debajo de lo escrito.
        final drawn = live.strokes.single;
        expect(drawn.points.first.dx, 48);
        expect(drawn.points.first.dy, greaterThan(36));
        expect(drawn.points.last.dx - drawn.points.first.dx, 200);
        expect(live.persisted, 1);
        expect(action!.label, contains('Boceto'));
      },
    );

    test('sketch_note guarda el boceto en una nota cerrada', () async {
      final (created, _) = await tools.call('create_note', {
        'title': 'Rutas',
        'text': 'Comparar caminos.',
      });
      final id = created['note_id']! as int;

      await tools.call('sketch_note', {
        'note_id': id,
        'strokes': [
          {
            'points': [
              [10, 10],
              [90, 90],
              [10, 90],
            ],
          },
        ],
        'x': 100,
        'y': 400,
      });

      final saved = await NotesRepository(db).get(id);
      final doc = NoteDocument.decode(saved!.content);
      expect(doc.strokes, hasLength(1));
      expect(doc.text, contains('Rutas'));
      // Con x e y explícitas manda la IA.
      expect(doc.strokes.single.points.first.dx, 100 + 10 * 320 / 100);
    });

    test('focus_note_text señala la frase antes de explicarla', () async {
      final live = _LiveNote()
        ..text = 'Idea central\nExplicar la arquitectura por capas.';
      notes.attach(live);

      final (result, action) = await tools.call('focus_note_text', {
        'note_id': 1,
        'phrase': 'arquitectura por capas',
      });

      expect(result['focused'], 'arquitectura por capas');
      expect(live.focused, 'arquitectura por capas');
      expect(action!.label, contains('Explicando'));
    });

    test(
      'explain_note prepara un recorrido ordenado para voz y selección',
      () async {
        final (created, _) = await tools.call('create_note', {
          'title': 'Fotosíntesis',
          'text':
              'Las plantas transforman luz en energía. El proceso produce oxígeno.',
        });
        final id = created['note_id']! as int;
        final (result, action) = await tools.call('explain_note', {
          'note_id': id,
          'steps': [
            {
              'phrase': 'transforman luz en energía',
              'explanation': 'Primero, la planta captura energía luminosa.',
            },
            {
              'phrase': 'produce oxígeno',
              'explanation': 'Después libera oxígeno como parte del proceso.',
            },
          ],
        });

        expect(result['steps'], 2);
        expect(action!.explanation!.target, ExplanationTarget.note);
        expect(action.explanation!.steps.map((step) => step.focus), [
          'transforman luz en energía',
          'produce oxígeno',
        ]);
      },
    );

    test('explain_canvas valida ids y prepara el recorrido visual', () async {
      final id = await canvases.create(title: 'Fotosíntesis');
      final live = _LiveCanvas(
        id,
        CanvasDocument(
          items: const [
            CanvasItem(
              id: 'luz',
              type: CanvasItemType.card,
              position: Offset.zero,
              title: 'Captura de luz',
            ),
            CanvasItem(
              id: 'energia',
              type: CanvasItemType.card,
              position: Offset(300, 0),
              title: 'Energía química',
            ),
          ],
        ),
      );
      canvasBridge.attach(live);

      final (result, action) = await tools.call('explain_canvas', {
        'canvas_id': id,
        'steps': [
          {'element_id': 'luz', 'explanation': 'La hoja captura la luz.'},
          {
            'element_id': 'energia',
            'explanation': 'Después la convierte en energía química.',
          },
        ],
      });

      expect(result['steps'], 2);
      expect(action!.explanation!.target, ExplanationTarget.canvas);
      expect(action.explanation!.steps.map((step) => step.focus), [
        'luz',
        'energia',
      ]);
      canvasBridge.detach(live);
      live.document.dispose();
    });

    test(
      'search_workspace encuentra la nota aunque el usuario la nombre a su manera',
      () async {
        await tools.call('create_note', {
          'title': 'Arquitectura limpia de la calculadora',
          'text': 'Capas: presentación, dominio y datos.',
        });
        await tools.call('create_note', {
          'title': 'Lista de la compra',
          'text': 'Pan y café.',
        });
        await tools.call('create_reminder', {
          'title': 'Terminar la calculadora',
          'remind_at': '2026-09-16T09:00:00',
        });

        final (found, _) = await tools.call('search_workspace', {
          'query': 'mi proyecto de la calculadora',
        });
        final notes = found['notes']! as List;
        expect(notes, hasLength(1));
        expect(
          (notes.single as Map)['title'],
          'Arquitectura limpia de la calculadora',
        );
        expect(
          ((found['tasks']! as List).single as Map)['title'],
          'Terminar la calculadora',
        );

        final (nothing, _) = await tools.call('search_workspace', {
          'query': 'recetas de cocina',
        });
        expect(nothing['found'], isFalse);
      },
    );

    test('el contexto resume lo que hay guardado', () async {
      await tools.call('create_note', {
        'title': 'Plan de la semana',
        'text': 'Lunes compras, martes estudio.',
      });
      await tools.refresh();
      expect(tools.context(), contains('Plan de la semana'));
    });

    test(
      'create_reminder crea la tarea con hora y rechaza horas pasadas',
      () async {
        final (result, _) = await tools.call('create_reminder', {
          'title': 'Llamar a Ana',
          'remind_at': '2026-09-16T09:00:00',
        });
        final task = (await TasksRepository(
          db,
        ).get(result['task_id']! as int))!;
        expect(task.remindAt, DateTime(2026, 9, 16, 9));

        final (past, _) = await tools.call('create_reminder', {
          'title': 'Tarde',
          'remind_at': '2026-09-14T09:00:00',
        });
        expect(past['error'], contains('ya pasó'));
      },
    );
  });

  test(
    'Gemini chat: ejecuta la herramienta que pide el modelo y devuelve el resultado',
    () async {
      final store = _MemoryStore()..values['gemini_api_key'] = 'clave';
      final sent = <Map<String, Object?>>[];
      var round = 0;
      final engine = GeminiChatEngine(
        tools: tools,
        store: store,
        send: (url, body) async* {
          sent.add(body);
          expect(
            url.toString(),
            contains('gemini-3.8-flash:streamGenerateContent'),
          );
          expect(url.queryParameters['alt'], 'sse');
          round++;
          if (round == 1) {
            yield {
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {
                        'functionCall': {
                          'name': 'create_note',
                          'args': {
                            'title': 'Arquitectura limpia',
                            'text': 'Principios de arquitectura limpia',
                          },
                        },
                      },
                    ],
                  },
                },
              ],
            };
            return;
          }
          // La respuesta llega por trozos, como en el streaming real.
          for (final piece in ['Listo, ', 'te creé ', 'la nota.']) {
            yield {
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': piece},
                    ],
                  },
                },
              ],
            };
          }
        },
      );

      final events = await engine
          .send('Apúntame una nota sobre arquitectura limpia')
          .toList();
      expect(events.whereType<AssistantToolRan>().single.name, 'create_note');
      expect(events.whereType<AssistantDelta>().map((e) => e.text), [
        'Listo, ',
        'te creé ',
        'la nota.',
      ]);
      expect(
        events.whereType<AssistantReply>().single.text,
        'Listo, te creé la nota.',
      );
      // La declaración de herramientas viaja con tipos de Gemini y el resultado vuelve como functionResponse.
      expect(jsonEncode(sent.first['tools']), contains('"OBJECT"'));
      expect(jsonEncode(sent.last['contents']), contains('functionResponse'));
      final notes = await NotesRepository(db).watchAll().first;
      expect(notes.single.title, 'Arquitectura limpia');
    },
  );

  test('Gemini Pro envía el nivel de razonamiento que exige la API', () async {
    final store = _MemoryStore()..values['gemini_api_key'] = 'clave';
    Map<String, Object?>? sent;
    final engine = GeminiChatEngine(
      tools: tools,
      store: store,
      model: ChatModel.pro31.id,
      send: (url, body) async* {
        sent = body;
        yield {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'Listo'},
                ],
              },
            },
          ],
        };
      },
    );

    await engine.send('Haz un diagrama detallado').toList();

    final generation = sent!['generationConfig']! as Map;
    expect((generation['thinkingConfig']! as Map)['thinkingLevel'], 'high');
  });

  test(
    'Live keeps thinking across utterances and ignores duplicate or cancelled calls',
    () async {
      final store = _MemoryStore();
      final transport = _FakeTransport();
      final voice = VoiceController(
        tools: tools,
        engines: [GeminiChatEngine(tools: tools, store: store)],
        settings: SettingsRepository(db),
        store: store,
        audio: _FakeAudio(),
        connect: (_) async => transport,
        liveAudio: true,
        model: LiveModel.live38Thinking.id,
      );
      await voice.saveKey('test');
      await voice.start();
      transport.incoming.add({'setupComplete': <String, Object?>{}});
      transport.incoming.add({'interactionStatus': 'IN_PROGRESS'});
      transport.incoming.add({
        'serverContent': {'turnComplete': true},
      });
      await pumpEventQueue();
      expect(voice.liveThinking, isTrue);
      transport.incoming.add({
        'toolCallCancellation': {
          'ids': ['cancelled'],
        },
      });
      final call = <String, Object?>{
        'id': 'once',
        'name': 'create_note',
        'args': {
          'title': 'Solo una',
          'text': 'Contenido verificable',
          'open': false,
        },
      };
      transport.incoming.add({
        'toolCall': {
          'functionCalls': [
            call,
            call,
            {...call, 'id': 'cancelled'},
          ],
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(await tools.notes.watchAll().first, hasLength(1));
      expect(
        transport.sent.where((m) => m.containsKey('toolResponse')),
        hasLength(1),
      );
      transport.incoming.add({
        'serverContent': {'interactionStatus': 'IDLE'},
      });
      await pumpEventQueue();
      expect(voice.liveThinking, isFalse);
      await voice.stop();
      voice.dispose();
    },
  );

  test('local and alternative providers never open Gemini Live', () async {
    for (final id in ['deepseek', 'mimo', 'openrouter']) {
      var connected = false;
      final voice = VoiceController(
        tools: tools,
        engines: [_FakeEngine(id: id)],
        settings: SettingsRepository(db),
        store: _MemoryStore()..values['gemini_api_key'] = 'existing',
        audio: _FakeAudio(),
        liveAudio: true,
        connect: (_) async {
          connected = true;
          return _FakeTransport();
        },
      );
      expect(voice.usesDictation, true);
      await voice.start();
      expect(connected, false);
      expect(voice.active, false);
      await voice.ask('Planifica mi proyecto');
      expect(voice.turns.last.text, 'Hecho');
      voice.dispose();
    }
  });

  test('chat escrito: responde con texto y ejecuta herramientas', () async {
    final store = _MemoryStore()..values['gemini_api_key'] = 'k';
    final engine = _FakeEngine();
    final voice = VoiceController(
      tools: tools,
      engines: [engine],
      settings: SettingsRepository(db),
      store: store,
      audio: _FakeAudio(),
      connect: (_) async => _FakeTransport(),
    );

    await voice.ask('Recuérdame comprar pan mañana');
    // Los trozos se escriben en un único mensaje, no uno por token.
    expect(voice.turns.map((t) => t.text), [
      'Recuérdame comprar pan mañana',
      'Hecho',
    ]);
    expect(voice.actions.single.label, 'Recordatorio creado');
    expect(voice.thinking, isFalse);
    voice.dispose();
  });

  test('guarda, recupera y limpia el historial de conversaciones', () async {
    final settings = SettingsRepository(db);
    final first = VoiceController(
      tools: tools,
      engines: [_FakeEngine()],
      settings: settings,
      store: _MemoryStore(),
      audio: _FakeAudio(),
      liveAudio: false,
    );
    await first.loadKey();
    await first.ask('Explícame cómo funciona KRAFT');
    await first.newConversation();
    final saved = first.conversations.firstWhere(
      (thread) => thread.entries.isNotEmpty,
    );
    expect(saved.title, 'Explícame cómo funciona KRAFT');
    await first.stop();
    first.dispose();

    final restored = VoiceController(
      tools: tools,
      engines: [_FakeEngine()],
      settings: settings,
      store: _MemoryStore(),
      audio: _FakeAudio(),
      liveAudio: false,
    );
    await restored.loadKey();
    await restored.openConversation(saved.id);
    expect(restored.turns.map((turn) => turn.text), [
      'Explícame cómo funciona KRAFT',
      'Hecho',
    ]);

    await restored.clearConversationHistory();
    expect(
      restored.conversations.where((thread) => thread.entries.isNotEmpty),
      isEmpty,
    );
    await restored.stop();
    restored.dispose();
  });

  test(
    'sin audio nativo (Mac) no se ofrece hablar, pero sí escribir',
    () async {
      final store = _MemoryStore()..values['gemini_api_key'] = 'clave';
      final voice = VoiceController(
        tools: tools,
        engines: [_FakeEngine(id: 'gemini')],
        settings: SettingsRepository(db),
        store: store,
        audio: _FakeAudio(),
        connect: (_) async => _FakeTransport(),
        liveAudio: false,
      );

      await voice.start();
      expect(voice.active, isFalse);
      expect(
        voice.error,
        contains('dispositivo'),
        reason: 'no puede decir que falta el permiso del micrófono',
      );

      await voice.ask('Apunta una idea');
      expect(voice.turns.last.text, 'Hecho');
      voice.dispose();
    },
  );

  test(
    'si el micrófono nativo no arranca, se muestra un error y no se conecta a Gemini',
    () async {
      final store = _MemoryStore()..values['gemini_api_key'] = 'clave';
      final audio = _FakeAudio()..startResult = MicrophoneStart.failed;
      var connected = false;
      final voice = VoiceController(
        tools: tools,
        engines: [_FakeEngine(id: 'gemini')],
        settings: SettingsRepository(db),
        store: store,
        audio: audio,
        connect: (_) async {
          connected = true;
          return _FakeTransport();
        },
        liveAudio: true,
      );

      await voice.start();
      expect(voice.active, isFalse);
      expect(connected, isFalse);
      expect(voice.status, VoiceStatus.error);
      expect(voice.error, contains('micrófono'));
      voice.dispose();
    },
  );

  test(
    'conversación: setup, micrófono, herramienta y audio de respuesta',
    () async {
      final store = _MemoryStore();
      final audio = _FakeAudio();
      final transport = _FakeTransport();
      final voice = VoiceController(
        tools: tools,
        engines: [GeminiChatEngine(tools: tools, store: store)],
        settings: SettingsRepository(db),
        store: store,
        audio: audio,
        connect: (url) async => transport..url = url,
        liveAudio: true,
      );

      await voice.start();
      expect(
        voice.status,
        VoiceStatus.needsKey,
        reason: 'sin API key no conecta',
      );

      await voice.saveKey('clave-secreta');
      await voice.start();
      expect(transport.url.toString(), contains('key=clave-secreta'));
      expect(transport.sent.single.containsKey('setup'), isTrue);

      transport.incoming.add({'setupComplete': <String, Object?>{}});
      await pumpEventQueue();
      expect(voice.status, VoiceStatus.listening);

      audio.mic.add(Uint8List.fromList([0, 1, 0, 1]));
      await pumpEventQueue();
      expect(transport.sent.last.containsKey('realtimeInput'), isTrue);
      final sentBeforeReply = transport.sent.length;

      transport.incoming.add({
        'serverContent': {
          'inputTranscription': {
            'text': 'Recuérdame comprar pan mañana a las 9',
          },
        },
      });
      transport.incoming.add({
        'toolCall': {
          'functionCalls': [
            {
              'id': 'call-1',
              'name': 'create_reminder',
              'args': {
                'title': 'Comprar pan',
                'remind_at': '2026-09-16T09:00:00',
              },
            },
          ],
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final response = transport.sent.lastWhere(
        (m) => m.containsKey('toolResponse'),
      );
      expect(jsonEncode(response), contains('call-1'));
      expect(voice.actions.single.label, contains('Comprar pan'));
      expect(voice.turns.single.text, 'Recuérdame comprar pan mañana a las 9');

      transport.incoming.add({
        'serverContent': {
          'modelTurn': {
            'parts': [
              {
                'inlineData': {
                  'data': base64Encode([9, 9]),
                  'mimeType': 'audio/pcm;rate=24000',
                },
              },
            ],
          },
        },
      });
      await pumpEventQueue();
      expect(voice.status, VoiceStatus.speaking);
      expect(audio.played.single, [9, 9]);

      // Aunque el micrófono alcance a recoger la voz del altavoz, no debe
      // reenviarla a Gemini ni durante la respuesta ni en su breve cola final.
      audio.mic.add(Uint8List.fromList([9, 9, 9, 9]));
      transport.incoming.add({
        'serverContent': {'turnComplete': true},
      });
      audio.mic.add(Uint8List.fromList([9, 9, 9, 9]));
      await pumpEventQueue();
      expect(transport.sent, hasLength(sentBeforeReply + 1));

      await voice.stop();
      expect(voice.status, VoiceStatus.idle);
      expect(audio.running, isFalse);
      voice.dispose();
    },
  );

  test(
    'recuerda el micrófono elegido y lo usa al iniciar Gemini Live',
    () async {
      final store = _MemoryStore()..values['gemini_api_key'] = 'clave';
      final audio = _FakeAudio();
      final voice = VoiceController(
        tools: tools,
        engines: [_FakeEngine(id: 'gemini')],
        settings: SettingsRepository(db),
        store: store,
        audio: audio,
        connect: (_) async => _FakeTransport(),
        liveAudio: true,
      );

      await voice.loadKey();
      expect(voice.microphones.map((device) => device.id), [
        'system',
        'studio',
      ]);
      await voice.setMicrophone('studio');
      await voice.start();

      expect(audio.startedWith, 'studio');
      expect(
        await SettingsRepository(db).get(VoiceController.microphoneKey),
        'studio',
      );
      await voice.stop();
      voice.dispose();
    },
  );
}
