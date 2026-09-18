import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../data/repositories.dart';
import 'assistant_engine.dart';
import 'assistant_tools.dart';
import 'gemini_chat.dart';

typedef OllamaRequester =
    Future<Object?> Function(
      String method,
      String path, {
      Map<String, Object?>? body,
    });

class OllamaModelInfo {
  const OllamaModelInfo({
    required this.name,
    this.tools = false,
    this.thinking = false,
    this.parameterSize,
  });

  final String name;
  final bool tools;
  final bool thinking;
  final String? parameterSize;

  String get detail {
    final parts = [
      if (parameterSize != null && parameterSize!.isNotEmpty) parameterSize,
      if (tools) 'herramientas',
      if (thinking) 'razonamiento',
    ];
    return parts.isEmpty ? 'Instalado en Ollama' : parts.join(' · ');
  }
}

class OllamaSuggested {
  const OllamaSuggested({
    required this.name,
    required this.label,
    required this.detail,
  });
  final String name;
  final String label;
  final String detail;
}

/// Adaptador para Ollama local en el Mac. No descarga modelos ni inicia el
/// servidor: KRAFT sólo se conecta a una instalación que el usuario controla.
class OllamaChatEngine implements AssistantEngine, RestorableAssistantEngine {
  OllamaChatEngine({
    required this.tools,
    required this.settings,
    this.baseUrl = 'http://127.0.0.1:11434',
    OllamaRequester? requester,
  }) : _requester = requester;

  final AssistantTools tools;
  final SettingsRepository settings;
  final String baseUrl;
  final OllamaRequester? _requester;
  static const modelKey = 'assistant.ollama.model';
  static const deepKey = 'assistant.ollama.deep';
  static const fallbackModel = 'qwen3.5:4b';
  final List<Map<String, Object?>> _history = [];
  bool _busy = false;

  @override
  String get id => 'ollama';
  @override
  String get label => 'Ollama local';

  Future<String> get model async => resolveModel(await listModels());

  Future<bool> get deep async => (await settings.get(deepKey)) != 'false';

  static const suggested = [
    OllamaSuggested(
      name: 'qwen3.5:4b',
      label: 'Qwen 3.5 4B',
      detail: 'Q4_K_M · 3,4 GB · el más rápido con herramientas',
    ),
    OllamaSuggested(
      name: 'qwen3.5:9b',
      label: 'Qwen 3.5 9B',
      detail: 'Q4 · ~6 GB · más criterio, sigue ágil',
    ),
    OllamaSuggested(
      name: 'gemma4:e4b',
      label: 'Gemma 4 E4B',
      detail: 'Cuantizado · más ligero que el 12B',
    ),
  ];

  Future<String> resolveModel(List<OllamaModelInfo> available) async {
    final saved = (await settings.get(modelKey))?.trim() ?? '';
    if (saved.isNotEmpty && available.any((model) => model.name == saved)) {
      return saved;
    }
    final preferred =
        available.where((model) => model.tools).firstOrNull ??
        available.firstOrNull;
    if (preferred == null) return saved.isNotEmpty ? saved : fallbackModel;
    if (saved != preferred.name) {
      await settings.set(modelKey, preferred.name);
    }
    return preferred.name;
  }

  Future<List<OllamaModelInfo>> listModels() async {
    try {
      final response = await _send('GET', '/api/tags');
      final models = (response as Map)['models'] as List? ?? const [];
      return [
        for (final raw in models)
          if (raw is Map) ?_modelInfo(raw),
      ];
    } catch (_) {
      return const [];
    }
  }

  static OllamaModelInfo? _modelInfo(Map raw) {
    final name = '${raw['name'] ?? raw['model'] ?? ''}'.trim();
    if (name.isEmpty) return null;
    final size = '${(raw['details'] as Map?)?['parameter_size'] ?? ''}'.trim();
    return OllamaModelInfo(
      name: name,
      tools: _capabilities(raw).contains('tools'),
      thinking: _capabilities(raw).contains('thinking'),
      parameterSize: size.isEmpty ? null : size,
    );
  }

