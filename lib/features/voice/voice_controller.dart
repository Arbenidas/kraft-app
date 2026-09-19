import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../platform/secure_store.dart';
import '../../platform/speech_output.dart';
import '../../platform/voice_audio.dart';
import '../../data/repositories.dart';
import 'assistant_engine.dart';
import 'creation_policy.dart';
import 'assistant_tools.dart';
import 'conversation_history.dart';
import 'gemini_chat.dart';
import 'gemini_models.dart';
import 'live_protocol.dart';
import 'live_transport.dart';

enum VoiceStatus { idle, needsKey, connecting, listening, speaking, error }

typedef AiCreationEvent = ({
  String title,
  String subtitle,
  IconData icon,
  String? actionLabel,
  VoidCallback? onAction,
});

/// Una intervención en la conversación (se va completando mientras llega la transcripción).
class VoiceTurn {
  VoiceTurn({required this.user, this.text = ''});

  final bool user;
  String text;
}

/// Conversación de voz con Gemini Live: micrófono → WebSocket → altavoz, y las herramientas de KRAFT en medio.
class VoiceController extends ChangeNotifier {
  VoiceController({
    required this.tools,
    required this.engines,
    required SettingsRepository settings,
    SecureStore store = const KeychainStore(),
    VoiceAudio audio = const ChannelVoiceAudio(),
    SpeechOutput speech = const ChannelSpeechOutput(),
    LiveConnector connect = WebSocketLiveTransport.connect,
    String model = LiveProtocol.defaultModel,
    bool? liveAudio,
  }) : _settings = settings,
       _store = store,
       _audio = audio,
       _speech = speech,
       _connect = connect,
       // iPad y Mac registran el mismo puente nativo de PCM para Gemini Live.
       liveAudio =
           liveAudio ??
           (defaultTargetPlatform == TargetPlatform.iOS ||
               defaultTargetPlatform == TargetPlatform.macOS),
       engine = engines.first,
       // ignore: prefer_initializing_formals
       model = model;

  /// `true` si este aparato puede mantener una conversación de voz.
  final bool liveAudio;

  /// Motores de chat escrito disponibles.
  final List<AssistantEngine> engines;
  AssistantEngine engine;
  final SettingsRepository _settings;

  final AssistantTools tools;
  final SecureStore _store;
  final VoiceAudio _audio;
  final SpeechOutput _speech;
  final LiveConnector _connect;

  static const apiKeyName = VoiceKeys.apiKey;
  static const engineKey = 'assistant.engine';
  static const chatModelKey = 'assistant.chatModel';
  static const liveModelKey = 'assistant.liveModel';
  static const economyKey = 'assistant.economy';
  static const speakRepliesKey = 'assistant.speakReplies';
  static const microphoneKey = 'assistant.microphone';
  static const chatHistoryKey = 'assistant.chatHistory.v1';
  static const _historyLimit = 30;

  /// Modelo de la Live API. Se aplica en la siguiente conversación.
  String model;

  /// Modo económico: el botón "Hablar" dicta con el motor de iPadOS y responde con la
  /// voz del sistema en vez de abrir la Live API, que cobra el audio por minuto.
  bool economy = false;

  bool get usesDictation => economy || engine.id != 'gemini';

  VoiceStatus status = VoiceStatus.idle;
  String? error;
  bool muted = false;
  bool? hasKey;
  bool speakReplies = true;
  List<MicrophoneDevice> microphones = const [MicrophoneDevice.system];
  String selectedMicrophoneId = MicrophoneDevice.system.id;
  bool loadingMicrophones = false;
  String? microphoneError;

  /// Nivel del micrófono (0–1) para animar el botón.
  double level = 0;

  /// El asistente está escribiendo una respuesta (chat de texto).
  bool thinking = false;
  bool liveThinking = false;
  String thought = '';
  double? tokensPerSecond;
  int? generatedTokens;
  int _liveEpoch = 0;
  Future<void> _toolQueue = Future.value();
  final Set<String> _cancelledTools = {};
  final Set<String> _seenTools = {};
  final List<VoiceTurn> turns = [];
  final List<AssistantAction> actions = [];
  final _creationEventsController =
      StreamController<AiCreationEvent>.broadcast();
  Stream<AiCreationEvent> get creationEvents =>
      _creationEventsController.stream;

