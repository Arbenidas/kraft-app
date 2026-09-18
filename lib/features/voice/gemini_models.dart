/// Modelos de la API de Gemini entre los que puede elegir KRAFT.
///
/// Sólo entran los que saben llamar herramientas: sin function calling el asistente
/// no puede crear notas ni dibujar, que es todo lo que hace. Por eso no están aquí
/// los `-image`, los `-tts` ni los de transcripción.
library;

enum ChatModel {
  flash38(
    'gemini-3.8-flash',
    'Gemini 3.8 Flash',
    'El de siempre · 0,75 \$ entrada / 3,75 \$ salida por millón',
    'medium',
  ),
  liteFlash31(
    'gemini-3.1-flash-lite',
    'Gemini 3.1 Flash Lite',
    'El más barato · 0,25 \$ / 1,50 \$ · para hablar mucho rato',
    'minimal',
  ),
  pro31(
    'gemini-3.1-pro-preview',
    'Gemini 3.1 Pro',
    'El más listo · 2 \$ / 12 \$ · diagramas y notas con más criterio',
    'high',
  );

  const ChatModel(this.id, this.label, this.detail, this.thinkingLevel);

  final String id;
  final String label;
  final String detail;
  final String thinkingLevel;

  static ChatModel from(String? id) =>
      values.firstWhere((m) => m.id == id, orElse: () => flash38);
}

enum LiveModel {
  live38(
    'gemini-3.8-live',
    'Gemini 3.8 Live',
    'Voz de baja latencia · unos 1,38 \$ por hora de conversación',
  ),
  live38Thinking(
    'gemini-3.8-live-extended-thinking',
    'Gemini 3.8 Live · piensa más',
    'Razonamiento alto · planifica y revisa; puede tardar más',
  );

  const LiveModel(this.id, this.label, this.detail);

  final String id;
  final String label;
  final String detail;

  static LiveModel from(String? id) =>
      values.firstWhere((m) => m.id == id, orElse: () => live38);
}
