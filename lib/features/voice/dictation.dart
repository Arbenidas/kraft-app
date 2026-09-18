import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../platform/speech.dart';

/// Dictado: pasa a texto lo que se dice, dentro del iPad y sin coste.
/// Se usa para escribirle al asistente sin teclado y para dictar dentro de una nota.
class DictationController extends ChangeNotifier {
  DictationController({
    SpeechToText speech = const ChannelSpeechToText(),
    this.locale = 'es-ES',
    this.silence = const Duration(milliseconds: 1500),
  }) : _speech = speech;

  final SpeechToText _speech;
  final String locale;

  /// Cuánto hay que callar, con texto ya dictado, para dar la frase por cerrada.
  final Duration silence;

  /// Qué motor hay: `analyzer` (iPadOS 26), `legacy` o `none`. `null` mientras no se ha comprobado.
  String? engine;
  bool listening = false;
  String? error;

  /// Lo dictado en esta sesión (se va corrigiendo mientras hablas).
  String text = '';

  /// Si [start] pidió enviar al callar: al detectar silencio se para solo.
  bool sendWhenQuiet = false;

  /// Se pone a `true` un instante al terminar por silencio, para que el chat envíe.
  bool readyToSend = false;

  StreamSubscription<Dictated>? _results;
  Timer? _quiet;

  bool get supported => engine != null && engine != 'none';

  Future<void> load() async {
    engine = await _speech.mode(locale: locale);
    notifyListeners();
  }

  Future<void> toggle() => listening ? stop() : start();

  Future<void> start({bool sendWhenQuiet = false}) async {
    if (listening) return;
    engine ??= await _speech.mode(locale: locale);
    if (!supported) {
      error = 'Este iPad no tiene dictado disponible.';
      notifyListeners();
      return;
    }
    error = null;
    text = '';
    this.sendWhenQuiet = sendWhenQuiet;
    _quiet?.cancel();
    // Si la sesión nativa anterior se quedó a medias, hay que soltar el micrófono
    // antes de volver a escuchar. Si no, el segundo dictado no oye nada.
    await _speech.stop();
    await _listen();
    listening = await _speech.start(locale: locale);
    if (!listening) {
      this.sendWhenQuiet = false;
      error =
          'Permite el micrófono y el reconocimiento de voz en Ajustes › KRAFT.';
    }
    notifyListeners();
  }

  Future<void> _listen() async {
    if (_results != null) return;
    _results = _speech.results.listen(
      (event) {
        text = event.text;
        _armQuiet(event.done);
        notifyListeners();
      },
      onError: (Object e) {
        error = '$e';
        listening = false;
        _quiet?.cancel();
        notifyListeners();
      },
      onDone: () {
        _results = null;
        if (listening) {
          listening = false;
          _quiet?.cancel();
          notifyListeners();
        }
      },
    );
  }

  void _armQuiet(bool utteranceDone) {
    _quiet?.cancel();
    if (!sendWhenQuiet || !listening || text.trim().isEmpty) return;
    // Un `final` del reconocedor ya es una pausa: espera un poco por si sigue
    // la frase. Si sólo llegan parciales, espera el silencio completo.
    _quiet = Timer(
      utteranceDone ? const Duration(milliseconds: 800) : silence,
      () {
        if (listening && text.trim().isNotEmpty) unawaited(stop());
      },
    );
  }

  Future<void> stop() async {
    _quiet?.cancel();
    _quiet = null;
    final shouldHandOff = sendWhenQuiet && text.trim().isNotEmpty;
    sendWhenQuiet = false;
    listening = false;
    await _speech.stop();
    // El último resultado puede llegar justo después de parar.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    readyToSend = shouldHandOff && text.trim().isNotEmpty;
    notifyListeners();
    readyToSend = false;
  }

  @override
  void dispose() {
    _quiet?.cancel();
    unawaited(_results?.cancel());
    _results = null;
    unawaited(_speech.stop());
    super.dispose();
  }
}
