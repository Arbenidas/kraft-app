import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app/router.dart';
import '../../theme/kraft_colors.dart';
import '../../theme/kraft_motion.dart';
import '../../theme/kraft_tokens.dart';
import '../../theme/kraft_typography.dart';
import '../ai/ai_providers.dart';
import '../../widgets/ai_creation_toast.dart';
import 'assistant_markdown.dart';
import 'dictation.dart';
import 'assistant_engine.dart';
import 'gemini_models.dart';
import 'voice_controller.dart';

/// Botón de micrófono en toda la app y panel de conversación con el asistente.
/// Va por encima del navegador (ver `KraftApp`), por eso trae su propio `Overlay` para los campos de texto.
class VoiceOverlay extends StatefulWidget {
  const VoiceOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<VoiceOverlay> createState() => _VoiceOverlayState();
}

class _VoiceOverlayState extends State<VoiceOverlay> {
  late final _entry = OverlayEntry(builder: (_) => const _VoiceLayer());

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Stack(
      children: [
        widget.child,
        Positioned.fill(child: Overlay(initialEntries: [_entry])),
      ],
    );
  }
}

class _VoiceLayer extends ConsumerStatefulWidget {
  const _VoiceLayer();

  @override
  ConsumerState<_VoiceLayer> createState() => _VoiceLayerState();
}

class _VoiceLayerState extends ConsumerState<_VoiceLayer> {
  bool _panelOpen = false;
  bool _panelExpanded = false;
  double _panelWidth = 380;
  double _panelHeight = 560;
  Offset? _panelPosition;

  /// Posición vertical del botón (0 arriba, 1 abajo); se puede arrastrar por el borde derecho.
  double _y = 0.62;

  static const buttonSize = 60.0;

  StreamSubscription<AiCreationEvent>? _creationSub;

  @override
  void initState() {
    super.initState();
    _creationSub = ref.read(voiceControllerProvider).creationEvents.listen((event) {
      if (mounted) {
        AiCreationToast.show(
          context,
          title: event.title,
          subtitle: event.subtitle,
          icon: event.icon,
          actionLabel: event.actionLabel,
          onAction: event.onAction,
        );
      }
    });
  }

  @override
  void dispose() {
    _creationSub?.cancel();
    super.dispose();
  }

