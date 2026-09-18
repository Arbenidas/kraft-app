import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Canal bidireccional de mensajes JSON con la Live API (inyectable en los tests).
abstract interface class LiveTransport {
  Stream<Map<String, Object?>> get messages;
  void send(Map<String, Object?> message);
  Future<void> close();

  /// Motivo del cierre que dio el servidor (p. ej. API key no válida).
  String? get closeReason;
}

typedef LiveConnector = Future<LiveTransport> Function(Uri url);

class WebSocketLiveTransport implements LiveTransport {
  WebSocketLiveTransport._(this._socket);

  final WebSocket _socket;

  static Future<LiveTransport> connect(Uri url) async =>
      WebSocketLiveTransport._(await WebSocket.connect(url.toString()).timeout(const Duration(seconds: 15)));

  @override
  late final Stream<Map<String, Object?>> messages = _socket.map((frame) {
    final text = frame is String ? frame : utf8.decode(frame as List<int>);
    return (jsonDecode(text) as Map).cast<String, Object?>();
  }).asBroadcastStream();

  @override
  void send(Map<String, Object?> message) {
    if (_socket.readyState == WebSocket.open) _socket.add(jsonEncode(message));
  }

  @override
  Future<void> close() => _socket.close(WebSocketStatus.normalClosure);

  @override
  String? get closeReason => _socket.closeReason;
}
