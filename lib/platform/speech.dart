import 'dart:async';

import 'package:flutter/services.dart';

/// Un trozo de dictado: [text] es todo lo dicho hasta ahora y [done] indica si ya no cambiará.
typedef Dictated = ({String text, bool done});

/// Dictado en el propio iPad (ver `KraftSpeech` en `AppDelegate.swift`).
/// No sale audio del dispositivo: iPadOS 26 usa SpeechAnalyzer y las versiones anteriores SFSpeechRecognizer.
abstract interface class SpeechToText {
  /// `analyzer`, `legacy` o `none` según lo que soporte este iPad.
  Future<String> mode({String? locale});

  /// Pide permiso y empieza a escuchar. Devuelve `false` si no hay permiso o no hay motor.
  Future<bool> start({String? locale});
  Future<void> stop();

  /// Lo que se va reconociendo mientras se habla.
  Stream<Dictated> get results;
}

class ChannelSpeechToText implements SpeechToText {
  const ChannelSpeechToText();

  static const _methods = MethodChannel('kraft/speech');
  static const _text = EventChannel('kraft/speech/text');
  static final Stream<Dictated> _results = _text.receiveBroadcastStream().map((
    event,
  ) {
    final map = (event as Map).cast<Object?, Object?>();
    return (text: '${map['text'] ?? ''}', done: map['final'] == true);
  });

  @override
  Future<String> mode({String? locale}) async {
    try {
      return await _methods.invokeMethod<String>('available', {
            'locale': locale,
          }) ??
          'none';
    } on MissingPluginException {
      return 'none';
    } on PlatformException {
      return 'none';
    }
  }

  @override
  Future<bool> start({String? locale}) async {
    try {
      return await _methods.invokeMethod<bool>('start', {'locale': locale}) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _methods.invokeMethod<void>('stop');
    } on MissingPluginException {
      return;
    }
  }

  @override
  Stream<Dictated> get results => _results;
}
