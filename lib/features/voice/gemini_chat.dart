import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../platform/secure_store.dart';
import 'assistant_engine.dart';
import 'creation_policy.dart';
import 'assistant_tools.dart';
import 'gemini_models.dart';
import 'live_protocol.dart';

/// Chat escrito con Gemini (por defecto 3.8 Flash), con las mismas herramientas que la voz.
/// Habla directamente con la API REST: no hace falta ninguna librería extra.
class GeminiChatEngine implements AssistantEngine, RestorableAssistantEngine {
  GeminiChatEngine({
    required this.tools,
    SecureStore store = const KeychainStore(),
    String model = defaultModel,
    GeminiSender? send,
  }) : _store = store,
       _model = model,
       _send = send ?? _httpSend;

  final AssistantTools tools;
  final SecureStore _store;
  final GeminiSender _send;

  /// Se puede cambiar en caliente desde Ajustes. Cambiarlo empieza conversación nueva:
  /// el historial de un modelo no siempre le sirve a otro.
  String _model;
  String get model => _model;
  set model(String next) {
    if (next == _model) return;
    _model = next;
    _history.clear();
  }

  static const defaultModel = 'gemini-3.8-flash';
  static const _maxToolRounds = 6;
  static const _historyLimit = 24;

  final List<Map<String, Object?>> _history = [];

  @override
  String get id => 'gemini';

  @override
  String get label =>
      'Gemini ${_model.replaceAll('gemini-', '').replaceAll('-', ' ')}';

  @override
  Future<bool> isReady() async =>
      (await _store.read(VoiceKeys.apiKey))?.isNotEmpty ?? false;

  @override
  void reset() => _history.clear();

  @override
  void restore(List<AssistantMessage> messages) {
    _history
      ..clear()
      ..addAll([
        for (final message in messages)
          {
            'role': message.user ? 'user' : 'model',
            'parts': [
              {'text': message.text},
            ],
          },
      ]);
    _trim();
  }

  @override
  Stream<AssistantEvent> send(String message) async* {
    final key = await _store.read(VoiceKeys.apiKey);
    if (key == null || key.isEmpty) {
      yield const AssistantFailed('Falta la API key de Gemini.');
      return;
    }
    await tools.refresh();
    _history.add({
      'role': 'user',
      'parts': [
        {'text': message},
      ],
    });

    for (var round = 0; round < _maxToolRounds; round++) {
      // La respuesta llega por trozos (SSE): se van escribiendo en pantalla mientras el modelo piensa.
      final parts = <Map<String, Object?>>[];
      final written = StringBuffer();
      try {
        await for (final chunk in _send(_url(key), _body())) {
          for (final part in _parts(chunk)) {
            if (part['text'] case final String t when t.isNotEmpty) {
              written.write(t);
              yield AssistantDelta(t);
            } else {
              parts.add(part);
            }
          }
        }
      } on Object catch (e) {
        yield AssistantFailed('$e');
        return;
      }
      final text = written.toString().trim();
      if (parts.isEmpty && text.isEmpty) {
        yield const AssistantFailed('Gemini no devolvió respuesta.');
        return;
      }
      _history.add({
        'role': 'model',
        'parts': [
          if (written.isNotEmpty) {'text': written.toString()},
          ...parts,
        ],
      });
      _trim();

      final calls = [
        for (final part in parts)
          if (part['functionCall'] case final Map<String, Object?> call) call,
      ];
      if (text.isNotEmpty) yield AssistantReply(text);

      if (calls.isEmpty) return;

      final responses = <Map<String, Object?>>[];
      for (final call in calls) {
        final name = '${call['name']}';
        final args =
            (call['args'] as Map?)?.cast<String, Object?>() ??
            const <String, Object?>{};
        final (result, action) = await tools.call(name, args);
        yield AssistantToolRan(name, action);
        responses.add({
          'functionResponse': {'name': name, 'response': result},
        });
      }
      _history.add({'role': 'user', 'parts': responses});
    }
    yield const AssistantFailed(
      'Demasiados pasos seguidos; prueba a pedirlo por partes.',
    );
  }