  void emitAiCreation({
    required String title,
    required String subtitle,
    IconData icon = Symbols.auto_awesome,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _creationEventsController.add((
      title: title,
      subtitle: subtitle,
      icon: icon,
      actionLabel: actionLabel,
      onAction: onAction,
    ));
  }

  void _onToolExecuted(String name, AssistantAction? action) {
    if (action == null) return;
    if (name == 'create_project') {
      emitAiCreation(
        title: 'Nuevo proyecto creado',
        subtitle: action.label,
        icon: Symbols.auto_awesome,
        actionLabel: action.open != null ? 'Abrir' : null,
        onAction: action.open,
      );
    } else if (name == 'save_project_work') {
      final isReq =
          action.label.toLowerCase().contains('requerimiento') ||
          !action.label.toLowerCase().contains('actividad');
      emitAiCreation(
        title: isReq
            ? 'Requerimiento generado con IA'
            : 'Actividad planificada con IA',
        subtitle: action.label,
        icon: isReq ? Symbols.task_alt : Symbols.calendar_today,
        actionLabel: action.open != null ? 'Ver' : null,
        onAction: action.open,
      );
    } else if (name == 'create_note') {
      emitAiCreation(
        title: 'Nota creada con IA',
        subtitle: action.label,
        icon: Symbols.edit_note,
        actionLabel: action.open != null ? 'Abrir' : null,
        onAction: action.open,
      );
    } else if (name == 'create_canvas' || name == 'create_diagram') {
      emitAiCreation(
        title: 'Lienzo generado con IA',
        subtitle: action.label,
        icon: Symbols.auto_awesome_mosaic,
        actionLabel: action.open != null ? 'Abrir' : null,
        onAction: action.open,
      );
    }
  }

  List<ConversationThread> _conversations = [];
  String? _activeConversationId;

  LiveTransport? _transport;
  StreamSubscription<Map<String, Object?>>? _messages;
  StreamSubscription<Uint8List>? _mic;
  bool _ready = false;
  DateTime _lastLevelAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _playbackEndsAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _explanationEpoch = 0;

  static const _playbackSampleRate = 24000;
  static const _playbackTail = Duration(milliseconds: 250);

  bool get active =>
      status == VoiceStatus.connecting ||
      status == VoiceStatus.listening ||
      status == VoiceStatus.speaking;

  List<ConversationThread> get conversations {
    final copy = List<ConversationThread>.of(_conversations);
    copy.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(copy);
  }

  String? get activeConversationId => _activeConversationId;

  Future<void> loadKey() async {
    hasKey = (await _store.read(apiKeyName))?.isNotEmpty ?? false;
    final saved = await _settings.get(engineKey);
    engine = engines.firstWhere(
      (e) => e.id == saved,
      orElse: () => engines.first,
    );
    speakReplies = await _settings.get(speakRepliesKey) != 'false';
    economy = await _settings.get(economyKey) == 'true';
    model = LiveModel.from(await _settings.get(liveModelKey)).id;
    // `_applyChatModel`, no `chatModel = …`: asignar el campo a secas dejaba el motor
    // con el modelo por defecto y Ajustes enseñando otro.
    _applyChatModel = ChatModel.from(await _settings.get(chatModelKey));
    selectedMicrophoneId =
        await _settings.get(microphoneKey) ?? MicrophoneDevice.system.id;
    await _loadConversations();
    await refreshMicrophones(notify: false);
    notifyListeners();
  }

  Future<void> refreshMicrophones({bool notify = true}) async {
    loadingMicrophones = true;
    microphoneError = null;
    if (notify) notifyListeners();
    try {
      final found = await _audio.microphones();
      final unique = <String, MicrophoneDevice>{
        MicrophoneDevice.system.id: MicrophoneDevice.system,
        for (final device in found) device.id: device,
      };
      microphones = unique.values.toList(growable: false);
      if (!unique.containsKey(selectedMicrophoneId)) {
        selectedMicrophoneId = MicrophoneDevice.system.id;
        await _settings.set(microphoneKey, selectedMicrophoneId);
      }
    } on Object catch (e) {
      microphones = const [MicrophoneDevice.system];
      selectedMicrophoneId = MicrophoneDevice.system.id;
      microphoneError = 'No se pudieron leer los micrófonos: $e';
    } finally {
      loadingMicrophones = false;
      if (notify) notifyListeners();
    }
  }

  Future<void> setMicrophone(String id) async {
    if (id == selectedMicrophoneId ||
        !microphones.any((device) => device.id == id)) {
      return;
    }
    final restart = active;
    if (restart) await stop();
    selectedMicrophoneId = id;
    microphoneError = null;
    notifyListeners();
    await _settings.set(microphoneKey, id);
    if (restart) await start();
  }

  Future<void> setSpeakReplies(bool value) async {
    speakReplies = value;
    if (!value) await _speech.stop();
    notifyListeners();
    await _settings.set(speakRepliesKey, '$value');
  }

  /// Para el altavoz antes de dictar: si sigue leyendo la respuesta, el micrófono no oye.
  Future<void> stopSpeaking() => _speech.stop();

  /// Modelo del chat escrito de Gemini. Se guarda y se aplica al motor en caliente.
  ChatModel chatModel = ChatModel.flash38;

  set _applyChatModel(ChatModel next) {
    chatModel = next;
    for (final e in engines) {
      if (e is GeminiChatEngine) e.model = next.id;
    }
  }

  Future<void> setChatModel(ChatModel next) async {
    if (next == chatModel) return;
    if (engine.id == 'gemini' && turns.isNotEmpty) {
      await _saveCurrentConversation();
      _applyChatModel = next;
      _startBlankConversation();
      await _saveCurrentConversation();
    } else {
      _applyChatModel = next;
      engine.reset();
      await _saveCurrentConversation();
    }
    notifyListeners();
    await _settings.set(chatModelKey, next.id);
  }

  Future<void> setLiveModel(LiveModel next) async {
    model = next.id;
    notifyListeners();
    await _settings.set(liveModelKey, next.id);
    // Una conversación abierta sigue con el modelo con el que se abrió.
  }

  Future<void> setEconomy(bool value) async {
    economy = value;
    if (value && active) await stop();
    notifyListeners();
    await _settings.set(economyKey, '$value');
  }

  /// Cambia entre Gemini (API) y Gemma (en el iPad) para el chat escrito.
  Future<void> setEngine(AssistantEngine next) async {
    if (identical(engine, next) || thinking) return;
    if (active) await stop();
    await _saveCurrentConversation();
    engine = next;
    if (turns.isEmpty) {
      engine.reset();
      await _saveCurrentConversation();
    } else {
      _startBlankConversation();
      await _saveCurrentConversation();
    }
    notifyListeners();
    await _settings.set(engineKey, next.id);
  }

  Future<void> newConversation() async {
    if (thinking) return;
    await _saveCurrentConversation();
    _startBlankConversation();
    await _saveCurrentConversation();
    notifyListeners();
  }

  Future<void> openConversation(String id) async {
    if (thinking) return;
    if (id == _activeConversationId) return;
    await _saveCurrentConversation();
    final thread = _conversations.where((item) => item.id == id).firstOrNull;
    if (thread == null) return;
    engine = engines.firstWhere(
      (candidate) => candidate.id == thread.engineId,
      orElse: () => engines.first,
    );
    if (engine.id == 'gemini' && thread.modelId.isNotEmpty) {
      _applyChatModel = ChatModel.from(thread.modelId);
    }
    _activeConversationId = thread.id;
    turns
      ..clear()
      ..addAll([
        for (final entry in thread.entries)
          VoiceTurn(user: entry.user, text: entry.text),
      ]);
    actions.clear();
    error = null;
    _restoreEngineContext();
    await _settings.set(engineKey, engine.id);
    if (engine.id == 'gemini') {
      await _settings.set(chatModelKey, chatModel.id);
    }
    await _writeArchive();
    notifyListeners();
  }

  Future<void> clearCurrentConversation() async {
    final id = _activeConversationId;
    if (id != null) {
      _conversations.removeWhere((thread) => thread.id == id);
    }
    _startBlankConversation();
    await _saveCurrentConversation();
    notifyListeners();
  }

  Future<void> clearConversationHistory() async {
    _conversations = [];
    _startBlankConversation();
    await _saveCurrentConversation();
    notifyListeners();
  }

  /// Escribe al asistente. Si hay conversación de voz, entra por ahí; si no, responde el chat elegido.
  Future<void> ask(String message, {String? instruction}) async {
    final text = message.trim();
    if (text.isEmpty || thinking) return;
    if (_ready) {
      sendText(instruction == null ? text : '$instruction\nUsuario: $text');
      return;
    }
    turns.add(VoiceTurn(user: true, text: text));
    final explanationEpoch = ++_explanationEpoch;
    thinking = true;
    thought = '';
    tokensPerSecond = null;
    generatedTokens = null;
    error = null;
    notifyListeners();
    // El turno que se está escribiendo: los trozos se van añadiendo y al final se sustituye por el texto completo.
    VoiceTurn? writing;
    var playedGuidedExplanation = false;
    try {
      await _speech.stop();
      await for (final event in engine.send(
        instruction == null ? text : '$instruction\nUsuario: $text',
      )) {
        switch (event) {
          case AssistantDelta(:final text):
            if (writing == null) {
              writing = VoiceTurn(user: false, text: text);
              turns.add(writing);
            } else {
              writing.text += text;
            }
          case AssistantThinking(:final text):
            thought += assistantVisibleText(text);
          case AssistantStats(:final tokens, :final tokensPerSecond):
            generatedTokens = tokens;
            this.tokensPerSecond = tokensPerSecond;
          case AssistantReply(:final text):
            if (writing != null) {
              writing.text = text;
              writing = null;
            } else {
              turns.add(VoiceTurn(user: false, text: text));
            }
            if (speakReplies && !_ready && !playedGuidedExplanation) {
              unawaited(_speech.speak(text));
            }
          case AssistantToolRan(:final name, :final action):
            // Lo dicho antes de usar una herramienta ya es un mensaje terminado.
            writing = null;
            if (action != null) {
              actions.insert(0, action);
              if (actions.length > 8) actions.removeLast();
              _onToolExecuted(name, action);
              if (action.explanation case final explanation?
                  when speakReplies && !_ready) {
                playedGuidedExplanation = true;
                await _playExplanation(explanation, explanationEpoch);
              }
            }
          case AssistantFailed(:final message):
            error = assistantVisibleText(message);
        }
        notifyListeners();
      }
    } finally {
      thinking = false;
      await _saveCurrentConversation();
      notifyListeners();
    }
  }

  Future<void> saveKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return;
    await _store.write(apiKeyName, trimmed);
    hasKey = true;
    if (status == VoiceStatus.needsKey || status == VoiceStatus.error) {
      status = VoiceStatus.idle;
    }
    error = null;
    notifyListeners();
  }

