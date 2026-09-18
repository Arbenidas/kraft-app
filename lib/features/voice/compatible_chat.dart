import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../data/repositories.dart';
import '../../platform/secure_store.dart';
import 'assistant_engine.dart';
import 'assistant_tools.dart';
import 'gemini_chat.dart';

typedef CompatibleSender =
    Future<Map<String, dynamic>> Function(
      Uri uri,
      String key,
      Map<String, Object?> body,
    );

class CompatibleModel {
  const CompatibleModel({required this.id, required this.label, this.detail});
  final String id;
  final String label;
  final String? detail;
}

/// DeepSeek, MiMo y OpenRouter usan el mismo contrato OpenAI de herramientas.
class CompatibleChatEngine
    implements AssistantEngine, RestorableAssistantEngine {
  CompatibleChatEngine({
    required this.id,
    required this.label,
    required this.baseUrl,
    required this.defaultModel,
    required this.tools,
    required this.settings,
    this.store = const KeychainStore(),
    this.catalog = const [],
    this.hint,
    CompatibleSender? sender,
  }) : _sender = sender ?? httpSend;
  @override
  final String id;
  @override
  final String label;
  final String baseUrl, defaultModel;
  final List<CompatibleModel> catalog;
  final String? hint;
  final AssistantTools tools;
  final SettingsRepository settings;
  final SecureStore store;
  final CompatibleSender _sender;
  final List<Map<String, Object?>> _history = [];
  bool _busy = false;
  String get keyName => 'assistant.$id.apiKey';
  String get modelKey => 'assistant.$id.model';
  @override
  Future<bool> isReady() async =>
      (await store.read(keyName))?.trim().isNotEmpty ?? false;
  @override
  void reset() => _history.clear();
  @override
  void restore(List<AssistantMessage> messages) {
    _history
      ..clear()
      ..addAll([
        for (final m in messages.skip(
          messages.length > 16 ? messages.length - 16 : 0,
        ))
          {'role': m.user ? 'user' : 'assistant', 'content': m.text},
      ]);
  }

  @override
  Stream<AssistantEvent> send(String message) async* {
    if (_busy) {
      yield const AssistantFailed('Espera a que termine la respuesta actual.');
      return;
    }
    _busy = true;
    try {
      final key = await store.read(keyName);
      if (key == null || key.trim().isEmpty) {
        yield AssistantFailed('Agrega la API key de $label en Ajustes.');
        return;
      }
      await tools.refresh();
      // Trim only at complete user-turn boundaries, never between calls and results.
      while (_history.length > 36) {
        final next = _history.indexWhere((m) => m['role'] == 'user', 1);
        if (next < 0) break;
        _history.removeRange(0, next);
      }
      _history.add({'role': 'user', 'content': message});
      for (var round = 0; round < 8; round++) {
        final response = await _sender(
          Uri.parse('$baseUrl/chat/completions'),
          key,
          {
            'model': await settings.get(modelKey) ?? defaultModel,
            'messages': [
              {
                'role': 'system',
                'content': GeminiChatEngine.instructions(tools),
              },
              ..._history,
            ],
            'stream': false,
            if (id == 'mimo')
              'max_completion_tokens': 4096
            else
              'max_tokens': 4096,
            'tools': [
              for (final tool in tools.definitions)
                {
                  'type': 'function',
                  'function': {
                    'name': tool['name'],
                    'description': tool['description'],
                    'parameters': tool['inputSchema'],
                  },
                },
            ],
          },
        );
        final choices = response['choices'] as List? ?? [];
        if (choices.isEmpty)
          throw const FormatException(
            'El proveedor no devolvió una respuesta.',
          );
        final answer = Map<String, Object?>.from(
          (choices.first as Map)['message'] as Map,
        );
        final calls = answer['tool_calls'] as List? ?? [];
        // Preserve reasoning_content for providers that require it during tool rounds.
        _history.add(answer);
        if (calls.isEmpty) {
          final text = assistantVisibleText(answer['content'] as String? ?? '');
          if (text.trim().isEmpty)
            throw const FormatException(
              'Respuesta vacía; revisa el modelo configurado.',
            );
          yield AssistantReply(text);
          return;
        }
        for (final raw in calls) {
          final call = raw as Map;
          final function = call['function'] as Map;
          final name = function['name'] as String;
          Map<String, Object?> result;
          AssistantAction? action;
          try {
            final args = Map<String, Object?>.from(
              jsonDecode(function['arguments'] as String) as Map,
            );
            (result, action) = await tools.call(name, args);
          } catch (_) {
            result = {
              'error':
                  'Argumentos inválidos. Corrige los parámetros según el esquema.',
            };
          }
          _history.add({
            'role': 'tool',
            'tool_call_id': call['id'],
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
      yield AssistantFailed(_friendly(error));
    } finally {
      _busy = false;
    }
  }

  static Future<Map<String, dynamic>> httpSend(
    Uri uri,
    String key,
    Map<String, Object?> body,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 25));
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      if (uri.host == 'api.xiaomimimo.com') request.headers.set('api-key', key);
      if (uri.host.contains('openrouter.ai')) {
        request.headers.set('HTTP-Referer', 'https://kraft.app');
        request.headers.set('X-Title', 'KRAFT');
      }
      request.write(jsonEncode(body));
      final wait = uri.host.contains('openrouter.ai')
          ? const Duration(minutes: 3)
          : const Duration(minutes: 2);
      final response = await request.close().timeout(wait);
      final text = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(minutes: 2));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(switch (response.statusCode) {
          401 || 403 => 'API key inválida o sin permiso para este modelo.',
          402 => 'Este modelo pide créditos. Elige uno marcado como gratuito.',
          404 => 'Ese modelo no está disponible ahora. Elige otro de la lista.',
          429 =>
            uri.host.contains('openrouter.ai')
                ? 'Límite de los modelos gratis de OpenRouter. Espera un momento o cambia de modelo.'
                : 'Límite de uso alcanzado; revisa tu cuota.',
          _ =>
            'Error HTTP ${response.statusCode}. Revisa el nombre del modelo o inténtalo de nuevo.',
        });
      }
      return jsonDecode(text) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  String _friendly(Object error) {
    final text = assistantVisibleText('$error');
    if (error is TimeoutException ||
        text.contains('TimeoutException') ||
        text.contains('timed out')) {
      return '$label tardó demasiado. Prueba otro modelo${id == 'openrouter' ? ' gratuito' : ''} en Ajustes.';
    }
    if (error is HttpException) return '$label: ${error.message}';
    return '$label no pudo responder. $text';
  }
}
