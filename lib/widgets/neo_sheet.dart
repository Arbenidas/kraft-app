import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/kraft_colors.dart';
import '../theme/kraft_motion.dart';
import '../theme/kraft_tokens.dart';
import '../theme/kraft_typography.dart';
import 'neo_box.dart';

/// Hoja modal neobrutalista que sube desde abajo con rebote corto.
Future<T?> showNeoSheet<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
  String? eyebrow,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar',
    barrierColor: KraftColors.scrim,
    transitionDuration: KraftMotion.of(context, KraftMotion.slow),
    pageBuilder: (context, _, _) => _NeoSheetFrame(title: title, eyebrow: eyebrow, child: builder(context)),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: KraftMotion.pop, reverseCurve: Curves.easeIn);
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: const Interval(0, 0.4)),
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _NeoSheetFrame extends StatelessWidget {
  const _NeoSheetFrame({required this.title, required this.child, this.eyebrow});

  final String title;
  final String? eyebrow;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(KraftSpace.md, KraftSpace.md, KraftSpace.md, KraftSpace.md + insets),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                decoration: BoxDecoration(
                  color: KraftColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(KraftRadius.xl),
                  border: KraftBorder.ink(),
                  boxShadow: KraftShadow.hard(6),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(KraftSpace.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (eyebrow != null)
                                  Text(eyebrow!, style: KraftText.techBadge.copyWith(color: KraftColors.onSurfaceVariant)),
                                Text(title, style: KraftText.headlineSm.copyWith(fontSize: 24, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cerrar',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Symbols.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: KraftSpace.md),
                      child,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Campo de texto con etiqueta técnica y sombra dura.
class NeoTextField extends StatelessWidget {
  const NeoTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.maxLines = 1,
    this.autofocus = false,
    this.onSubmitted,
    this.textInputAction,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final int maxLines;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label.toUpperCase(), style: KraftText.techBadge.copyWith(color: KraftColors.onSurfaceVariant)),
        const SizedBox(height: 6),
        NeoBox(
          shadow: 2,
          radius: KraftRadius.sm,
          borderWidth: 1.5,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            controller: controller,
            autofocus: autofocus,
            maxLines: maxLines,
            minLines: 1,
            textInputAction: textInputAction,
            onSubmitted: onSubmitted,
            style: KraftText.bodyLg,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: KraftText.bodyLg.copyWith(color: KraftColors.outline),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
}

/// Selector de una opción entre varias, con pastillas neobrutalistas.
class NeoChoice<T> extends StatelessWidget {
  const NeoChoice({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<(T value, String label, Color color)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    // `start` y no `stretch`: el selector también se usa dentro de filas sin ancho acotado.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: KraftText.techBadge.copyWith(color: KraftColors.onSurfaceVariant)),
        const SizedBox(height: 6),
        Wrap(
          spacing: KraftSpace.sm,
          runSpacing: KraftSpace.sm,
          children: [
            for (final (v, text, color) in options)
              NeoBox(
                onTap: () => onChanged(v),
                color: v == value ? color : KraftColors.surfaceContainerLowest,
                borderWidth: 1.5,
                shadow: v == value ? 2 : 0,
                radius: KraftRadius.sm,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(
                  text,
                  style: KraftText.labelCode.copyWith(fontWeight: v == value ? FontWeight.w700 : FontWeight.w500),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Fila de acciones de una hoja: borrar (opcional) a la izquierda, guardar a la derecha.
class NeoSheetActions extends StatelessWidget {
  const NeoSheetActions({super.key, required this.onSave, this.saveLabel = 'Guardar', this.onDelete});

  final VoidCallback? onSave;
  final String saveLabel;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Row(
      children: [
        if (onDelete != null)
          NeoBox(
            onTap: onDelete,
            color: KraftColors.errorContainer,
            shadow: 2,
            radius: KraftRadius.sm,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(Symbols.delete, size: 18, color: KraftColors.onErrorContainer),
                const SizedBox(width: 6),
                Text('BORRAR', style: KraftText.labelCode.copyWith(fontWeight: FontWeight.w700, color: KraftColors.onErrorContainer)),
              ],
            ),
          ),
        const Spacer(),
        AnimatedOpacity(
          duration: KraftMotion.fast,
          opacity: onSave == null ? 0.45 : 1,
          child: NeoBox(
            onTap: onSave,
            color: KraftColors.primaryContainer,
            borderWidth: KraftBorder.width,
            shadow: 3,
            radius: KraftRadius.sm,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Text(saveLabel.toUpperCase(), style: KraftText.labelCode.copyWith(fontWeight: FontWeight.w700, color: KraftColors.onPrimaryContainer)),
          ),
        ),
      ],
    );
  }
}