  Future<void> forgetKey() async {
    await stop();
    await _store.delete(apiKeyName);
    hasKey = false;
    notifyListeners();
  }

  Future<void> start() async {
    if (active || usesDictation) return;
    if (!liveAudio) {
      _fail(
        'Este dispositivo no tiene el audio necesario. Aquí escribe al asistente o usa el dictado.',
      );
      return;
    }
    final key = await _store.read(apiKeyName);
    if (key == null || key.isEmpty) {
      hasKey = false;
      _setStatus(VoiceStatus.needsKey);
      return;
    }
    error = null;
    if (turns.isNotEmpty) {
      await _saveCurrentConversation();
      _startBlankConversation();
    }
    _ready = false;
    liveThinking = false;
    _playbackEndsAt = DateTime.fromMillisecondsSinceEpoch(0);
    _liveEpoch++;
    _cancelledTools.clear();
    _seenTools.clear();
    _setStatus(VoiceStatus.connecting);
    // Que la voz sepa qué notas y lienzos existen antes de la primera frase.
    await tools.refresh();

    switch (await _audio.start(microphoneId: selectedMicrophoneId)) {
      case MicrophoneStart.ok:
        await _mic?.cancel();
        _mic = _audio.microphone.listen(_onMic);
      case MicrophoneStart.denied:
        _fail(
          'Permite el micrófono en Ajustes › KRAFT para hablar con el asistente.',
        );
        return;
      case MicrophoneStart.unsupported:
        _fail(
          'Este dispositivo no tiene el audio necesario. Aquí escribe al asistente o usa el dictado.',
        );
        return;
      case MicrophoneStart.failed:
        _fail(
          'No se pudo arrancar el micrófono. Cierra otras apps que lo estén usando, o prueba sin auriculares, y vuelve a pulsar.',
        );
        return;
    }
    try {
      final transport = await _connect(
        LiveProtocol.endpoint(
          key,
          extendedThinking: model.endsWith('-extended-thinking'),
        ),
      );
      _transport = transport;
      _messages = transport.messages.listen(
        _onMessage,
        onError: (Object e) => _fail('Se perdió la conexión: $e'),
        onDone: () {
          if (!active) return;
          final reason = transport.closeReason;
          _fail(
            reason == null || reason.isEmpty
                ? 'La conversación terminó.'
                : _explain(reason),
          );
        },
      );
      transport.send(
        LiveProtocol.setup(
          model: model,
          systemInstruction: _instructions(),
          tools: tools.definitions,
        ),
      );
    } on Object catch (e) {
      _fail('No se pudo conectar con Gemini: $e');
    }
  }

