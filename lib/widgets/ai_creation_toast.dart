import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/kraft_colors.dart';
import '../theme/kraft_motion.dart';
import '../theme/kraft_tokens.dart';
import '../theme/kraft_typography.dart';

/// Notificación animada con micro-interacción para creaciones realizadas por agentes de IA.
abstract final class AiCreationToast {
  static OverlayEntry? _current;

  static void show(
    BuildContext context, {
    required String title,
    required String subtitle,
    IconData icon = Symbols.auto_awesome,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    showOn(
      Overlay.of(context, rootOverlay: true),
      title: title,
      subtitle: subtitle,
      icon: icon,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void showOn(
    OverlayState overlay, {
    required String title,
    required String subtitle,
    IconData icon = Symbols.auto_awesome,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!overlay.mounted) return;
    if (_current?.mounted ?? false) _current!.remove();
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _AiCreationToastView(
        title: title,
        subtitle: subtitle,
        icon: icon,
        actionLabel: actionLabel,
        onAction: onAction,
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

class _AiCreationToastView extends StatefulWidget {
  const _AiCreationToastView({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onDone,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onDone;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<_AiCreationToastView> createState() => _AiCreationToastViewState();
}

class _AiCreationToastViewState extends State<_AiCreationToastView>
    with TickerProviderStateMixin {
  late final AnimationController _entranceCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );
  late final AnimationController _pulseCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  late final Animation<double> _scale = CurvedAnimation(
    parent: _entranceCtrl,
    curve: KraftMotion.pop,
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _entranceCtrl,
    curve: Curves.easeOut,
  );

  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    _entranceCtrl.forward();
    Future.delayed(const Duration(milliseconds: 3400), () {
      if (mounted && !_exiting) _dismiss();
    });
  }

  void _dismiss() {
    if (_exiting) return;
    _exiting = true;
    _entranceCtrl.reverse().then((_) {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 480;

    return Positioned(
      top: MediaQuery.paddingOf(context).top + 16,
      left: isCompact ? 16 : null,
      right: isCompact ? 16 : 24,
      child: Material(
        type: MaterialType.transparency,
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (context, child) {
                final glow = _pulseCtrl.value;
                return Container(
                  constraints: BoxConstraints(
                    maxWidth: isCompact ? double.infinity : 400,
                    minWidth: 280,
                  ),
                  decoration: BoxDecoration(
                    color: KraftColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(KraftRadius.lg),
                    border: Border.all(
                      color: KraftColors.primary.withValues(
                        alpha: 0.5 + glow * 0.5,
                      ),
                      width: 1.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: KraftColors.primary.withValues(
                          alpha: 0.15 + glow * 0.25,
                        ),
                        blurRadius: 16 + glow * 8,
                        spreadRadius: 1 + glow * 2,
                      ),
                      KraftShadow.hard(3)[0],
                    ],
                  ),
                  child: child,
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: KraftSpace.md,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            KraftColors.primaryContainer,
                            KraftColors.tertiaryContainer,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(KraftRadius.md),
                        boxShadow: [
                          BoxShadow(
                            color: KraftColors.primary.withValues(alpha: 0.4),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: Icon(
                        widget.icon,
                        size: 20,
                        color: KraftColors.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: KraftSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Text(
                                'CREADO POR IA',
                                style: KraftText.techBadge.copyWith(
                                  fontSize: 9,
                                  color: KraftColors.primary,
                                  letterSpacing: 1.1,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: KraftColors.secondaryContainer,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: KraftText.bodyMd.copyWith(
                              fontWeight: FontWeight.w700,
                              color: KraftColors.onSurface,
                            ),
                          ),
                          if (widget.subtitle.isNotEmpty)
                            Text(
                              widget.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: KraftText.labelCode.copyWith(
                                fontSize: 11,
                                color: KraftColors.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (widget.actionLabel != null && widget.onAction != null) ...[
                      const SizedBox(width: KraftSpace.sm),
                      TextButton(
                        onPressed: () {
                          _dismiss();
                          widget.onAction!();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: Text(widget.actionLabel!),
                      ),
                    ],
                    IconButton(
                      tooltip: 'Cerrar',
                      icon: const Icon(Symbols.close, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      onPressed: _dismiss,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
