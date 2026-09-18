import 'package:flutter/material.dart';

import '../../theme/kraft_colors.dart';
import '../../theme/kraft_tokens.dart';
import '../../theme/kraft_typography.dart';
import '../voice/compatible_chat.dart';

class ProviderCredentials extends StatefulWidget {
  const ProviderCredentials({super.key, required this.engine});
  final CompatibleChatEngine engine;
  @override
  State<ProviderCredentials> createState() => _ProviderCredentialsState();
}

class _ProviderCredentialsState extends State<ProviderCredentials> {
  final keyInput = TextEditingController();
  final modelInput = TextEditingController();
  bool saved = false, busy = false;
  String? message;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final model = await widget.engine.settings.get(widget.engine.modelKey);
    final ready = await widget.engine.isReady();
    if (mounted)
      setState(() {
        modelInput.text = model ?? widget.engine.defaultModel;
        saved = ready;
      });
  }

  @override
  void dispose() {
    keyInput.dispose();
    modelInput.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (modelInput.text.trim().isEmpty) {
      setState(() => message = 'Escribe el nombre del modelo.');
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      if (keyInput.text.trim().isNotEmpty)
        await widget.engine.store.write(
          widget.engine.keyName,
          keyInput.text.trim(),
        );
      await widget.engine.settings.set(
        widget.engine.modelKey,
        modelInput.text.trim(),
      );
      widget.engine.reset();
      final ready = await widget.engine.isReady();
      if (mounted)
        setState(() {
          saved = ready;
          keyInput.clear();
          message = ready
              ? 'Configuración guardada.'
              : 'Agrega una API key para conectar.';
        });
    } catch (_) {
      if (mounted)
        setState(() => message = 'No se pudo guardar en el llavero.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: Text('${widget.engine.label} · API'),
    subtitle: Text(
      saved
          ? 'Clave guardada en el llavero'
          : widget.engine.id == 'openrouter'
          ? 'Modelos gratuitos · sin configurar'
          : 'Sin configurar',
    ),
    children: [
      if (widget.engine.hint != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            widget.engine.hint!,
            style: KraftText.bodySm.copyWith(
              color: KraftColors.onSurfaceVariant,
            ),
          ),
        ),
      if (widget.engine.catalog.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Wrap(
            spacing: KraftSpace.sm,
            runSpacing: KraftSpace.sm,
            children: [
              for (final model in widget.engine.catalog)
                FilterChip(
                  selected: modelInput.text.trim() == model.id,
                  label: Text(model.label),
                  tooltip: model.detail,
                  onSelected: (_) => setState(() => modelInput.text = model.id),
                ),
            ],
          ),
        ),
      TextField(
        controller: modelInput,
        decoration: const InputDecoration(labelText: 'Modelo'),
      ),
      TextField(
        controller: keyInput,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: saved ? 'Reemplazar API key' : 'API key',
        ),
      ),
      if (message != null)
        Padding(padding: const EdgeInsets.all(8), child: Text(message!)),
      Row(
        children: [
          TextButton(
            onPressed: busy ? null : _save,
            child: const Text('Guardar'),
          ),
          if (saved)
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      await widget.engine.store.delete(widget.engine.keyName);
                      widget.engine.reset();
                      if (mounted) setState(() => saved = false);
                    },
              child: const Text('Eliminar clave'),
            ),
        ],
      ),
    ],
  );
}