  Future<void> stop({bool persist = true}) async {
    _explanationEpoch++;
    _liveEpoch++;
    liveThinking = false;
    await _mic?.cancel();
    _mic = null;
    await _messages?.cancel();
    _messages = null;
    final transport = _transport;
    _transport = null;
    await transport?.close();
    await _audio.stop();
    await _speech.stop();
    _ready = false;
    liveThinking = false;
    _playbackEndsAt = DateTime.fromMillisecondsSinceEpoch(0);
    level = 0;
    if (status != VoiceStatus.error && status != VoiceStatus.needsKey) {
      _setStatus(VoiceStatus.idle);
    }
    if (persist) await _saveCurrentConversation();
  }

  Future<void> _playExplanation(
    GuidedExplanation explanation,
    int epoch,
  ) async {
    for (final step in explanation.steps) {
      if (epoch != _explanationEpoch) return;
      try {
        switch (explanation.target) {
          case ExplanationTarget.canvas:
            await tools.canvasBridge.focusItem(
              explanation.documentId,
              step.focus,
            );
          case ExplanationTarget.note:
            // La navegación necesita al menos un frame para adjuntar la nota al puente.
            for (var attempt = 0; attempt < 20; attempt++) {
              if (tools.noteBridge.live?.noteId == explanation.documentId) {
                break;
              }
              await Future<void>.delayed(const Duration(milliseconds: 50));
            }
            await tools.noteBridge.focusText(
              explanation.documentId,
              step.focus,
            );
        }
      } on Object {
        // Si un elemento cambió durante la explicación, continúa con el siguiente.
      }
      if (epoch != _explanationEpoch) return;
      await _speech.speak(step.narration);
      final words = step.narration
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .length;
      final milliseconds = (700 + words * 330).clamp(1400, 9000).toInt();
      await Future<void>.delayed(Duration(milliseconds: milliseconds));
    }
  }

