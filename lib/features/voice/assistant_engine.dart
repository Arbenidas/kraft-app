import 'assistant_tools.dart';

class AssistantMessage {
  const AssistantMessage({required this.user, required this.text});

  final bool user;
  final String text;
}

/// Lo que va contando el asistente mientras responde a un mensaje escrito.
sealed class AssistantEvent {
  const AssistantEvent();
}

/// Un trozo de respuesta recién generado: se va escribiendo en pantalla como en Gemini Live.
class AssistantDelta extends AssistantEvent {
  const AssistantDelta(this.text);
  final String text;
}

/// La respuesta completa de un turno. Sustituye a lo que se fue escribiendo con [AssistantDelta].
class AssistantReply extends AssistantEvent {
  const AssistantReply(this.text);
  final String text;
}

class AssistantToolRan extends AssistantEvent {
  const AssistantToolRan(this.name, this.action);
  final String name;
  final AssistantAction? action;
}

class AssistantFailed extends AssistantEvent {
  const AssistantFailed(this.message);
  final String message;
}

/// Texto seguro para la UI: quita caracteres de control y glifos que la fuente no pinta.
String assistantVisibleText(String text) => text.replaceAll(
  RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F\uFFFD\uE000-\uF8FF]'),
  '',
);

/// Cadena de razonamiento que el modelo va generando (Ollama, Gemini, etc.).
class AssistantThinking extends AssistantEvent {
  const AssistantThinking(this.text);
  final String text;
}

/// Ritmo de generación de la respuesta local.
class AssistantStats extends AssistantEvent {
  const AssistantStats({required this.tokens, required this.tokensPerSecond});
  final int tokens;
  final double tokensPerSecond;
}

/// Un modelo con el que se puede charlar por texto usando las herramientas de KRAFT.
/// Hoy: Gemini por API; luego, Gemma en el propio iPad.
abstract interface class AssistantEngine {
  /// Identificador estable para recordar cuál eligió el usuario.
  String get id;

  /// Nombre para la interfaz ("Gemini 3.8 Flash").
  String get label;

  /// `true` si se puede usar ya (hay API key o modelo descargado).
  Future<bool> isReady();

  Stream<AssistantEvent> send(String message);

  /// Empieza una conversación nueva.
  void reset();
}

/// Motores capaces de reconstruir el contexto textual de una charla guardada.
abstract interface class RestorableAssistantEngine {
  void restore(List<AssistantMessage> messages);
}