  Uri _url(String key) => Uri.https(
    'generativelanguage.googleapis.com',
    '/v1beta/models/$_model:streamGenerateContent',
    {'alt': 'sse', 'key': key},
  );

  Map<String, Object?> _body() => {
    'contents': _history,
    'generationConfig': {
      'thinkingConfig': {'thinkingLevel': _thinkingLevel},
    },
    'systemInstruction': {
      'parts': [
        {'text': instructions(tools)},
      ],
    },
    'tools': [
      {
        'functionDeclarations': [
          for (final t in tools.definitions) LiveProtocol.declaration(t),
        ],
      },
    ],
  };

  String get _thinkingLevel {
    for (final candidate in ChatModel.values) {
      if (candidate.id == _model) return candidate.thinkingLevel;
    }
    return 'medium';
  }

  /// Envío real por HTTPS con respuesta en streaming (SSE). En los tests se sustituye.
  static Stream<Map<String, Object?>> _httpSend(
    Uri url,
    Map<String, Object?> body,
  ) async* {
    final client = HttpClient();
    try {
      final request = await client.postUrl(url);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      final lines = response
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      if (response.statusCode != HttpStatus.ok) {
        final text = await lines.join();
        final error = (jsonDecode(text) as Map?)?['error'] as Map?;
        throw Exception(
          (error?['message'] as String?) ?? 'Error ${response.statusCode}',
        );
      }
      await for (final line in lines) {
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty || payload == '[DONE]') continue;
        yield (jsonDecode(payload) as Map).cast<String, Object?>();
      }
    } finally {
      client.close();
    }
  }

  static List<Map<String, Object?>> _parts(Map<String, Object?> response) {
    final candidates = response['candidates'] as List? ?? const [];
    if (candidates.isEmpty) return const [];
    final content = (candidates.first as Map)['content'] as Map?;
    return [
      for (final part in (content?['parts'] as List? ?? const []))
        (part as Map).cast<String, Object?>(),
    ];
  }

  void _trim() {
    while (_history.length > _historyLimit) {
      _history.removeAt(0);
    }
  }

  /// Instrucciones comunes a voz y chat. [compact] recorta para modelos locales con poco contexto.
  /// [withContext] añade la foto de ahora mismo (fecha, qué hay abierto, qué existe): Gemini la
  /// recalcula en cada petición, pero un chat local se crea una vez, así que la manda por turno.
  static String instructions(
    AssistantTools tools, {
    bool compact = false,
    bool withContext = true,
  }) =>
      '''
Eres el asistente de KRAFT. Habla siempre en español, de forma breve; guarda el contenido completo y útil en los documentos.
Usa create_note/append_to_note para notas, create_reminder o save_task para tareas,
save_task/save_tasks con requirement_id para casillas, get_requirement para leerlas,
open_requirement para mostrarlas y create_canvas/create_diagram
para nuevos lienzos. Si no hay lienzo, créalo tú: nunca pidas ids al usuario.
sketch_note con embedded=true crea un boceto dentro de la nota. No crees notas vacías: create_note necesita el artículo en text.
Si el usuario pide una guía o nota sobre un tema, ese tema va en la nota; no desvíes a analizar el inventario del workspace.
Para explicar usa read_note + explain_note o get_canvas + explain_canvas con ids reales.
Vincula tarjetas a sus notas con note_id cuando amplíen el mismo tema.
${compact ? CreationPolicy.compactInstructions : CreationPolicy.instructions}
${withContext ? tools.context(compact: compact) : ''}''';
}

/// Cómo se manda una petición a Gemini y cómo llegan sus trozos (inyectable en los tests).
typedef GeminiSender =
    Stream<Map<String, Object?>> Function(Uri url, Map<String, Object?> body);

/// Claves de los secretos guardados en el llavero.
abstract final class VoiceKeys {
  static const apiKey = 'gemini_api_key';
}