  void toggleMute() {
    muted = !muted;
    notifyListeners();
  }

  /// Escribir en vez de hablar (útil en silencio o para corregir).
  void sendText(String text) {
    if (!_ready || text.trim().isEmpty) return;
    turns.add(VoiceTurn(user: true, text: text.trim()));
    _transport?.send(LiveProtocol.text(text.trim()));
    unawaited(_saveCurrentConversation());
    notifyListeners();
  }

  void _onMessage(Map<String, Object?> message) {
    for (final event in LiveProtocol.parse(message)) {
      switch (event) {
        case LiveReady():
          _ready = true;
          _mic ??= _audio.microphone.listen(_onMic);
          _setStatus(VoiceStatus.listening);
        case LiveAudio(:final pcm):
          _trackPlayback(pcm.lengthInBytes);
          _audio.play(pcm);
          if (status != VoiceStatus.speaking) _setStatus(VoiceStatus.speaking);
        case LiveTranscript(:final user, :final text):
          _appendTranscript(user: user, text: text);
        case LiveInterrupted():
          _audio.clear();
          _playbackEndsAt = DateTime.fromMillisecondsSinceEpoch(0);
          _setStatus(VoiceStatus.listening);
        case LiveTurnComplete():
          _setStatus(VoiceStatus.listening);
          unawaited(_saveCurrentConversation());
        case LiveToolCall(:final id, :final name, :final args):
          if (_seenTools.add(id)) {
            final epoch = _liveEpoch;
            _toolQueue = _toolQueue.then(
              (_) => _runTool(id, name, args, epoch),
            );
          }
        case LiveToolCancelled(:final ids):
          _cancelledTools.addAll(ids);
        case LiveInteractionStatus(:final inProgress):
          liveThinking = inProgress;
          if (!inProgress) {
            _setStatus(VoiceStatus.listening);
          } else {
            notifyListeners();
          }
        case LiveGoAway():
          error =
              'La sesión está por terminar (límite de Gemini). Vuelve a pulsar para seguir.';
          notifyListeners();
      }
    }
  }

