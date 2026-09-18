import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kraft_web_discovery/kraft_web_discovery.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/providers.dart';
import '../../theme/kraft_colors.dart';
import '../../theme/kraft_tokens.dart';
import '../../theme/kraft_typography.dart';
import '../../widgets/neo_sheet.dart';
import '../ai/ai_providers.dart';
import '../voice/assistant_engine.dart';

const webDiscoveryEnabledKey = 'notes.webDiscoveryBeta';

Future<void> showNoteAiSheet(
  BuildContext context,
  WidgetRef ref, {
  required String text,
  required String selectedText,
  required ValueChanged<String> onApply,
}) => showNeoSheet<void>(
  context,
  eyebrow: 'IA PARA NOTAS',
  title: 'Trabajar con esta nota',
  builder: (_) =>
      _NoteAiSheet(text: text, selectedText: selectedText, onApply: onApply),
);

class _NoteAiSheet extends ConsumerStatefulWidget {
  const _NoteAiSheet({
    required this.text,
    required this.selectedText,
    required this.onApply,
  });
  final String text;
  final String selectedText;
  final ValueChanged<String> onApply;
  @override
  ConsumerState<_NoteAiSheet> createState() => _NoteAiSheetState();
}

class _NoteAiSheetState extends ConsumerState<_NoteAiSheet> {
  String? _result;
  String? _error;
  bool _loading = false;
  List<WebSearchResult>? _sources;
  String get _target =>
      widget.selectedText.trim().isEmpty ? widget.text : widget.selectedText;

  Future<void> _ask(String operation) async {
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
      _sources = null;
    });
    final prompt =
        '$operation el siguiente texto en español. Devuelve únicamente el contenido propuesto, en Markdown claro.\n\n---\n$_target';
    final out = StringBuffer();
    try {
      await for (final event
          in ref.read(voiceControllerProvider).engine.send(prompt)) {
        switch (event) {
          case AssistantDelta(:final text):
            out.write(text);
          case AssistantReply(:final text):
            if (out.isEmpty) out.write(text);
          case AssistantFailed(:final message):
            throw Exception(message);
          default:
            break;
        }
      }
      if (!mounted) return;
      setState(() => _result = out.toString().trim());
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _search() async {
    final enabled =
        await ref
            .read(settingsRepositoryProvider)
            .get(webDiscoveryEnabledKey) ==
        'true';
    if (!enabled) {
      setState(
        () => _error =
            'Activa “Búsqueda web beta” en Ajustes antes de enviar texto a Internet.',
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final found = await WebSearchClient().search(
        _target.length > 220 ? _target.substring(0, 220) : _target,
      );
      if (mounted) setState(() => _sources = found);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo buscar: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        widget.selectedText.trim().isEmpty
            ? 'Usará toda la nota.'
            : 'Usará el texto seleccionado.',
        style: KraftText.bodySm.copyWith(color: KraftColors.onSurfaceVariant),
      ),
      const SizedBox(height: KraftSpace.md),
      Wrap(
        spacing: KraftSpace.sm,
        runSpacing: KraftSpace.sm,
        children: [
          FilledButton.icon(
            onPressed: _loading || _target.trim().isEmpty
                ? null
                : () => _ask('Resume'),
            icon: const Icon(Symbols.summarize),
            label: const Text('Resumir'),
          ),
          OutlinedButton.icon(
            onPressed: _loading || _target.trim().isEmpty
                ? null
                : () => _ask('Expande con contexto, ejemplos y estructura'),
            icon: const Icon(Symbols.auto_awesome),
            label: const Text('Expandir'),
          ),
          OutlinedButton.icon(
            onPressed: _loading || _target.trim().isEmpty ? null : _search,
            icon: const Icon(Symbols.travel_explore),
            label: const Text('Buscar web beta'),
          ),
        ],
      ),
      if (_loading)
        const Padding(
          padding: EdgeInsets.all(KraftSpace.lg),
          child: Center(child: CircularProgressIndicator()),
        ),
      if (_error case final error?)
        Padding(
          padding: const EdgeInsets.only(top: KraftSpace.md),
          child: Text(
            error,
            style: KraftText.bodySm.copyWith(color: KraftColors.error),
          ),
        ),
      if (_result case final result? when result.isNotEmpty) ...[
        const SizedBox(height: KraftSpace.md),
        Text('Vista previa', style: KraftText.labelCode),
        const SizedBox(height: KraftSpace.xs),
        Container(
          padding: const EdgeInsets.all(KraftSpace.sm),
          decoration: BoxDecoration(
            color: KraftColors.surfaceContainer,
            borderRadius: BorderRadius.circular(KraftRadius.md),
          ),
          child: SelectableText(result, style: KraftText.bodySm),
        ),
        const SizedBox(height: KraftSpace.sm),
        FilledButton.icon(
          onPressed: () {
            widget.onApply(result);
            Navigator.pop(context);
          },
          icon: const Icon(Symbols.check),
          label: Text(
            widget.selectedText.trim().isEmpty
                ? 'Reemplazar nota'
                : 'Reemplazar selección',
          ),
        ),
      ],
      if (_sources case final sources?) ...[
        const SizedBox(height: KraftSpace.md),
        Text(
          'Fuentes beta · revisa antes de usarlas',
          style: KraftText.labelCode,
        ),
        for (final source in sources)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Symbols.link),
            title: Text(source.title),
            subtitle: Text(
              source.url.toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (sources.isEmpty)
          const Text('No hubo resultados públicos para esta consulta.'),
      ],
    ],
  );
}
