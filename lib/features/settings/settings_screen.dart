import 'provider_credentials.dart';
import '../voice/compatible_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app/router.dart';
import '../../data/providers.dart';
import '../../theme/kraft_colors.dart';
import '../../theme/kraft_motion.dart';
import '../../theme/kraft_tokens.dart';
import '../../theme/kraft_typography.dart';
import '../../widgets/kraft_toast.dart';
import '../../widgets/neo_box.dart';
import '../ai/ai_connection_sheet.dart';
import '../ai/ai_providers.dart';
import '../voice/gemini_models.dart';
import '../voice/ollama_chat.dart';
import '../notes/note_ai_sheet.dart';

final _webDiscoveryProvider = FutureProvider<bool>(
  (ref) async =>
      await ref.read(settingsRepositoryProvider).get(webDiscoveryEnabledKey) ==
      'true',
);

/// Ajustes: asistente (Gemini o Gemma en el iPad), lienzo, recordatorios y servidor MCP.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Scaffold(
      backgroundColor: KraftColors.surface,
      appBar: AppBar(
        backgroundColor: KraftColors.surface,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Volver',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(Routes.home),
          icon: const Icon(Symbols.arrow_back),
        ),
        title: Text(
          'Ajustes',
          style: KraftText.headlineSm.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          KraftSpace.lg,
          0,
          KraftSpace.lg,
          KraftSpace.xl * 2,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: const [
                  _SettingsIntro(),
                  SizedBox(height: KraftSpace.lg),
                  _AppearanceSection(),
                  SizedBox(height: KraftSpace.lg),
                  _AssistantSection(),
                  SizedBox(height: KraftSpace.lg),
                  _DictationSection(),
                  SizedBox(height: KraftSpace.lg),
                  _AppSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Resume el punto de partida para que los ajustes del asistente no parezcan
/// una lista de integraciones sin orden.
class _SettingsIntro extends ConsumerWidget {
  const _SettingsIntro();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voice = ref.watch(voiceControllerProvider);
    final ready = voice.engine.id != 'gemini' || (voice.hasKey ?? false);
    return NeoBox(
      color: KraftColors.primaryContainer,
      borderWidth: 1.5,
      shadow: 2,
      radius: KraftRadius.lg,
      padding: const EdgeInsets.all(KraftSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Symbols.auto_awesome, size: 24),
          const SizedBox(width: KraftSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chat activo: ${voice.engine.label}',
                  style: KraftText.headlineSm.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  ready
                      ? 'Empieza por elegir el motor. Los modelos y claves de cada integración quedan debajo, en su propia sección.'
                      : 'Gemini necesita una API key para responder. Agrégala en “Asistente” y luego podrás usar el chat.',
                  style: KraftText.bodySm.copyWith(
                    color: KraftColors.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.children,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return NeoBox(
      shadow: 3,
      radius: KraftRadius.lg,
      padding: const EdgeInsets.all(KraftSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 22),
              const SizedBox(width: KraftSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: KraftText.headlineSm.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: KraftText.bodySm.copyWith(
                        color: KraftColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: KraftSpace.md),
          ...children,
        ],
      ),
    );
  }
}

class _AssistantSection extends ConsumerStatefulWidget {
  const _AssistantSection();

  @override
  ConsumerState<_AssistantSection> createState() => _AssistantSectionState();
}

class _AssistantSectionState extends ConsumerState<_AssistantSection> {
  final _key = TextEditingController();

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final voice = ref.watch(voiceControllerProvider);
    final ollama = voice.engines.whereType<OllamaChatEngine>().firstOrNull;
    return _Section(
      title: 'Asistente',
      subtitle: 'Con quién hablas y escribes',
      icon: Symbols.auto_awesome,
      children: [
        Text(
          '1 · ELIGE EL MOTOR DEL CHAT',
          style: KraftText.techBadge.copyWith(
            color: KraftColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Esto cambia quién responde en el panel. Puedes volver a cambiarlo sin perder tus integraciones.',
          style: KraftText.bodySm.copyWith(color: KraftColors.onSurfaceVariant),
        ),
        const SizedBox(height: KraftSpace.sm),
        Wrap(
          spacing: KraftSpace.sm,
          runSpacing: KraftSpace.sm,
          children: [
            for (final engine in voice.engines)
              NeoBox(
                onTap: () => voice.setEngine(engine),
                color: engine == voice.engine
                    ? KraftColors.primaryContainer
                    : KraftColors.surfaceContainerLowest,
                borderWidth: 1.5,
                shadow: engine == voice.engine ? 2 : 0,
                radius: KraftRadius.sm,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Symbols.cloud,
                      size: 16,
                      color: engine == voice.engine
                          ? KraftColors.onPrimaryContainer
                          : KraftColors.onSurface,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      engine.label,
                      style: KraftText.labelCode.copyWith(
                        fontWeight: FontWeight.w700,
                        color: engine == voice.engine
                            ? KraftColors.onPrimaryContainer
                            : KraftColors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: KraftSpace.sm),
        Text(
          'El chat escrito usa el motor elegido. OpenRouter ofrece modelos gratuitos y Ollama usa los modelos que tengas instalados en tu Mac.',
          style: KraftText.bodySm.copyWith(color: KraftColors.onSurfaceVariant),
        ),
        const SizedBox(height: KraftSpace.md),
        Text(
          '2 · MODELOS Y CONEXIONES',
          style: KraftText.techBadge.copyWith(
            color: KraftColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Abre sólo el proveedor que quieras configurar. Las claves se guardan en el llavero del dispositivo.',
          style: KraftText.bodySm.copyWith(color: KraftColors.onSurfaceVariant),
        ),
        const SizedBox(height: KraftSpace.sm),
        for (final engine in voice.engines.whereType<CompatibleChatEngine>())
          ProviderCredentials(engine: engine),
        if (ollama != null) _OllamaSettings(engine: ollama),
        if (voice.engine.id == 'gemini')
          _ModelPicker<ChatModel>(
            title: 'MODELO DEL CHAT DE GEMINI',
            options: ChatModel.values,
            selected: voice.chatModel,
            label: (m) => m.label,
            detail: (m) => m.detail,
            onPick: voice.setChatModel,
          ),
        if (voice.liveAudio) ...[
          const SizedBox(height: KraftSpace.md),
          _ModelPicker<LiveModel>(
            title: 'MODELO DE VOZ EN TIEMPO REAL',
            options: LiveModel.values,
            selected: LiveModel.from(voice.model),
            label: (m) => m.label,
            detail: (m) => m.detail,
            onPick: voice.setLiveModel,
          ),
          const SizedBox(height: KraftSpace.md),
          NeoBox(
            color: voice.economy
                ? KraftColors.secondaryContainer
                : KraftColors.surfaceContainerLowest,
            borderWidth: 1.5,
            shadow: voice.economy ? 2 : 0,
            radius: KraftRadius.sm,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Modo económico',
                        style: KraftText.bodyMd.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '"Hablar" dicta con el motor del iPad y te contesta con la voz del '
                        'sistema, sin abrir la Live API. El dictado y la voz son gratis: '
                        'sólo pagas el texto. Unas 10 veces más barato para probar largo rato.',
                        style: KraftText.bodySm.copyWith(
                          color: KraftColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: KraftSpace.sm),
                Switch(value: voice.economy, onChanged: voice.setEconomy),
              ],
            ),
          ),
        ],
        if (voice.liveAudio) ...[
          const SizedBox(height: KraftSpace.md),
          Text(
            'MICRÓFONO PARA CONVERSAR',
            style: KraftText.techBadge.copyWith(
              color: KraftColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(
                    '${voice.selectedMicrophoneId}-${voice.microphones.length}',
                  ),
                  initialValue: voice.selectedMicrophoneId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Symbols.mic, size: 20),
                    filled: true,
                    fillColor: KraftColors.surfaceContainer,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(KraftRadius.sm),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: [
                    for (final device in voice.microphones)
                      DropdownMenuItem(
                        value: device.id,
                        child: Text(
                          device.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: voice.loadingMicrophones
                      ? null
                      : (id) {
                          if (id != null) voice.setMicrophone(id);
                        },
                ),
              ),
              const SizedBox(width: KraftSpace.sm),
              IconButton.filledTonal(
                tooltip: 'Actualizar micrófonos',
                onPressed: voice.loadingMicrophones
                    ? null
                    : voice.refreshMicrophones,
                icon: voice.loadingMicrophones
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Symbols.refresh),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Si cambias de micrófono durante una conversación, KRAFT la reinicia con la nueva entrada.',
            style: KraftText.bodySm.copyWith(
              color: KraftColors.onSurfaceVariant,
            ),
          ),
          if (voice.microphoneError != null) ...[
            const SizedBox(height: 4),
            Text(
              voice.microphoneError!,
              style: KraftText.bodySm.copyWith(color: KraftColors.error),
            ),
          ],
        ],
        const SizedBox(height: KraftSpace.md),
        Row(
          children: [
            Icon(
              voice.hasKey ?? false ? Symbols.key : Symbols.key_off,
              size: 20,
            ),
            const SizedBox(width: KraftSpace.sm),
            Expanded(
              child: Text(
                voice.hasKey ?? false
                    ? 'API key de Gemini guardada en el llavero'
                    : 'Sin API key de Gemini',
                style: KraftText.bodyMd,
              ),
            ),
            if (voice.hasKey ?? false)
              TextButton(
                onPressed: voice.forgetKey,
                child: const Text('Borrar'),
              ),
          ],
        ),
        if (!(voice.hasKey ?? false)) ...[
          const SizedBox(height: KraftSpace.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _key,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (_) => setState(() {}),
                  style: KraftText.labelCode,
                  decoration: InputDecoration(
                    labelText: 'API key de aistudio.google.com/apikey',
                    filled: true,
                    fillColor: KraftColors.surfaceContainer,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(KraftRadius.sm),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: KraftSpace.sm),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: KraftColors.inkFill,
                  foregroundColor: KraftColors.onInkFill,
                ),
                onPressed: _key.text.trim().isEmpty
                    ? null
                    : () => voice.saveKey(_key.text),
                child: const Text('Guardar'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Theme.of(context); // Rebuild when the active palette changes.
    final theme = ref.watch(themeProvider);
    return _Section(
      title: 'Aspecto',
      subtitle: 'Claro de día, Gruvbox de noche',
      icon: Symbols.contrast,
      children: [
        Wrap(
          spacing: KraftSpace.sm,
          runSpacing: KraftSpace.sm,
          children: [
            for (final (mode, label, icon) in const [
              (ThemeMode.system, 'Como el sistema', Symbols.brightness_auto),
              (ThemeMode.light, 'Claro', Symbols.light_mode),
              (ThemeMode.dark, 'Gruvbox', Symbols.dark_mode),
            ])
              NeoBox(
                onTap: () => theme.set(mode),
                color: theme.mode == mode
                    ? KraftColors.primaryContainer
                    : KraftColors.surfaceContainerLowest,
                borderWidth: 1.5,
                shadow: theme.mode == mode ? 2 : 0,
                radius: KraftRadius.sm,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: KraftText.labelCode.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _DictationSection extends ConsumerWidget {
  const _DictationSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Theme.of(context); // Rebuild when the active palette changes.
    final dictation = ref.watch(dictationProvider);
    final detail = switch (dictation.engine) {
      'analyzer' =>
        'Listo: este iPad transcribe con el motor nuevo de iPadOS, rápido y sin conexión.',
      'legacy' =>
        'Listo: este iPad transcribe con el reconocimiento de voz del sistema.',
      'none' => 'Este iPad no tiene dictado disponible para el español.',
      _ => 'Comprobando…',
    };
    return _Section(
      title: 'Dictado',
      subtitle:
          'Hablar y que se escriba, sin enviar el audio a ningún servidor',
      icon: Symbols.keyboard_voice,
      children: [
        Text(detail, style: KraftText.bodySm),
        const SizedBox(height: KraftSpace.sm),
        Text(
          'Úsalo con el botón del micrófono pequeño del panel del asistente: dicta y el texto aparece escrito.',
          style: KraftText.bodySm.copyWith(color: KraftColors.onSurfaceVariant),
        ),
        if (dictation.error != null) ...[
          const SizedBox(height: KraftSpace.sm),
          Text(
            dictation.error!,
            style: KraftText.bodySm.copyWith(color: KraftColors.error),
          ),
        ],
      ],
    );
  }
}

class _OllamaSettings extends StatefulWidget {
  const _OllamaSettings({required this.engine});
  final OllamaChatEngine engine;
  @override
  State<_OllamaSettings> createState() => _OllamaSettingsState();
}

class _OllamaSettingsState extends State<_OllamaSettings> {
  final _model = TextEditingController();
  bool _deep = true, _checking = false;
  String? _status;
  String? _selected;
  String? _installing;
  List<OllamaModelInfo> _models = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final models = await widget.engine.listModels();
    final selected = await widget.engine.resolveModel(models);
    _model.text = selected;
    _deep = await widget.engine.deep;
    if (mounted) {
      setState(() {
        _models = models;
        _selected = selected;
      });
    }
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Future<void> _save({String? model}) async {
    final name = (model ?? _model.text).trim();
    await widget.engine.settings.set(
      OllamaChatEngine.modelKey,
      name.isEmpty ? OllamaChatEngine.fallbackModel : name,
    );
    await widget.engine.settings.set(OllamaChatEngine.deepKey, '$_deep');
    widget.engine.reset();
    if (mounted) {
      setState(() {
        _selected = name.isEmpty ? OllamaChatEngine.fallbackModel : name;
        _model.text = _selected!;
        _status = 'Configuración guardada.';
      });
    }
  }

  Future<void> _install(String name) async {
    setState(() {
      _installing = name;
      _status = 'Descargando $name…';
    });
    try {
      await for (final chunk in widget.engine.pull(name)) {
        if (!mounted) return;
        final status = '${chunk['status'] ?? 'Descargando'}';
        final completed = chunk['completed'];
        final total = chunk['total'];
        setState(() {
          _status = completed is num && total is num && total > 0
              ? '$status · ${(completed / total * 100).clamp(0, 100).toStringAsFixed(0)}%'
              : status;
        });
      }
      final models = await widget.engine.listModels();
      await widget.engine.settings.set(OllamaChatEngine.modelKey, name);
      widget.engine.reset();
      if (!mounted) return;
      setState(() {
        _models = models;
        _selected = name;
        _model.text = name;
        _installing = null;
        _status = '$name listo. Ya es el modelo activo.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _installing = null;
        _status = 'No se pudo instalar $name: $error';
      });
    }
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _status = null;
    });
    final available = await widget.engine.isReady();
    final models = available
        ? await widget.engine.listModels()
        : const <OllamaModelInfo>[];
    final selected = models.isEmpty
        ? _selected
        : await widget.engine.resolveModel(models);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _models = models;
      _selected = selected;
      if (selected != null) _model.text = selected;
      _status = !available
          ? 'No se encontró Ollama. Ábrelo y vuelve a probar.'
          : models.isEmpty
          ? 'Ollama responde, pero no hay modelos. Instala Qwen 3.5 4B, el más rápido.'
          : 'Ollama responde. ${models.length} modelo${models.length == 1 ? '' : 's'} disponible${models.length == 1 ? '' : 's'}.';
    });
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: const Text('Ollama local · Mac'),
    subtitle: Text(
      _models.isEmpty
          ? 'Usa los modelos instalados en Ollama'
          : _models.map((model) => model.name).join(' · '),
    ),
    childrenPadding: const EdgeInsets.fromLTRB(
      KraftSpace.md,
      0,
      KraftSpace.md,
      KraftSpace.md,
    ),
    children: [
      if (_models.isNotEmpty) ...[
        Text(
          'MODELOS INSTALADOS',
          style: KraftText.techBadge.copyWith(
            color: KraftColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: KraftSpace.sm,
          runSpacing: KraftSpace.sm,
          children: [
            for (final model in _models)
              NeoBox(
                onTap: () => _save(model: model.name),
                color: model.name == _selected
                    ? KraftColors.primaryContainer
                    : KraftColors.surfaceContainerLowest,
                borderWidth: 1.5,
                shadow: model.name == _selected ? 2 : 0,
                radius: KraftRadius.sm,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.name,
                      style: KraftText.labelCode.copyWith(
                        fontWeight: FontWeight.w700,
                        color: model.name == _selected
                            ? KraftColors.onPrimaryContainer
                            : KraftColors.onSurface,
                      ),
                    ),
                    Text(
                      model.detail,
                      style: KraftText.bodySm.copyWith(
                        color: model.name == _selected
                            ? KraftColors.onPrimaryContainer
                            : KraftColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: KraftSpace.sm),
      ],
      Builder(
        builder: (_) {
          final installed = {for (final model in _models) model.name};
          final missing = [
            for (final model in OllamaChatEngine.suggested)
              if (!installed.contains(model.name) &&
                  !installed.contains('${model.name}:latest'))
                model,
          ];
          if (missing.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MÁS RÁPIDOS · CUANTIZADOS',
                style: KraftText.techBadge.copyWith(
                  color: KraftColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'gemma4:12b es capaz, pero pesado. Estos Q4 contestan antes y siguen pudiendo usar herramientas.',
                style: KraftText.bodySm.copyWith(
                  color: KraftColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              for (final model in missing)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              model.label,
                              style: KraftText.labelCode.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(model.detail, style: KraftText.bodySm),
                          ],
                        ),
                      ),
                      FilledButton(
                        onPressed: _installing != null
                            ? null
                            : () => _install(model.name),
                        child: Text(
                          _installing == model.name
                              ? 'Instalando…'
                              : 'Instalar',
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
      TextField(
        controller: _model,
        decoration: const InputDecoration(
          labelText: 'Modelo',
          hintText: 'gemma4:12b',
        ),
      ),
      SwitchListTile.adaptive(
        value: _deep,
        onChanged: (value) => setState(() => _deep = value),
        title: const Text('Razonamiento para tareas profundas'),
      ),
      if (_status != null)
        Align(
          alignment: Alignment.centerLeft,
          child: Text(_status!, style: KraftText.bodySm),
        ),
      Wrap(
        spacing: KraftSpace.sm,
        children: [
          TextButton(
            onPressed: _checking ? null : _check,
            child: Text(_checking ? 'Comprobando…' : 'Probar conexión'),
          ),
          FilledButton(onPressed: () => _save(), child: const Text('Guardar')),
        ],
      ),
    ],
  );
}

class _AppSection extends ConsumerWidget {
  const _AppSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Theme.of(context); // Rebuild when the active palette changes.
    final reminders = ref.watch(reminderServiceProvider);
    final mcp = ref.watch(mcpControllerProvider);
    final webDiscovery = ref.watch(_webDiscoveryProvider).valueOrNull ?? false;
    return _Section(
      title: 'App',
      subtitle: 'Lienzo, recordatorios y conexiones',
      icon: Symbols.tune,
      children: [
        _SwitchRow(
          title: 'Búsqueda web beta',
          subtitle:
              'Envía la consulta al buscador público sin API key; puede fallar o cambiar.',
          value: webDiscovery,
          onChanged: (value) async {
            await ref
                .read(settingsRepositoryProvider)
                .set(webDiscoveryEnabledKey, '$value');
            ref.invalidate(_webDiscoveryProvider);
          },
        ),
        const Divider(height: KraftSpace.lg),
        _SwitchRow(
          title: 'Sincronizar con Recordatorios de Apple',
          subtitle: 'Las tareas con hora se copian a la app Recordatorios',
          value: reminders.appleSync,
          onChanged: (value) async {
            final ok = await reminders.setAppleSync(value);
            if (!ok && context.mounted) {
              KraftToast.show(
                context,
                'Permite el acceso en Ajustes › Privacidad › Recordatorios',
                icon: Symbols.lock,
              );
            }
          },
        ),
        const Divider(height: KraftSpace.lg),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Servidor MCP',
                    style: KraftText.bodyLg.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    mcp.running ? 'Encendido · ${mcp.endpoint}' : 'Apagado',
                    style: KraftText.bodySm.copyWith(
                      color: KraftColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => showAiConnectionSheet(context),
              child: const Text('Configurar'),
            ),
          ],
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: KraftText.bodyLg.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                subtitle,
                style: KraftText.bodySm.copyWith(
                  color: KraftColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          activeTrackColor: KraftColors.inkFill,
          activeThumbColor: KraftColors.primaryContainer,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Botón de ajustes para las barras superiores.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Tooltip(
      message: 'Ajustes',
      child: GestureDetector(
        onTap: () => context.push(Routes.settings),
        child: AnimatedContainer(
          duration: KraftMotion.of(context, KraftMotion.fast),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: KraftColors.surfaceContainer,
            borderRadius: BorderRadius.circular(KraftRadius.lg),
          ),
          child: Icon(Symbols.settings, size: 20, color: KraftColors.onSurface),
        ),
      ),
    );
  }
}

/// Lista de modelos con su precio: el usuario elige sabiendo lo que cuesta cada uno.
class _ModelPicker<T> extends StatelessWidget {
  const _ModelPicker({
    required this.title,
    required this.options,
    required this.selected,
    required this.label,
    required this.detail,
    required this.onPick,
  });

  final String title;
  final List<T> options;
  final T selected;
  final String Function(T) label;
  final String Function(T) detail;
  final void Function(T) onPick;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: KraftText.techBadge.copyWith(
            color: KraftColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        for (final option in options) ...[
          NeoBox(
            onTap: () => onPick(option),
            color: option == selected
                ? KraftColors.primaryContainer
                : KraftColors.surfaceContainerLowest,
            borderWidth: 1.5,
            shadow: option == selected ? 2 : 0,
            radius: KraftRadius.sm,
            padding: const EdgeInsets.all(12),
            child: Builder(
              builder: (context) {
                // Sobre el amarillo de selección hay que usar onPrimaryContainer:
                // con el color normal el texto se pierde, sobre todo en Gruvbox.
                final picked = option == selected;
                final ink = picked
                    ? KraftColors.onPrimaryContainer
                    : KraftColors.onSurface;
                return Row(
                  children: [
                    Icon(
                      picked
                          ? Symbols.radio_button_checked
                          : Symbols.radio_button_unchecked,
                      size: 18,
                      color: ink,
                    ),
                    const SizedBox(width: KraftSpace.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label(option),
                            style: KraftText.bodyMd.copyWith(
                              fontWeight: FontWeight.w700,
                              color: ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            detail(option),
                            style: KraftText.bodySm.copyWith(
                              color: picked
                                  ? KraftColors.onPrimaryContainer.withValues(
                                      alpha: 0.75,
                                    )
                                  : KraftColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: KraftSpace.xs + 2),
        ],
      ],
    );
  }
}