  static Set<String> _capabilities(Map raw) => {
    for (final value in raw['capabilities'] as List? ?? const []) '$value',
  };

  @override
  Future<bool> isReady() async {
    try {
      final response = await _send(
        'GET',
        '/api/tags',
      ).timeout(const Duration(seconds: 2));
      return response is Map;
    } catch (_) {
      return false;
    }
  }

  @override
  void reset() => _history.clear();
  @override
  void restore(List<AssistantMessage> messages) {
    _history
      ..clear()
      ..addAll([
        for (final m in messages.take(16))
          {'role': m.user ? 'user' : 'assistant', 'content': m.text},
      ]);
  }

  @override
  Stream<AssistantEvent> send(String message) async* {
    if (_busy) {
      yield const AssistantFailed('Espera a que termine la respuesta local.');
      return;
    }
    _busy = true;
    var selected = fallbackModel;
    try {
      final available = await listModels();
      if (available.isEmpty && !await isReady()) {
        yield const AssistantFailed(
          'Ollama no está disponible. Abre Ollama en este Mac y prueba la conexión en Ajustes.',
        );
        return;
      }
      if (available.isEmpty) {
        yield const AssistantFailed(
          'Ollama está vacío. Instala un modelo cuantizado rápido: ollama pull qwen3.5:4b',
        );
        return;
      }
      selected = await resolveModel(available);
      if (!available.any((model) => model.name == selected)) {
        yield AssistantFailed(
          'No está $selected. Modelos instalados: ${[for (final model in available) model.name].join(', ')}.',
        );
        return;
      }
      await tools.refresh();
      _history.add({'role': 'user', 'content': message});
      final think = await deep;
      for (var round = 0; round < 8; round++) {
        final body = <String, Object?>{
          'model': selected,
          'stream': true,
          'messages': [
            {
              'role': 'system',
              'content': GeminiChatEngine.instructions(tools, compact: true),
            },
            ..._history,
          ],
          'tools': [
            for (final tool in tools.compactDefinitions)
              {
                'type': 'function',
                'function': {
                  'name': tool['name'],
                  'description': tool['description'],
                  'parameters': tool['inputSchema'],
                },
              },
          ],
        };
        if (think) body['think'] = true;
        final thinking = StringBuffer();
        final content = StringBuffer();
        var calls = <dynamic>[];
        await for (final chunk in _chatChunks(body)) {
          if (chunk['error'] != null) {
            throw HttpException('${chunk['error']}');
          }
          final msg = chunk['message'] as Map?;
          if (msg != null) {
            final thought = assistantVisibleText('${msg['thinking'] ?? ''}');
            if (thought.isNotEmpty) {
              thinking.write(thought);
              yield AssistantThinking(thought);
            }
            final piece = assistantVisibleText('${msg['content'] ?? ''}');
            if (piece.isNotEmpty) {
              content.write(piece);
              yield AssistantDelta(piece);
            }
            final nextCalls = msg['tool_calls'] as List?;
            if (nextCalls != null && nextCalls.isNotEmpty) {
              calls = nextCalls;
            }
          }
          final evalCount = (chunk['eval_count'] as num?)?.toInt();
          final evalDuration = (chunk['eval_duration'] as num?)?.toInt();
          if (evalCount != null && evalDuration != null && evalDuration > 0) {
            yield AssistantStats(
              tokens: evalCount,
              tokensPerSecond: evalCount / (evalDuration / 1e9),
            );
          }
        }
        final assistant = <String, Object?>{
          'role': 'assistant',
          'content': content.toString(),
          if (thinking.isNotEmpty) 'thinking': thinking.toString(),
          if (calls.isNotEmpty) 'tool_calls': calls,
        };
        _history.add(assistant);
        if (calls.isEmpty) {
          final text = content.toString().trim();
          if (text.isNotEmpty) {
            yield AssistantReply(text);
            return;
          }
          if (thinking.isNotEmpty) {
            throw const FormatException(
              'El modelo pensó pero no contestó. Prueba otra vez o elige un modelo más pequeño.',
            );
          }
          throw const FormatException(
            'El modelo local devolvió una respuesta vacía.',
          );
        }
        for (final raw in calls) {
          final call = raw as Map;
          final function = Map<String, dynamic>.from(
            call['function'] as Map? ?? const {},
          );
          final name = function['name'] as String? ?? '';
          final (result, action) = await tools.call(
            name,
            _args(function['arguments']),
          );
          _history.add({
            'role': 'tool',
            'tool_name': name,
            if (call['id'] != null) 'tool_call_id': call['id'],
            'content': jsonEncode(result),
          });
          yield AssistantToolRan(name, action);
        }
        await tools.refresh();
      }
      yield const AssistantFailed(
        'Se alcanzó el límite de acciones. Las acciones completadas se conservaron.',
      );
    } on Object catch (error) {
      yield AssistantFailed(
        error is TimeoutException
            ? 'Ollama tardó demasiado con $selected. gemma4:12b es pesado: instala Qwen 3.5 4B o usa OpenRouter con un modelo gratuito.'
            : _friendlyError('$error', selected),
      );
    } finally {
      _busy = false;
    }
  }