  Future<void> _runTool(
    String id,
    String name,
    Map<String, Object?> args,
    int epoch,
  ) async {
    if (epoch != _liveEpoch || _cancelledTools.contains(id)) return;
    final transport = _transport;
    try {
      final (response, action) = await tools.call(name, args);
      if (epoch != _liveEpoch || _cancelledTools.contains(id)) return;
      if (action != null) {
        actions.insert(0, action);
        if (actions.length > 8) actions.removeLast();
        _onToolExecuted(name, action);
        notifyListeners();
      }
      transport?.send(
        LiveProtocol.toolResponse([(id: id, name: name, response: response)]),
      );
    } on Object {
      if (epoch != _liveEpoch || _cancelledTools.contains(id)) return;
      try {
        transport?.send(
          LiveProtocol.toolResponse([
            (
              id: id,
              name: name,
              response: {
                'error':
                    'No se pudo completar la operación. Lee el estado actual antes de reintentar para evitar duplicados.',
              },
            ),
          ]),
        );
      } on Object {
        // El transporte puede haberse cerrado mientras se ejecutaba la herramienta.
      }
    }
  }

  void _onMic(Uint8List pcm) {
    final now = DateTime.now();
    // Nivel para la animación, como mucho 15 veces por segundo.
    if (now.difference(_lastLevelAt).inMilliseconds >= 66) {
      _lastLevelAt = now;
      final samples = pcm.buffer.asByteData(
        pcm.offsetInBytes,
        pcm.lengthInBytes,
      );
      var sum = 0.0;
      final count = pcm.lengthInBytes ~/ 2;
      for (var i = 0; i < count; i++) {
        final v = samples.getInt16(i * 2, Endian.little) / 32768;
        sum += v * v;
      }
      level = count == 0 ? 0 : math.min(1, math.sqrt(sum / count) * 4);
      notifyListeners();
    }
    // No reenviar al modelo su propia voz. La cancelación de eco nativa ayuda,
    // pero altavoces, Bluetooth y rutas externas pueden dejar pasar suficiente
    // audio para que Gemini lo confunda con una nueva intervención del usuario.
    if (!_ready || muted || status != VoiceStatus.listening) return;
    if (now.isBefore(_playbackEndsAt.add(_playbackTail))) return;
    _transport?.send(LiveProtocol.audio(pcm));
  }

  void _trackPlayback(int byteCount) {
    // Gemini entrega PCM mono de 16 bits a 24 kHz. Los trozos se programan en
    // cola en el reproductor nativo, así que su duración también se acumula.
    final now = DateTime.now();
    final startsAt = _playbackEndsAt.isAfter(now) ? _playbackEndsAt : now;
    final microseconds =
        (byteCount * Duration.microsecondsPerSecond) ~/
        (_playbackSampleRate * 2);
    _playbackEndsAt = startsAt.add(Duration(microseconds: microseconds));
  }

  void _appendTranscript({required bool user, required String text}) {
    if (text.isEmpty) return;
    final last = turns.isEmpty ? null : turns.last;
    if (last != null && last.user == user) {
      last.text += text;
    } else {
      turns.add(VoiceTurn(user: user, text: text.trimLeft()));
      if (turns.length > 30) turns.removeAt(0);
    }
    notifyListeners();
  }

