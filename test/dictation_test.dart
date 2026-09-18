import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kraft/features/voice/dictation.dart';
import 'package:kraft/platform/speech.dart';
import 'package:kraft/utils/text_match.dart';

class _FakeSpeech implements SpeechToText {
  _FakeSpeech({this.engine = 'analyzer', this.allowed = true});

  final String engine;
  final bool allowed;
  final _events = StreamController<Dictated>.broadcast();
  var starts = 0;
  var stops = 0;

  @override
  Future<String> mode({String? locale}) async => engine;

  @override
  Future<bool> start({String? locale}) async {
    starts++;
    return allowed;
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Stream<Dictated> get results => _events.stream;

  void say(String text, {bool done = false}) =>
      _events.add((text: text, done: done));
}

void main() {
  group('dictado', () {
    test(
      'lo que se va reconociendo se corrige hasta el resultado final',
      () async {
        final speech = _FakeSpeech();
        final dictation = DictationController(speech: speech);
        await dictation.load();
        expect(dictation.supported, isTrue);

        await dictation.start();
        expect(dictation.listening, isTrue);

        speech.say('recuérdame');
        await pumpEventQueue();
        expect(dictation.text, 'recuérdame');

        speech.say('Recuérdame comprar pan mañana.', done: true);
        await pumpEventQueue();
        expect(dictation.text, 'Recuérdame comprar pan mañana.');

        await dictation.stop();
        expect(dictation.listening, isFalse);
        expect(speech.stops, 2);
        dictation.dispose();
      },
    );

    test('el segundo dictado sigue oyendo después de parar', () async {
      final speech = _FakeSpeech();
      final dictation = DictationController(speech: speech);
      await dictation.start();
      speech.say('primera');
      await pumpEventQueue();
      await dictation.stop();

      await dictation.start();
      expect(dictation.listening, isTrue);
      expect(speech.starts, 2);
      speech.say('segunda vez');
      await pumpEventQueue();
      expect(dictation.text, 'segunda vez');
      await dictation.stop();
      dictation.dispose();
    });

    test('al callar un momento termina solo si se pidió enviar', () async {
      final speech = _FakeSpeech();
      final dictation = DictationController(
        speech: speech,
        silence: const Duration(milliseconds: 20),
      );
      await dictation.start(sendWhenQuiet: true);
      speech.say('ve al proyecto kraft');
      await pumpEventQueue();
      expect(dictation.listening, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 220));
      expect(dictation.listening, isFalse);
      expect(dictation.text, 've al proyecto kraft');
      dictation.dispose();
    });

    test('dictar en el campo no se corta al callar', () async {
      final speech = _FakeSpeech();
      final dictation = DictationController(
        speech: speech,
        silence: const Duration(milliseconds: 20),
      );
      await dictation.start();
      speech.say('solo el campo');
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(dictation.listening, isTrue);
      await dictation.stop();
      dictation.dispose();
    });

    test('sin permiso avisa en vez de quedarse escuchando', () async {
      final dictation = DictationController(
        speech: _FakeSpeech(allowed: false),
      );
      await dictation.start();
      expect(dictation.listening, isFalse);
      expect(dictation.error, contains('micrófono'));
      dictation.dispose();
    });

    test('en un iPad sin dictado no se ofrece', () async {
      final dictation = DictationController(
        speech: _FakeSpeech(engine: 'none'),
      );
      await dictation.load();
      expect(dictation.supported, isFalse);
      dictation.dispose();
    });
  });

  group('reconocer de qué habla el usuario', () {
    test('ignora acentos, artículos y palabras de relleno', () {
      expect(keywords('mi proyecto de la Calculadora Científica'), {
        'calculadora',
        'cientifica',
      });
      expect(normalize('Arquitectura Tecnológica'), 'arquitectura tecnologica');
    });

    test('dos títulos del mismo tema se parecen; dos distintos no', () {
      final limpia = keywords('Arquitectura limpia calculadora');
      expect(
        overlap(limpia, keywords('Arquitectura Tecnológica Calculadora')),
        greaterThanOrEqualTo(0.5),
      );
      expect(overlap(limpia, keywords('Lista de la compra')), 0);
    });

    test('puntúa un texto por las palabras que contiene', () {
      expect(
        score(
          keywords('la calculadora'),
          'Arquitectura limpia de la calculadora',
        ),
        1,
      );
      expect(
        score(keywords('calculadora científica'), 'Notas de la calculadora'),
        0.5,
      );
    });
  });
}
