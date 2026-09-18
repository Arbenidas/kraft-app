import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;

import '../../data/repositories.dart';
import 'canvas_bridge.dart';
import 'canvas_tools.dart' show Json;
import '../voice/assistant_tools.dart';

/// Llamada registrada para el panel de actividad.
@immutable
class McpActivity {
  const McpActivity({
    required this.at,
    required this.tool,
    required this.summary,
    required this.ok,
  });

  final DateTime at;
  final String tool;
  final String summary;
  final bool ok;
}

/// JSON-RPC de MCP (sólo herramientas). No sabe nada de HTTP.
class McpProtocol {
  McpProtocol(this.tools, {this.onToolCall, this.onInitialize});

  final AssistantTools tools;
  final void Function(String tool, Json args, Object? error)? onToolCall;
  final void Function(String clientName)? onInitialize;

  static const latestVersion = '2025-06-18';
  static const supportedVersions = [latestVersion, '2025-03-26', '2024-11-05'];

  static const instructions =
      'KRAFT es un espacio creativo para proyectos, requerimientos, subtareas, notas y lienzos. '
      'Antes de editar o borrar, consulta el elemento y usa sus identificadores. '
      'save_task crea o edita subtareas; delete_work elimina una subtarea o requerimiento. '
      'Para diagramas, usa create_diagram para flujos, mapas mentales u organigramas y get_canvas antes de editar. '
      'Si no indicas canvas_id se usa el lienzo abierto en pantalla.';

  /// Responde un mensaje JSON-RPC; `null` si era una notificación (sin respuesta).
  Future<Json?> handle(Object? message) async {
    if (message is! Map) return _error(null, -32600, 'Invalid Request');
    final id = message['id'];
    final method = message['method'];
    // Respuestas del cliente a peticiones nuestras: no hacemos ninguna.
    if (method is! String)
      return message.containsKey('result') || message.containsKey('error')
          ? null
          : _error(id, -32600, 'Invalid Request');
    final notification = !message.containsKey('id');
    final params =
        (message['params'] as Map?)?.cast<String, Object?>() ?? const {};

    if (method.startsWith('notifications/')) return null;

    try {
      final Object result;
      switch (method) {
        case 'initialize':
          final requested = params['protocolVersion'] as String?;
          final client = (params['clientInfo'] as Map?)?['name'] as String?;
          if (client != null) onInitialize?.call(client);
          result = {
            'protocolVersion': supportedVersions.contains(requested)
                ? requested
                : latestVersion,
            'capabilities': {
              'tools': {'listChanged': false},
            },
            'serverInfo': {
              'name': 'kraft',
              'title': 'KRAFT · Lienzo',
              'version': '0.1.0',
            },
            'instructions': instructions,
          };
        case 'ping':
          result = <String, Object?>{};
        case 'tools/list':
          result = {'tools': tools.definitions};
        case 'resources/list':
          result = {'resources': <Object>[]};
        case 'prompts/list':
          result = {'prompts': <Object>[]};
        case 'tools/call':
          final name = params['name'] as String? ?? '';
          if (!tools.definitions.any((tool) => tool['name'] == name)) {
            return _error(id, -32602, 'Herramienta desconocida: $name');
          }
          final args =
              (params['arguments'] as Map?)?.cast<String, Object?>() ??
              const {};
          result = await _callTool(name, args);
        default:
          return notification
              ? null
              : _error(id, -32601, 'Método no soportado: $method');
      }
      return notification
          ? null
          : {'jsonrpc': '2.0', 'id': id, 'result': result};
    } on Object catch (e) {
      return notification ? null : _error(id, -32603, '$e');
    }
  }

  Future<Json> _callTool(String name, Json args) async {
    try {
      final (result, _) = await tools.call(name, args);
      final error = result['error'];
      if (error is String && error.isNotEmpty) {
        final exception = McpToolError(error);
        onToolCall?.call(name, args, exception);
        return {
          'content': [
            {'type': 'text', 'text': error},
          ],
          'isError': true,
        };
      }
      onToolCall?.call(name, args, null);
      return {
        'content': [
          {'type': 'text', 'text': jsonEncode(result)},
        ],
        'isError': false,
      };
    } on McpToolError catch (e) {
      onToolCall?.call(name, args, e);
      return {
        'content': [
          {'type': 'text', 'text': e.message},
        ],
        'isError': true,
      };
    }
  }

  static Json _error(Object? id, int code, String message) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  };
}