  static Map<String, Object?> _args(Object? raw) {
    if (raw is Map) return Map<String, Object?>.from(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    }
    return const {};
  }

  Stream<Map<String, dynamic>> pull(String name) async* {
    await for (final chunk in _ndjson('POST', '/api/pull', {
      'model': name,
      'name': name,
      'stream': true,
    })) {
      yield chunk;
    }
  }

  Stream<Map<String, dynamic>> _chatChunks(Map<String, Object?> body) async* {
    final requester = _requester;
    if (requester != null) {
      final response = await requester('POST', '/api/chat', body: body);
      if (response is Map) yield Map<String, dynamic>.from(response);
      return;
    }
    yield* _ndjson('POST', '/api/chat', body);
  }

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) {
    final requester = _requester;
    if (requester != null) return requester(method, path, body: body);
    return _request(method, path, body: body);
  }

  Stream<Map<String, dynamic>> _ndjson(
    String method,
    String path,
    Map<String, Object?> body,
  ) async* {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = method == 'GET'
          ? await client.getUrl(Uri.parse('$baseUrl$path'))
          : await client.postUrl(Uri.parse('$baseUrl$path'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close().timeout(
        const Duration(minutes: 15),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final text = await utf8.decoder.bind(response).join();
        throw HttpException(_httpError(response.statusCode, text));
      }
      final leftover = StringBuffer();
      await for (final chunk in utf8.decoder.bind(response)) {
        leftover.write(chunk);
        var text = leftover.toString();
        leftover.clear();
        while (true) {
          final index = text.indexOf('\n');
          if (index < 0) {
            leftover.write(text);
            break;
          }
          final line = text.substring(0, index).trim();
          text = text.substring(index + 1);
          if (line.isEmpty) continue;
          final decoded = jsonDecode(line);
          if (decoded is Map) yield Map<String, dynamic>.from(decoded);
        }
      }
      final rest = leftover.toString().trim();
      if (rest.isNotEmpty) {
        final decoded = jsonDecode(rest);
        if (decoded is Map) yield Map<String, dynamic>.from(decoded);
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<Object?> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = method == 'GET'
          ? await client.getUrl(Uri.parse('$baseUrl$path'))
          : await client.postUrl(Uri.parse('$baseUrl$path'));
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(_httpError(response.statusCode, text));
      }
      return jsonDecode(text);
    } finally {
      client.close(force: true);
    }
  }

  static String _friendlyError(String raw, String model) {
    final text = assistantVisibleText(raw);
    if (text.contains('TimeoutException') || text.contains('timed out')) {
      return 'Ollama tardó demasiado con $model. Prueba Qwen 3.5 4B (más rápido) o OpenRouter.';
    }
    return 'Ollama no pudo responder. $text';
  }

  static String _httpError(int status, String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map && decoded['error'] != null) {
        return '${decoded['error']}';
      }
    } catch (_) {}
    return 'Error HTTP $status.';
  }
}
