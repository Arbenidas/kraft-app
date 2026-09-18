import 'package:flutter/services.dart';

/// Voz del sistema para respuestas de los modelos de texto, incluidos los
/// modelos locales. Gemini Live reproduce su propio PCM y no usa este canal.
abstract interface class SpeechOutput {
  Future<void> speak(String text, {String locale = 'es-ES'});
  Future<void> stop();
}

class ChannelSpeechOutput implements SpeechOutput {
  const ChannelSpeechOutput();

  static const _channel = MethodChannel('kraft/tts');

  @override
  Future<void> speak(String text, {String locale = 'es-ES'}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    try {
      await _channel.invokeMethod<void>('speak', {
        'text': trimmed,
        'locale': locale,
      });
    } on Object {
      // Las plataformas sin síntesis nativa siguen mostrando la respuesta.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on Object {
      // Sin canal nativo no hay nada que detener.
    }
  }
}
