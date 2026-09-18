import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../notes/note_bridge.dart';
import '../voice/assistant_tools.dart';
import '../voice/dictation.dart';
import '../voice/gemini_chat.dart';
import '../voice/compatible_chat.dart';
import '../voice/ollama_chat.dart';
import '../voice/voice_controller.dart';
import 'canvas_bridge.dart';
import 'canvas_tools.dart';
import 'mcp_server.dart';

final canvasBridgeProvider = Provider((ref) {
  final bridge = CanvasBridge(ref.watch(canvasesRepositoryProvider));
  ref.onDispose(bridge.dispose);
  return bridge;
});

final noteBridgeProvider = Provider((ref) {
  final bridge = NoteBridge();
  ref.onDispose(bridge.dispose);
  return bridge;
});

/// Servidor MCP. Se crea al arrancar la app y se enciende sólo si el usuario lo activó.
final assistantToolsProvider = Provider(
  (ref) => AssistantTools(
    notes: ref.watch(notesRepositoryProvider),
    tasks: ref.watch(tasksRepositoryProvider),
    projects: ref.watch(projectsRepositoryProvider),
    workItems: ref.watch(workItemsRepositoryProvider),
    noteBridge: ref.watch(noteBridgeProvider),
    canvasBridge: ref.watch(canvasBridgeProvider),
    canvasTools: KraftCanvasTools(
      bridge: ref.watch(canvasBridgeProvider),
      canvases: ref.watch(canvasesRepositoryProvider),
    ),
  ),
);

final mcpControllerProvider = ChangeNotifierProvider((ref) {
  final controller = McpController(
    settings: ref.watch(settingsRepositoryProvider),
    tools: ref.watch(assistantToolsProvider),
  );
  controller.load();
  return controller;
});

/// Dictado en el iPad: hablar y que se escriba, sin conexión ni coste.
final dictationProvider = ChangeNotifierProvider((ref) {
  final dictation = DictationController();
  dictation.load();
  return dictation;
});

/// Asistente: voz con Gemini Live y chat escrito con los proveedores configurados.
final voiceControllerProvider = ChangeNotifierProvider((ref) {
  final tools = ref.watch(assistantToolsProvider);
  final controller = VoiceController(
    tools: tools,
    settings: ref.watch(settingsRepositoryProvider),
    engines: [
      GeminiChatEngine(tools: tools),
      CompatibleChatEngine(
        id: 'deepseek',
        label: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com',
        defaultModel: 'deepseek-flash',
        tools: tools,
        settings: ref.watch(settingsRepositoryProvider),
      ),
      CompatibleChatEngine(
        id: 'mimo',
        label: 'MiMo',
        baseUrl: 'https://api.xiaomimimo.com/v1',
        defaultModel: 'mimo-v2.5-pro',
        tools: tools,
        settings: ref.watch(settingsRepositoryProvider),
      ),
      CompatibleChatEngine(
        id: 'openrouter',
        label: 'OpenRouter',
        baseUrl: 'https://openrouter.ai/api/v1',
        defaultModel: 'openrouter/free',
        tools: tools,
        settings: ref.watch(settingsRepositoryProvider),
        hint:
            'Crea una clave gratis en openrouter.ai/keys. Los modelos :free no cobran tokens.',
        catalog: const [
          CompatibleModel(
            id: 'openrouter/free',
            label: 'Router gratuito',
            detail: 'Elige un modelo gratis con herramientas',
          ),
          CompatibleModel(
            id: 'qwen/qwen3.8-27b:free',
            label: 'Qwen 3.8 27B',
            detail: 'Gratis · herramientas',
          ),
          CompatibleModel(
            id: 'google/gemma-4-26b-a4b-it:free',
            label: 'Gemma 4 26B',
            detail: 'Gratis · más rápido que el 31B',
          ),
          CompatibleModel(
            id: 'google/gemma-4-31b-it:free',
            label: 'Gemma 4 31B',
            detail: 'Gratis',
          ),
          CompatibleModel(
            id: 'nvidia/nemotron-3.5-lightning:free',
            label: 'Nemotron Lightning',
            detail: 'Gratis · veloz',
          ),
          CompatibleModel(
            id: 'liquid/lfm-2.5-2.6b:free',
            label: 'LFM 2.5 2.6B',
            detail: 'Gratis · el más pequeño',
          ),
        ],
      ),
      OllamaChatEngine(
        tools: tools,
        settings: ref.watch(settingsRepositoryProvider),
      ),
    ],
  );
  controller.loadKey();
  return controller;
});
