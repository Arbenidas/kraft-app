import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kraft/platform/voice_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const audio = ChannelVoiceAudio();
  const channel = MethodChannel('kraft/voice');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'un error nativo de AVAudio no se escapa como PlatformException',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(
              code: 'audio',
              message:
                  'The operation couldn’t be completed. (com.apple.coreaudio.avfaudio error -10875.)',
            );
          });

      expect(await audio.start(), MicrophoneStart.failed);
    },
  );

  test('sin permiso el canal nativo devuelve denied', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => false);

    expect(await audio.start(), MicrophoneStart.denied);
  });
}
