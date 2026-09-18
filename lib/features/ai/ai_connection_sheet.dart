import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../theme/kraft_colors.dart';
import '../../theme/kraft_motion.dart';
import '../../theme/kraft_tokens.dart';
import '../../theme/kraft_typography.dart';
import '../../widgets/kraft_toast.dart';
import '../../widgets/neo_box.dart';
import '../../widgets/neo_sheet.dart';
import 'ai_providers.dart';
import 'mcp_server.dart';

Future<void> showAiConnectionSheet(BuildContext context) {
  return showNeoSheet<void>(
    context,
    eyebrow: 'SERVIDOR MCP LOCAL',
    title: 'Conectar IA',
    builder: (_) => const _AiConnectionPanel(),
  );
}

/// Botón de la barra superior: punto verde con el servidor encendido y latido cuando la IA está editando.
class AiConnectButton extends ConsumerStatefulWidget {
  const AiConnectButton({super.key});

  @override
  ConsumerState<AiConnectButton> createState() => _AiConnectButtonState();
}

class _AiConnectButtonState extends ConsumerState<AiConnectButton> {
  Timer? _pulseOff;
  bool _pulsing = false;
  DateTime? _seenActivity;

  @override
  void dispose() {
    _pulseOff?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final mcp = ref.watch(mcpControllerProvider);
    if (mcp.lastActivityAt != _seenActivity) {
      _seenActivity = mcp.lastActivityAt;
      if (_seenActivity != null) {
        _pulsing = true;
        _pulseOff?.cancel();
        _pulseOff = Timer(const Duration(milliseconds: 1600), () {
          if (mounted) setState(() => _pulsing = false);
        });
      }
    }
    final on = mcp.running;
    return Tooltip(
      message: 'Conectar IA (MCP)',
      child: Semantics(
        button: true,
        label: 'Conectar IA',
        child: GestureDetector(
          onTap: () => showAiConnectionSheet(context),
          child: AnimatedContainer(
            duration: KraftMotion.of(context, KraftMotion.base),
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: _pulsing ? KraftColors.primaryContainer : KraftColors.surfaceContainer,
              borderRadius: BorderRadius.circular(KraftRadius.md),
              border: Border.all(color: on ? KraftColors.ink : KraftColors.ink.withValues(alpha: 0.1)),
              boxShadow: on ? KraftShadow.hard(2) : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: _pulsing ? 1.25 : 1,
                  duration: KraftMotion.of(context, KraftMotion.base),
                  curve: KraftMotion.pop,
                  child: Icon(Symbols.auto_awesome, size: 18, color: KraftColors.onSurface),
                ),
                const SizedBox(width: 6),
                Text('IA', style: KraftText.labelCode.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(width: 6),
                AnimatedContainer(
                  duration: KraftMotion.of(context, KraftMotion.fast),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: on ? KraftColors.secondaryContainer : KraftColors.outlineVariant,
                    shape: BoxShape.circle,
                    border: Border.all(color: KraftColors.ink, width: on ? 1 : 0),
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

class _AiConnectionPanel extends ConsumerWidget {
  const _AiConnectionPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Theme.of(context); // Rebuild when the active palette changes.
    final mcp = ref.watch(mcpControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Activa el servidor para que una IA local (LM Studio, Ollama con cliente MCP) o cualquier cliente MCP '
          '(Claude, Cursor…) dibuje diagramas y notas en tus lienzos mientras hablas con ella.',
          style: KraftText.bodyMd.copyWith(color: KraftColors.onSurfaceVariant),
        ),
        const SizedBox(height: KraftSpace.md),
        NeoBox(
          shadow: 2,
          radius: KraftRadius.md,
          borderWidth: 1.5,
          color: mcp.running ? KraftColors.secondaryContainer : KraftColors.surfaceContainerLowest,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              const Icon(Symbols.hub, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Servidor MCP', style: KraftText.headlineSm.copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
                    Text(
                      mcp.starting
                          ? 'Arrancando…'
                          : mcp.running
                              ? (mcp.clientName == null ? 'Esperando a un cliente' : 'Conectado: ${mcp.clientName}')
                              : 'Apagado',
                      style: KraftText.labelCode.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              Switch(
                value: mcp.enabled,
                activeTrackColor: KraftColors.inkFill,
                activeThumbColor: KraftColors.primaryContainer,
                onChanged: mcp.starting ? null : mcp.setEnabled,
              ),
            ],
          ),
        ),
        if (mcp.error != null) ...[
          const SizedBox(height: KraftSpace.sm),
          Text(mcp.error!, style: KraftText.bodySm.copyWith(color: KraftColors.error)),
        ],
        if (mcp.running) ...[
          const SizedBox(height: KraftSpace.md),
          _CopyField(label: 'Dirección', value: mcp.endpoint),
          if (mcp.addresses.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Otras redes: ${mcp.addresses.skip(1).join(' · ')}',
                style: KraftText.labelCode.copyWith(fontSize: 11, color: KraftColors.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: KraftSpace.sm),
          _CopyField(
            label: 'Token',
            value: mcp.token,
            trailing: IconButton(
              tooltip: 'Regenerar token',
              visualDensity: VisualDensity.compact,
              onPressed: mcp.regenerateToken,
              icon: const Icon(Symbols.autorenew, size: 18),
            ),
          ),
          const SizedBox(height: KraftSpace.md),
          Text('COPIAR CONFIGURACIÓN', style: KraftText.techBadge.copyWith(color: KraftColors.onSurfaceVariant)),
          const SizedBox(height: 6),
          Wrap(
            spacing: KraftSpace.sm,
            runSpacing: KraftSpace.sm,
            children: [
              _CopyChip(label: 'Claude Code', value: mcp.claudeCodeCommand),
              _CopyChip(label: 'JSON (LM Studio, Cursor)', value: mcp.jsonConfig),
              _CopyChip(label: 'Claude Desktop (mcp-remote)', value: mcp.stdioBridgeConfig),
            ],
          ),
          const SizedBox(height: KraftSpace.md),
          Text(
            'Mantén KRAFT abierto en pantalla y el ordenador en la misma Wi-Fi que el iPad. '
            'Lo que añada la IA aparece en el lienzo abierto y se puede deshacer.',
            style: KraftText.bodySm.copyWith(color: KraftColors.onSurfaceVariant),
          ),
          if (mcp.activity.isNotEmpty) ...[
            const SizedBox(height: KraftSpace.md),
            Text('ACTIVIDAD', style: KraftText.techBadge.copyWith(color: KraftColors.onSurfaceVariant)),
            const SizedBox(height: 6),
            for (final a in mcp.activity.take(6)) _ActivityRow(activity: a),
          ],
        ],
      ],
    );
  }
}

class _CopyField extends StatelessWidget {
  const _CopyField({required this.label, required this.value, this.trailing});

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label.toUpperCase(), style: KraftText.techBadge.copyWith(color: KraftColors.onSurfaceVariant)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            color: KraftColors.surfaceContainer,
            borderRadius: BorderRadius.circular(KraftRadius.sm),
            border: Border.all(color: KraftColors.ink.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(value, maxLines: 1, style: KraftText.labelCode.copyWith(fontWeight: FontWeight.w700)),
              ),
              ?trailing,
              IconButton(
                tooltip: 'Copiar ${label.toLowerCase()}',
                visualDensity: VisualDensity.compact,
                onPressed: () => _copy(context, value, label),
                icon: const Icon(Symbols.content_copy, size: 18),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CopyChip extends StatelessWidget {
  const _CopyChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return NeoBox(
      onTap: () => _copy(context, value, label),
      borderWidth: 1.5,
      shadow: 2,
      radius: KraftRadius.sm,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Symbols.content_copy, size: 15),
          const SizedBox(width: 6),
          Text(label, style: KraftText.labelCode.copyWith(fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.activity});

  final McpActivity activity;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final t = activity.at;
    final time = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            activity.ok ? Symbols.check_circle : Symbols.error,
            size: 16,
            color: activity.ok ? KraftColors.secondary : KraftColors.error,
          ),
          const SizedBox(width: 6),
          Text(time, style: KraftText.labelCode.copyWith(fontSize: 11, color: KraftColors.onSurfaceVariant)),
          const SizedBox(width: 8),
          Text(activity.tool, style: KraftText.labelCode.copyWith(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              activity.summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: KraftText.bodySm.copyWith(color: KraftColors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

void _copy(BuildContext context, String value, String label) {
  Clipboard.setData(ClipboardData(text: value));
  HapticFeedback.selectionClick();
  KraftToast.show(context, '$label copiado', icon: Symbols.content_copy);
}