/// Transporte "Streamable HTTP" de MCP sin streaming: cada POST recibe su respuesta JSON.
class McpHttpServer {
  McpHttpServer(this.protocol, {required this.token});

  final McpProtocol protocol;

  /// Se exige en `Authorization: Bearer …` (o `?token=` para clientes sin cabeceras).
  String token;
  HttpServer? _server;

  static const path = '/mcp';
  static const _maxBody = 2 * 1024 * 1024;

  int? get port => _server?.port;
  bool get isRunning => _server != null;

  Future<void> start({required int port, InternetAddress? address}) async {
    await stop();
    final server = await HttpServer.bind(
      address ?? InternetAddress.anyIPv4,
      port,
      shared: true,
    );
    _server = server;
    server.listen((request) => unawaited(_handle(request)), onError: (_) {});
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final res = request.response;
    res.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'POST, GET, DELETE, OPTIONS')
      ..set(
        'Access-Control-Allow-Headers',
        'content-type, authorization, mcp-session-id, mcp-protocol-version',
      )
      ..set('Access-Control-Expose-Headers', 'mcp-session-id');
    try {
      final routePath = request.uri.path;
      if (request.method == 'OPTIONS')
        return await _send(res, HttpStatus.noContent);
      if (routePath == '/' && request.method == 'GET') {
        return await _send(
          res,
          HttpStatus.ok,
          text: 'KRAFT MCP activo. Conecta tu cliente a POST $path',
        );
      }
      if (routePath != path && routePath != '$path/')
        return await _send(res, HttpStatus.notFound);
      if (!_authorized(request)) {
        return await _send(
          res,
          HttpStatus.unauthorized,
          json: {
            'error': 'Token incorrecto. Cópialo desde KRAFT › Conectar IA.',
          },
        );
      }
      switch (request.method) {
        case 'GET':
          // Sin canal SSE: el cliente trabaja sólo con POST.
          res.headers.set('Allow', 'POST, DELETE');
          return await _send(res, HttpStatus.methodNotAllowed);
        case 'DELETE':
          return await _send(res, HttpStatus.noContent);
        case 'POST':
          break;
        default:
          return await _send(res, HttpStatus.methodNotAllowed);
      }

      final bytes = <int>[];
      await for (final chunk in request) {
        bytes.addAll(chunk);
        if (bytes.length > _maxBody)
          return await _send(res, HttpStatus.requestEntityTooLarge);
      }
      final Object? body;
      try {
        body = jsonDecode(utf8.decode(bytes));
      } on FormatException {
        return await _send(
          res,
          HttpStatus.badRequest,
          json: McpProtocol._error(null, -32700, 'Parse error'),
        );
      }

      if (body is List) {
        final responses = [
          for (final message in body) await protocol.handle(message),
        ].nonNulls.toList();
        return responses.isEmpty
            ? await _send(res, HttpStatus.accepted)
            : await _send(res, HttpStatus.ok, json: responses);
      }
      final response = await protocol.handle(body);
      if (response == null) return await _send(res, HttpStatus.accepted);
      if (body is Map && body['method'] == 'initialize')
        res.headers.set('Mcp-Session-Id', _randomToken(16));
      return await _send(res, HttpStatus.ok, json: response);
    } on Object catch (e) {
      return await _send(
        res,
        HttpStatus.internalServerError,
        json: {'error': '$e'},
      );
    }
  }

  bool _authorized(HttpRequest request) {
    final header = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    final given = header.startsWith('Bearer ')
        ? header.substring(7).trim()
        : request.uri.queryParameters['token'] ?? '';
    return token.isNotEmpty && _constantTimeEquals(given, token);
  }

  Future<void> _send(
    HttpResponse res,
    int status, {
    Object? json,
    String? text,
  }) async {
    res.statusCode = status;
    if (json != null) {
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode(json));
    } else if (text != null) {
      res.headers.contentType = ContentType.text;
      res.write(text);
    }
    await res.close();
  }
}

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