  Future<void> _loadConversations() async {
    final archive = ConversationArchive.decode(
      await _settings.get(chatHistoryKey),
    );
    _conversations = List.of(archive.threads);
    final active = _conversations
        .where((thread) => thread.id == archive.activeId)
        .firstOrNull;
    if (active == null) {
      _startBlankConversation();
      return;
    }
    engine = engines.firstWhere(
      (candidate) => candidate.id == active.engineId,
      orElse: () => engine,
    );
    if (engine.id == 'gemini' && active.modelId.isNotEmpty) {
      _applyChatModel = ChatModel.from(active.modelId);
    }
    _activeConversationId = active.id;
    turns.addAll([
      for (final entry in active.entries)
        VoiceTurn(user: entry.user, text: entry.text),
    ]);
    _restoreEngineContext();
  }

  void _startBlankConversation() {
    turns.clear();
    actions.clear();
    error = null;
    engine.reset();
    _activeConversationId =
        'chat-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
  }

  void _restoreEngineContext() {
    engine.reset();
    if (engine case final RestorableAssistantEngine restorable) {
      restorable.restore([
        for (final turn in turns)
          AssistantMessage(user: turn.user, text: turn.text),
      ]);
    }
  }

  Future<void> _saveCurrentConversation() async {
    final id = _activeConversationId;
    if (id == null) return;
    final now = DateTime.now();
    final entries = [
      for (final turn in turns.where((turn) => turn.text.trim().isNotEmpty))
        ConversationEntry(user: turn.user, text: turn.text.trim()),
    ];
    final firstUser = entries.where((entry) => entry.user).firstOrNull?.text;
    final title = _conversationTitle(firstUser);
    final thread = ConversationThread(
      id: id,
      title: title,
      engineId: engine.id,
      modelId: engine.id == 'gemini' ? chatModel.id : engine.id,
      updatedAt: now,
      entries: entries.length <= 60
          ? entries
          : entries.sublist(entries.length - 60),
    );
    final index = _conversations.indexWhere((item) => item.id == id);
    if (index < 0) {
      _conversations.add(thread);
    } else {
      _conversations[index] = thread;
    }
    _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (_conversations.length > _historyLimit) {
      _conversations = _conversations.sublist(0, _historyLimit);
    }
    await _writeArchive();
  }

  Future<void> _writeArchive() => _settings.set(
    chatHistoryKey,
    ConversationArchive(
      activeId: _activeConversationId,
      threads: _conversations,
    ).encode(),
  );

  static String _conversationTitle(String? text) {
    final clean = (text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return 'Conversación nueva';
    if (clean.length <= 42) return clean;
    return '${clean.substring(0, 39).trimRight()}…';
  }

  String _instructions() =>
      '''
Eres el asistente de voz de KRAFT. Habla español con frases naturales y breves.
Mientras trabajas puedes dar una actualización corta, pero no leas listas largas en voz alta.
Usa create_note/append_to_note para notas, create_reminder o save_task para tareas,
save_task con requirement_id para casillas de un requerimiento, complete_reminder o save_task con done=true para marcarlas hechas,
create_canvas/create_diagram para diagramas nuevos y sketch_note con embedded=true para bocetos en notas.
Si no hay lienzo y lo necesitas, créalo tú; nunca pidas al usuario un canvas_id.
Para explicar, lee primero y señala cada paso con focus_canvas_item (id real de get_canvas)
o focus_note_text (frase exacta de read_note); explica ese paso y continúa.
${CreationPolicy.instructions}
${tools.context()}
''';

  String _explain(String reason) {
    final lower = reason.toLowerCase();
    if (lower.contains('api key') ||
        lower.contains('permission') ||
        lower.contains('unauth')) {
      return 'Gemini rechazó la API key. Revísala en el panel del asistente.';
    }
    return 'Gemini cerró la conversación: $reason';
  }

  void _fail(String message) {
    error = assistantVisibleText(message);
    _setStatus(VoiceStatus.error);
    unawaited(stop());
  }

  void _setStatus(VoiceStatus next) {
    status = next;
    notifyListeners();
  }

  bool _disposed = false;

  /// `stop()` termina de forma asíncrona: tras `dispose` ya no avisa a nadie.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _creationEventsController.close();
    // El contenedor puede cerrar Drift inmediatamente después. Todo turno ya se
    // guarda al terminar; aquí sólo liberamos audio/transporte sin volver a escribir.
    unawaited(stop(persist: false));
    super.dispose();
  }
}
