import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/kraft_colors.dart';
import '../theme/kraft_motion.dart';
import '../theme/kraft_tokens.dart';
import '../theme/kraft_typography.dart';

/// Aviso flotante superior, con acción opcional ("Deshacer"). Sólo hay uno visible a la vez.
abstract final class KraftToast {
  static OverlayEntry? _current;

  static void show(
    BuildContext context,
    String message, {
    IconData icon = Symbols.check_circle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    showOn(Overlay.of(context, rootOverlay: true), message, icon: icon, actionLabel: actionLabel, onAction: onAction);
  }

  /// Para avisos lanzados tras un `await` cuyo widget de origen puede haberse desmontado:
  /// captura el overlay con `Overlay.of(context, rootOverlay: true)` antes de esperar.
  static void showOn(
    OverlayState overlay,
    String message, {
    IconData icon = Symbols.check_circle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!overlay.mounted) return;
    if (_current?.mounted ?? false) _current!.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastView(
        message: message,
        icon: icon,
        actionLabel: actionLabel,
        onAction: onAction,
        visibleFor: Duration(milliseconds: actionLabel == null ? 1800 : 4000),
        onDone: () {
          if (_current == entry) _current = null;
          if (entry.mounted) entry.remove();
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }
}

class _ToastView extends StatefulWidget {
  const _ToastView({
    required this.message,
    required this.icon,
    required this.visibleFor,
    required this.onDone,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final IconData icon;
  final Duration visibleFor;
  final VoidCallback onDone;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> with SingleTickerProviderStateMixin {
  static const _inMs = 240;
  static const _outMs = 160;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _inMs + widget.visibleFor.inMilliseconds + _outMs),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 0 = oculto arriba, 1 = visible.
  double get _presence {
    final total = _controller.duration!.inMilliseconds;
    final ms = _controller.value * total;
    if (ms < _inMs) return KraftMotion.pop.transform(ms / _inMs);
    if (ms > total - _outMs) return 1 - Curves.easeIn.transform((ms - (total - _outMs)) / _outMs);
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final top = MediaQuery.paddingOf(context).top + KraftSpace.md;
    return Positioned(
      top: top,
      left: KraftSpace.md,
      right: KraftSpace.md,
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final p = _presence;
            return Transform.translate(
              offset: Offset(0, -80 * (1 - p)),
              child: Opacity(opacity: p.clamp(0.0, 1.0), child: child),
            );
          },
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              padding: EdgeInsets.fromLTRB(KraftSpace.md, 8, widget.actionLabel == null ? KraftSpace.md : 6, 8),
              decoration: BoxDecoration(
                color: KraftColors.inkFill,
                borderRadius: BorderRadius.circular(KraftRadius.lg),
                boxShadow: KraftShadow.hard(3, KraftColors.primaryContainer),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon, size: 18, color: KraftColors.secondaryContainer),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      widget.message,
                      style: KraftText.labelCode.copyWith(color: KraftColors.surface, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (widget.actionLabel != null) ...[
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () {
                        widget.onAction?.call();
                        widget.onDone();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: KraftColors.primaryContainer,
                          borderRadius: BorderRadius.circular(KraftRadius.md),
                        ),
                        child: Text(
                          widget.actionLabel!.toUpperCase(),
                          style: KraftText.techBadge.copyWith(color: KraftColors.onPrimaryContainer),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