String _randomToken(int bytes) {
  final random = math.Random.secure();
  return [
    for (var i = 0; i < bytes; i++)
      random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

/// Estado del servidor MCP para la interfaz: encendido, dirección, token y actividad reciente.
class McpController extends ChangeNotifier {
  McpController({required this.settings, required this.tools});

  final SettingsRepository settings;
  final AssistantTools tools;

  static const defaultPort = 8765;
  static const _enabledKey = 'mcp.enabled';
  static const _tokenKey = 'mcp.token';

  late final McpHttpServer _server = McpHttpServer(
    McpProtocol(tools, onToolCall: _recordCall, onInitialize: _recordClient),
    token: '',
  );
  AppLifecycleListener? _lifecycle;

  bool _loaded = false;
  bool enabled = false;
  bool starting = false;
  String token = '';
  int port = defaultPort;
  String? error;
  String? clientName;
  List<String> addresses = const [];
  final List<McpActivity> activity = [];
  DateTime? lastActivityAt;

  bool get running => _server.isRunning;

  /// Dirección preferida para configurar el cliente (Wi-Fi si la hay).
  String get host => addresses.isEmpty ? 'localhost' : addresses.first;
  String get endpoint => 'http://$host:$port${McpHttpServer.path}';

  String get claudeCodeCommand =>
      'claude mcp add --transport http kraft $endpoint --header "Authorization: Bearer $token"';

  String get jsonConfig => const JsonEncoder.withIndent('  ').convert({
    'mcpServers': {
      'kraft': {
        'url': endpoint,
        'headers': {'Authorization': 'Bearer $token'},
      },
    },
  });

  String get stdioBridgeConfig => const JsonEncoder.withIndent('  ').convert({
    'mcpServers': {
      'kraft': {
        'command': 'npx',
        'args': [
          '-y',
          'mcp-remote',
          endpoint,
          '--allow-http',
          '--header',
          'Authorization: Bearer $token',
        ],
      },
    },
  });

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    token = await settings.get(_tokenKey) ?? '';
    if (token.isEmpty) {
      token = _randomToken(18);
      await settings.set(_tokenKey, token);
    }
    _server.token = token;
    enabled = await settings.get(_enabledKey) == 'true';
    notifyListeners();
    // iOS puede cerrar el socket con la app en segundo plano: al volver se reabre.
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (enabled) unawaited(_start());
      },
    );
    if (enabled) await _start();
  }

  Future<void> setEnabled(bool value) async {
    enabled = value;
    notifyListeners();
    await settings.set(_enabledKey, '$value');
    value ? await _start() : await _stop();
  }

  Future<void> regenerateToken() async {
    token = _randomToken(18);
    _server.token = token;
    await settings.set(_tokenKey, token);
    notifyListeners();
  }

  Future<void> _start() async {
    starting = true;
    error = null;
    notifyListeners();
    try {
      await _server.start(port: port);
      addresses = await _localAddresses();
    } on SocketException catch (e) {
      error =
          'No se pudo abrir el puerto $port: ${e.osError?.message ?? e.message}';
    } finally {
      starting = false;
      notifyListeners();
    }
  }

  Future<void> _stop() async {
    await _server.stop();
    clientName = null;
    notifyListeners();
  }

  static Future<List<String>> _localAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      // en0 = Wi-Fi en iPad y Mac.
      interfaces.sort(
        (a, b) => (a.name == 'en0' ? 0 : 1).compareTo(b.name == 'en0' ? 0 : 1),
      );
      return [
        for (final i in interfaces)
          for (final a in i.addresses)
            if (!a.isLoopback && !a.address.startsWith('169.254')) a.address,
      ];
    } on Object {
      return const [];
    }
  }

  void _recordClient(String name) {
    clientName = name;
    notifyListeners();
  }

  void _recordCall(String tool, Json args, Object? failure) {
    final now = DateTime.now();
    lastActivityAt = now;
    activity.insert(
      0,
      McpActivity(
        at: now,
        tool: tool,
        summary: failure?.toString() ?? _summarize(tool, args),
        ok: failure == null,
      ),
    );
    if (activity.length > 30) activity.removeLast();
    notifyListeners();
  }

  static String _summarize(String tool, Json args) {
    int count(String key) => (args[key] as List?)?.length ?? 0;
    return switch (tool) {
      'create_diagram' =>
        '${count('nodes')} nodos · ${count('edges')} conexiones',
      'add_elements' => '${count('elements')} elementos',
      'delete_elements' => '${count('ids')} borrados',
      'create_canvas' => '${args['title'] ?? ''}',
      'save_task' || 'save_tasks' || 'save_project_work' || 'delete_work' =>
        '${args['title'] ?? args['task_id'] ?? args['requirement_id'] ?? 'OK'}',
      'update_element' ||
      'connect_elements' ||
      'get_canvas' ||
      'open_canvas' ||
      'list_canvases' ||
      'close_view' => 'OK',
      _ => '',
    };
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    unawaited(_server.stop());
    super.dispose();
  }
}