  Future<void> _onButton(VoiceController voice) async {
    HapticFeedback.mediumImpact();
    setState(() => _panelOpen = true);
    // Sin API key (o sin audio nativo, como en el Mac) no se arranca la voz:
    // el panel queda listo para escribir o dictar.
    if (!voice.active &&
        !voice.usesDictation &&
        voice.liveAudio &&
        (voice.hasKey ?? false)) {
      await voice.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final voice = ref.watch(voiceControllerProvider);
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final top =
        (padding.top + 70 + (size.height - padding.vertical - 70 - 160) * _y)
            .clamp(padding.top + 70, size.height - 160);
    // Con el teclado abierto (escribiendo una nota o una tarea) el botón no estorba, salvo en plena conversación.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final hidden = keyboard && !voice.active && !_panelOpen;
    final narrow = size.width < 620;
    final minPanelWidth = math.min(320.0, math.max(240.0, size.width - 24));
    final minPanelHeight = math.min(360.0, math.max(280.0, size.height - 24));
    final expandedWidth = math.max(minPanelWidth, size.width - 24);
    final expandedHeight = math.max(
      minPanelHeight,
      size.height - padding.vertical - 24,
    );
    final maxPanelWidth = math.max(
      minPanelWidth,
      math.min(760, size.width - buttonSize - KraftSpace.xl * 3),
    );
    final maxPanelHeight = math.max(
      minPanelHeight,
      size.height - padding.vertical - 24,
    );
    final isExpanded = _panelExpanded || narrow;
    final panelWidth = isExpanded
        ? expandedWidth
        : _panelWidth.clamp(minPanelWidth, maxPanelWidth).toDouble();
    final panelHeight = isExpanded
        ? expandedHeight
        : _panelHeight.clamp(minPanelHeight, maxPanelHeight).toDouble();
    final defaultPanelLeft =
        size.width - panelWidth - KraftSpace.md - buttonSize - KraftSpace.sm;
    final defaultPanelTop = math.max(
      padding.top + 70,
      math.min(top - panelHeight * .44, size.height - panelHeight - 12),
    );
    final panelLeft = (_panelPosition?.dx ?? defaultPanelLeft)
        .clamp(12.0, math.max(12.0, size.width - panelWidth - 12))
        .toDouble();
    final panelTop = (_panelPosition?.dy ?? defaultPanelTop)
        .clamp(
          padding.top + 8,
          math.max(padding.top + 8, size.height - panelHeight - 12),
        )
        .toDouble();

    return Stack(
      children: [
        if (_panelOpen)
          Positioned(
            left: isExpanded ? 12 : panelLeft,
            top: isExpanded ? padding.top + 12 : panelTop,
            child: _VoicePanel(
              voice: voice,
              dictation: ref.watch(dictationProvider),
              width: panelWidth,
              height: panelHeight,
              expanded: isExpanded,
              canResize: !narrow,
              onResize: (delta) => setState(() {
                _panelExpanded = false;
                _panelWidth = (_panelWidth - delta.dx)
                    .clamp(minPanelWidth, maxPanelWidth)
                    .toDouble();
                _panelHeight = (_panelHeight + delta.dy)
                    .clamp(minPanelHeight, maxPanelHeight)
                    .toDouble();
              }),
              onMove: isExpanded
                  ? null
                  : (delta) => setState(() {
                      final current =
                          _panelPosition ??
                          Offset(defaultPanelLeft, defaultPanelTop);
                      _panelPosition = Offset(
                        (current.dx + delta.dx)
                            .clamp(
                              12.0,
                              math.max(12.0, size.width - panelWidth - 12),
                            )
                            .toDouble(),
                        (current.dy + delta.dy)
                            .clamp(
                              padding.top + 8,
                              math.max(
                                padding.top + 8,
                                size.height - panelHeight - 12,
                              ),
                            )
                            .toDouble(),
                      );
                    }),
              onToggleExpanded: narrow
                  ? null
                  : () => setState(() => _panelExpanded = !_panelExpanded),
              onClose: () => setState(() => _panelOpen = false),
              openSettings: () =>
                  ref.read(routerProvider).push(Routes.settings),
            ),
          ),
        Positioned(
          right: KraftSpace.md,
          top: top,
          child: AnimatedScale(
            scale: hidden ? 0 : 1,
            duration: KraftMotion.of(context, KraftMotion.fast),
            child: GestureDetector(
              onVerticalDragUpdate: (d) => setState(() {
                final usable = size.height - padding.vertical - 70 - 160;
                _y = (_y + d.delta.dy / usable).clamp(0.0, 1.0);
              }),
              child: _MicButton(voice: voice, onTap: () => _onButton(voice)),
            ),
          ),
        ),
      ],
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({required this.voice, required this.onTap});

  final VoiceController voice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final active = voice.active;
    final speaking = voice.status == VoiceStatus.speaking;
    return Semantics(
      button: true,
      label: active ? 'Asistente de voz activo' : 'Hablar con KRAFT',
      child: Tooltip(
        message: active ? 'Asistente de voz activo' : 'Hablar con KRAFT',
        child: GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: _VoiceLayerState.buttonSize + 24,
            height: _VoiceLayerState.buttonSize + 24,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Aro que respira con la voz.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 90),
                  width:
                      _VoiceLayerState.buttonSize +
                      (active ? 8 + 16 * (speaking ? 0.6 : voice.level) : 0),
                  height:
                      _VoiceLayerState.buttonSize +
                      (active ? 8 + 16 * (speaking ? 0.6 : voice.level) : 0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        (speaking
                                ? KraftColors.secondaryContainer
                                : KraftColors.primaryContainer)
                            .withValues(alpha: active ? 0.55 : 0),
                  ),
                ),
                AnimatedContainer(
                  duration: KraftMotion.of(context, KraftMotion.base),
                  width: _VoiceLayerState.buttonSize,
                  height: _VoiceLayerState.buttonSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active
                        ? KraftColors.inkFill
                        : KraftColors.primaryContainer,
                    border: KraftBorder.ink(),
                    boxShadow: KraftShadow.hard(3),
                  ),
                  child: voice.status == VoiceStatus.connecting
                      ? Padding(
                          padding: EdgeInsets.all(18),
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: KraftColors.onInkFill,
                          ),
                        )
                      : Icon(
                          speaking
                              ? Symbols.graphic_eq
                              : (voice.muted && active
                                    ? Symbols.mic_off
                                    : Symbols.mic),
                          size: 28,
                          color: active
                              ? KraftColors.onInkFill
                              : KraftColors.ink,
                          fill: 1,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VoicePanel extends StatelessWidget {
  const _VoicePanel({
    required this.voice,
    required this.dictation,
    required this.width,
    required this.height,
    required this.expanded,
    required this.canResize,
    required this.onResize,
    required this.onMove,
    required this.onToggleExpanded,
    required this.onClose,
    required this.openSettings,
  });

  final VoiceController voice;
  final DictationController dictation;
  final double width;
  final double height;
  final bool expanded;
  final bool canResize;
  final ValueChanged<Offset> onResize;
  final ValueChanged<Offset>? onMove;
  final VoidCallback? onToggleExpanded;
  final VoidCallback onClose;
  final VoidCallback openSettings;

  String get _status => switch (voice.status) {
    VoiceStatus.idle =>
      voice.liveAudio ? 'Listo para hablar' : 'Listo para escribir',
    VoiceStatus.needsKey => 'Falta la API key',
    VoiceStatus.connecting => 'Conectando…',
    VoiceStatus.listening =>
      voice.liveThinking
          ? 'Pensando y revisando…'
          : voice.muted
          ? 'Micrófono en silencio'
          : 'Te escucho',
    VoiceStatus.speaking => 'Hablando',
    VoiceStatus.error => 'No se pudo continuar',
  };

  Future<void> _historyAction(String value) async {
    if (value == 'new') {
      await voice.newConversation();
      return;
    }
    if (value == 'clear') {
      await voice.clearCurrentConversation();
      return;
    }
    if (value.startsWith('chat:')) {
      await voice.openConversation(value.substring(5));
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    // El chat local no necesita API key; sólo se pide para Gemini (chat o voz).
    final needsKey =
        (voice.status == VoiceStatus.needsKey || voice.hasKey == false) &&
        voice.engine.id == 'gemini';
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: KraftColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(KraftRadius.xl),
          border: KraftBorder.ink(),
          boxShadow: KraftShadow.hard(5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MouseRegion(
                  cursor: onMove == null
                      ? MouseCursor.defer
                      : SystemMouseCursors.move,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                    color: voice.active
                        ? KraftColors.ink
                        : KraftColors.primaryContainer,
                    child: Row(
                      children: [
                        Icon(
                          Symbols.auto_awesome,
                          size: 18,
                          color: voice.active
                              ? KraftColors.primaryContainer
                              : KraftColors.ink,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanUpdate: onMove == null
                                ? null
                                : (details) => onMove!(details.delta),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'HABLA CON KRAFT',
                                  style: KraftText.techBadge.copyWith(
                                    color: voice.active
                                        ? KraftColors.surface
                                        : KraftColors.ink,
                                    letterSpacing: 1,
                                  ),
                                ),
                                Text(
                                  _status,
                                  style: KraftText.labelCode.copyWith(
                                    color: voice.active
                                        ? KraftColors.primaryContainer
                                        : KraftColors.ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Nueva conversación',
                          onPressed: voice.active || voice.thinking
                              ? null
                              : voice.newConversation,
                          icon: Icon(
                            Symbols.add_comment,
                            size: 19,
                            color: voice.active
                                ? KraftColors.primaryContainer
                                : KraftColors.ink,
                          ),
                        ),
                        _HistoryMenu(
                          voice: voice,
                          enabled: !voice.active && !voice.thinking,
                          onAction: _historyAction,
                          color: voice.active
                              ? KraftColors.primaryContainer
                              : KraftColors.ink,
                        ),
                        if (onToggleExpanded != null)
                          IconButton(
                            tooltip: expanded
                                ? 'Restaurar tamaño'
                                : 'Ampliar chat',
                            onPressed: onToggleExpanded,
                            icon: Icon(
                              expanded
                                  ? Symbols.close_fullscreen
                                  : Symbols.open_in_full,
                              size: 18,
                              color: voice.active
                                  ? KraftColors.primaryContainer
                                  : KraftColors.ink,
                            ),
                          ),
                        IconButton(
                          tooltip: 'Cerrar panel',
                          onPressed: onClose,
                          icon: Icon(
                            Symbols.close,
                            size: 20,
                            color: voice.active
                                ? KraftColors.surface
                                : KraftColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _EnginePicker(voice: voice, openSettings: openSettings),
                if (needsKey)
                  Flexible(
                    child: SingleChildScrollView(child: _KeyForm(voice: voice)),
                  )
                else
                  Flexible(
                    child: _Conversation(
                      voice: voice,
                      dictation: dictation,
                      openSettings: openSettings,
                    ),
                  ),
              ],
            ),
            if (canResize && !expanded)
              Positioned(
                left: 0,
                bottom: 0,
                child: Tooltip(
                  message: 'Arrastra esta esquina para cambiar el tamaño',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeUpLeftDownRight,
                    child: GestureDetector(
                      onPanUpdate: (details) => onResize(details.delta),
                      child: Semantics(
                        label: 'Redimensionar chat',
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Align(
                            alignment: Alignment.bottomLeft,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                Symbols.open_in_full,
                                size: 18,
                                color: KraftColors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Menú anclado al propio `Overlay` del chat. A diferencia de
/// `PopupMenuButton`, no intenta encontrar un Navigator por encima del panel.
class _HistoryMenu extends StatelessWidget {
  const _HistoryMenu({
    required this.voice,
    required this.enabled,
    required this.onAction,
    required this.color,
  });

  final VoiceController voice;
  final bool enabled;
  final Future<void> Function(String) onAction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final saved = voice.conversations
        .where((thread) => thread.entries.isNotEmpty)
        .take(8)
        .toList();
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Symbols.add_comment),
          onPressed: enabled ? () => unawaited(onAction('new')) : null,
          child: const Text('Nueva conversación'),
        ),
        if (saved.isNotEmpty) const Divider(height: 1),
        for (final thread in saved)
          MenuItemButton(
            leadingIcon: Icon(
              thread.id == voice.activeConversationId
                  ? Symbols.check_circle
                  : Symbols.chat_bubble,
            ),
            onPressed: enabled
                ? () => unawaited(onAction('chat:${thread.id}'))
                : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    thread.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    thread.engineId == 'gemini'
                        ? ChatModel.from(thread.modelId).label
                        : 'Otro proveedor',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KraftText.bodySm.copyWith(
                      color: KraftColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        const Divider(height: 1),
        MenuItemButton(
          leadingIcon: const Icon(Symbols.delete_sweep),
          onPressed: enabled ? () => unawaited(onAction('clear')) : null,
          child: const Text('Limpiar conversación'),
        ),
        SubmenuButton(
          leadingIcon: const Icon(Symbols.delete_forever),
          menuChildren: [
            const MenuItemButton(
              onPressed: null,
              child: Text('Esta acción no se puede deshacer.'),
            ),
            MenuItemButton(
              leadingIcon: const Icon(Symbols.delete_forever),
              onPressed: enabled
                  ? () => unawaited(voice.clearConversationHistory())
                  : null,
              child: const Text('Sí, borrar todo'),
            ),
          ],
          child: const Text('Borrar todo el historial…'),
        ),
      ],
      builder: (context, controller, child) => IconButton(
        tooltip: 'Historial de conversaciones',
        onPressed: enabled
            ? () => controller.isOpen ? controller.close() : controller.open()
            : null,
        icon: Icon(Symbols.history, size: 20, color: color),
      ),
    );
  }
}

/// Con quién se habla, sin salir del panel.
class _EnginePicker extends StatelessWidget {
  const _EnginePicker({required this.voice, required this.openSettings});

  final VoiceController voice;
  final VoidCallback openSettings;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final engines = [
      for (final engine in voice.engines)
        GestureDetector(
          onTap: () => voice.setEngine(engine),
          child: AnimatedContainer(
            duration: KraftMotion.of(context, KraftMotion.fast),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: engine == voice.engine
                  ? KraftColors.primaryContainer
                  : KraftColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(KraftRadius.sm),
              border: Border.all(color: KraftColors.ink, width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Symbols.cloud, size: 14),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    engine.label,
                    overflow: TextOverflow.ellipsis,
                    style: KraftText.labelCode.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
    final configure = Tooltip(
      message: 'Configurar asistente',
      child: TextButton.icon(
        onPressed: openSettings,
        icon: const Icon(Symbols.tune, size: 16),
        label: const Text('Configurar'),
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(
        KraftSpace.md,
        KraftSpace.sm,
        KraftSpace.sm,
        KraftSpace.sm,
      ),
      decoration: BoxDecoration(
        color: KraftColors.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: KraftColors.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final choices = Wrap(spacing: 6, runSpacing: 6, children: engines);
          if (constraints.maxWidth < 480) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                choices,
                Align(alignment: Alignment.centerRight, child: configure),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: choices),
              configure,
            ],
          );
        },
      ),
    );
  }
}

class _Conversation extends StatefulWidget {
  const _Conversation({
    required this.voice,
    required this.dictation,
    required this.openSettings,
  });

  final VoiceController voice;
  final DictationController dictation;
  final VoidCallback openSettings;

  @override
  State<_Conversation> createState() => _ConversationState();
}

class _ConversationState extends State<_Conversation> {
  final _input = TextEditingController();

  /// Lo que ya estaba escrito cuando se empezó a dictar.
  String _typed = '';

  @override
  void initState() {
    super.initState();
    widget.dictation.addListener(_onDictated);
  }

  @override
  void dispose() {
    widget.dictation.removeListener(_onDictated);
    _input.dispose();
    super.dispose();
  }

  /// Lo dictado se va escribiendo en el campo, detrás de lo que ya había.
  void _onDictated() {
    final spoken = widget.dictation.text;
    if (!widget.dictation.listening && spoken.isEmpty) return;
    final joined = _typed.isEmpty ? spoken : '${_typed.trimRight()} $spoken';
    _input.value = TextEditingValue(
      text: joined,
      selection: TextSelection.collapsed(offset: joined.length),
    );
    setState(() {});
    if (widget.dictation.readyToSend && !widget.voice.thinking) {
      _send();
    }
  }

  Future<void> _dictate({bool sendWhenQuiet = false}) async {
    HapticFeedback.selectionClick();
    if (widget.dictation.listening) {
      await widget.dictation.stop();
    } else {
      _typed = _input.text;
      await widget.voice.stopSpeaking();
      await widget.dictation.start(sendWhenQuiet: sendWhenQuiet);
    }
    if (mounted) setState(() {});
  }

  /// Modo económico: "Hablar" dicta con el motor del iPad y, al callar, envía solo.
  /// Nunca abre la Live API, que es lo que cobra el audio por minuto.
  Future<void> _talkCheap() async {
    if (widget.dictation.listening) {
      await widget.dictation.stop();
      if (mounted) setState(() {});
      _send();
    } else {
      await _dictate(sendWhenQuiet: true);
    }
  }

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    if (widget.dictation.listening) unawaited(widget.dictation.stop());
    _input.clear();
    _typed = '';
    setState(() {});
    widget.voice.ask(text);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final voice = widget.voice;
    final turns = voice.turns.reversed.take(8).toList().reversed.toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: ListView(
            shrinkWrap: true,
            reverse: true,
            padding: const EdgeInsets.all(KraftSpace.md),
            children: [
              if (voice.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: KraftSpace.sm),
                  child: Text(
                    assistantVisibleText(voice.error!),
                    style: KraftText.bodySm.copyWith(
                      color: KraftColors.error,
                      fontFamilyFallback: const [
                        'SF Pro Text',
                        'Helvetica Neue',
                        'sans-serif',
                      ],
                    ),
                  ),
                ),
              for (final action in voice.actions.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: KraftColors.secondaryContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(KraftRadius.md),
                      side: BorderSide(color: KraftColors.ink, width: 1.5),
                    ),
                    child: InkWell(
                      onTap: action.open,
                      borderRadius: BorderRadius.circular(KraftRadius.md),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            const Icon(Symbols.check_circle, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                action.label,
                                style: KraftText.bodySm.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (action.open != null)
                              const Icon(Symbols.north_east, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              for (final turn in turns.reversed)
                Align(
                  alignment: turn.user
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    constraints: BoxConstraints(
                      maxWidth: turn.user ? 290 : 520,
                    ),
                    decoration: BoxDecoration(
                      color: turn.user
                          ? KraftColors.primaryContainer
                          : KraftColors.surfaceContainer,
                      borderRadius: BorderRadius.circular(KraftRadius.md),
                    ),
                    child: turn.user
                        ? Text(
                            turn.text.trim(),
                            style: KraftText.bodySm.copyWith(
                              color: KraftColors.onSurface,
                            ),
                          )
                        : AssistantMarkdown(text: turn.text.trim()),
                  ),
                ),
              if (turns.isEmpty && voice.error == null)
                Text(
                  switch ((voice.active, voice.liveAudio)) {
                    (true, _) =>
                      'Cuéntame una idea, pídeme un recordatorio o un diagrama.',
                    (false, true) =>
                      'Pulsa el micrófono y cuéntame una idea: la ordeno en una nota, creo recordatorios o dibujo un diagrama.',
                    (false, false) =>
                      'Escríbeme o dicta una idea: la ordeno en una nota, creo recordatorios o dibujo un diagrama.',
                  },
                  style: KraftText.bodySm.copyWith(
                    color: KraftColors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(
            KraftSpace.md,
            KraftSpace.sm,
            KraftSpace.md,
            KraftSpace.md,
          ),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: KraftColors.outlineVariant)),
          ),
          child: Column(
            children: [
              if (voice.thinking ||
                  voice.liveThinking ||
                  voice.thought.isNotEmpty ||
                  voice.tokensPerSecond != null) ...[
                _ThinkingStatus(voice: voice),
                const SizedBox(height: KraftSpace.sm),
              ],
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 3,
                      textInputAction: TextInputAction.send,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _send(),
                      style: KraftText.bodySm,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: voice.active
                            ? 'Escribe al asistente…'
                            : 'Escribe a ${voice.engine.label}…',
                        hintStyle: KraftText.bodySm.copyWith(
                          color: KraftColors.outline,
                        ),
                        filled: true,
                        fillColor: KraftColors.surfaceContainer,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(KraftRadius.md),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  // Dictado en el propio aparato: hablar sin encender la conversación con Gemini.
                  if (widget.dictation.supported && !voice.active)
                    IconButton(
                      tooltip: widget.dictation.listening
                          ? 'Parar el dictado'
                          : 'Dictar',
                      onPressed: _dictate,
                      isSelected: widget.dictation.listening,
                      style: IconButton.styleFrom(
                        backgroundColor: widget.dictation.listening
                            ? KraftColors.primaryContainer
                            : null,
                      ),
                      icon: Icon(
                        widget.dictation.listening
                            ? Symbols.graphic_eq
                            : Symbols.keyboard_voice,
                        size: 20,
                      ),
                    ),
                  IconButton(
                    tooltip: 'Enviar',
                    onPressed: _input.text.trim().isEmpty || voice.thinking
                        ? null
                        : _send,
                    icon: const Icon(Symbols.send, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: KraftSpace.sm),
              Row(
                children: [
                  if (voice.active)
                    IconButton(
                      tooltip: voice.muted
                          ? 'Activar micrófono'
                          : 'Silenciar micrófono',
                      onPressed: voice.toggleMute,
                      icon: Icon(voice.muted ? Symbols.mic_off : Symbols.mic),
                    ),
                  if (!voice.active)
                    IconButton(
                      tooltip: voice.speakReplies
                          ? 'Silenciar respuestas habladas'
                          : 'Leer respuestas en voz alta',
                      onPressed: () =>
                          voice.setSpeakReplies(!voice.speakReplies),
                      isSelected: voice.speakReplies,
                      icon: Icon(
                        voice.speakReplies
                            ? Symbols.volume_up
                            : Symbols.volume_off,
                        size: 20,
                      ),
                    ),
                  IconButton(
                    tooltip: 'Ajustes del asistente',
                    // El panel vive por encima del navegador: hay que pedirle al router directamente.
                    onPressed: () => widget.openSettings(),
                    icon: const Icon(Symbols.settings, size: 20),
                  ),
                  const Spacer(),
                  // Donde no hay audio nativo (el Mac) no se ofrece hablar: se escribe o se dicta.
                  if (voice.liveAudio)
                    () {
                      final dictating =
                          voice.usesDictation && widget.dictation.listening;
                      final busy = voice.active || dictating;
                      return FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: busy
                              ? KraftColors.error
                              : KraftColors.inkFill,
                          foregroundColor: busy
                              ? KraftColors.onError
                              : KraftColors.onInkFill,
                        ),
                        onPressed: voice.usesDictation
                            ? _talkCheap
                            : (voice.active ? voice.stop : voice.start),
                        icon: Icon(busy ? Symbols.stop : Symbols.mic, size: 18),
                        label: Text(
                          busy ? (dictating ? 'Enviar' : 'Terminar') : 'Hablar',
                        ),
                      );
                    }(),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _KeyForm extends StatefulWidget {
  const _KeyForm({required this.voice});

  final VoiceController voice;

  @override
  State<_KeyForm> createState() => _KeyFormState();
}

class _KeyFormState extends State<_KeyForm> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.voice.saveKey(_controller.text);
    await widget.voice.start();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Padding(
      padding: const EdgeInsets.all(KraftSpace.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Para hablar con Gemini Live necesitas una API key de Google AI Studio '
            '(aistudio.google.com/apikey). Se guarda sólo en el llavero de este iPad.',
            style: KraftText.bodySm,
          ),
          const SizedBox(height: KraftSpace.md),
          TextField(
            controller: _controller,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            style: KraftText.labelCode,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: 'API key de Gemini',
              filled: true,
              fillColor: KraftColors.surfaceContainer,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KraftRadius.sm),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: KraftSpace.md),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: KraftColors.inkFill,
              foregroundColor: KraftColors.onInkFill,
            ),
            onPressed: _controller.text.trim().isEmpty ? null : _save,
            icon: const Icon(Symbols.key, size: 18),
            label: const Text('Guardar y hablar'),
          ),
        ],
      ),
    );
  }
}

class _ThinkingStatus extends StatelessWidget {
  const _ThinkingStatus({required this.voice});

  final VoiceController voice;

  @override
  Widget build(BuildContext context) {
    final speed = voice.tokensPerSecond;
    final tokens = voice.generatedTokens;
    final waiting = voice.thinking || voice.liveThinking;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 140),
        child: SingleChildScrollView(
          reverse: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (voice.thought.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    voice.thought.trim(),
                    style: KraftText.bodySm.copyWith(
                      color: KraftColors.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              Row(
                children: [
                  if (waiting) ...[
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      waiting
                          ? '${voice.engine.label} está pensando…'
                          : voice.engine.label,
                      style: KraftText.labelCode.copyWith(fontSize: 11),
                    ),
                  ),
                  if (speed != null)
                    Text(
                      [
                        if (tokens != null) '$tokens tok',
                        '${speed.toStringAsFixed(1)} tok/s',
                      ].join(' · '),
                      style: KraftText.labelCode.copyWith(
                        fontSize: 11,
                        color: KraftColors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
