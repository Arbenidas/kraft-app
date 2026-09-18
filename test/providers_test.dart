import 'package:drift/drift.dart' show DatabaseConnection, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kraft/data/db/database.dart';
import 'package:kraft/data/providers.dart';
import 'package:kraft/features/ai/ai_providers.dart';
import 'package:kraft/features/voice/compatible_chat.dart';
import 'package:kraft/features/voice/gemini_chat.dart';
import 'package:kraft/features/voice/gemini_models.dart';
import 'package:kraft/features/voice/voice_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('elección de modelo', () {
    test(
      'cambiar el modelo del chat llega al motor de Gemini y se guarda',
      () async {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
        final db = AppDatabase(
          DatabaseConnection(
            NativeDatabase.memory(),
            closeStreamsSynchronously: true,
          ),
          seed: false,
        );
        final container = ProviderContainer(
          overrides: [databaseProvider.overrideWithValue(db)],
        );
        final voice = container.read(voiceControllerProvider);

        expect(voice.chatModel, ChatModel.flash38);
        await voice.setChatModel(ChatModel.liteFlash31);

        final gemini = voice.engines.whereType<GeminiChatEngine>().single;
        expect(gemini.model, 'gemini-3.1-flash-lite');
        final openrouter = voice.engines
            .whereType<CompatibleChatEngine>()
            .firstWhere((engine) => engine.id == 'openrouter');
        expect(openrouter.defaultModel, 'openrouter/free');
        expect(openrouter.catalog, isNotEmpty);
        expect(
          await container
              .read(settingsRepositoryProvider)
              .get(VoiceController.chatModelKey),
          'gemini-3.1-flash-lite',
        );

        // El modo económico también se recuerda: es lo que evita abrir la Live API.
        await voice.setEconomy(true);
        expect(
          await container
              .read(settingsRepositoryProvider)
              .get(VoiceController.economyKey),
          'true',
        );

        container.dispose();
        await db.close();
      },
    );
  });
}
