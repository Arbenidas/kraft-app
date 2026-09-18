import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../theme/kraft_colors.dart';
import '../../theme/kraft_motion.dart';
import '../../theme/kraft_tokens.dart';
import '../../theme/kraft_typography.dart';
import 'canvas_models.dart';

/// Paleta flotante del lienzo. En horizontal: grosor + colores arriba y herramientas abajo.
/// En vertical (anclada a un lado): dos columnas, con las herramientas pegadas al borde.
class ToolPalette extends StatelessWidget {
  const ToolPalette({
    super.key,
    required this.tool,
    required this.strokeWidth,
    required this.color,
    required this.pressureEnabled,
    required this.onPressureChanged,
    required this.fingerDraws,
    required this.onFingerDrawsChanged,
    required this.eraserMode,
    required this.onEraserMode,
    required this.onTool,
    required this.onStrokeWidth,
    required this.onColor,
    required this.onOpenLibrary,
    required this.onCollapse,
    this.libraryOpen = false,
    this.vertical = false,
    this.toolsFirst = true,
    this.sideAlignment = CrossAxisAlignment.start,
  });

  final CanvasTool tool;
  final double strokeWidth;
  final Color color;
  final bool pressureEnabled;
  final ValueChanged<bool> onPressureChanged;

  /// Ajuste "Dibujar con el dedo" (por defecto sólo dibuja el Apple Pencil).
  final bool fingerDraws;
  final ValueChanged<bool> onFingerDrawsChanged;
  final EraserMode eraserMode;
  final ValueChanged<EraserMode> onEraserMode;
  final ValueChanged<CanvasTool> onTool;
  final ValueChanged<double> onStrokeWidth;
  final ValueChanged<Color> onColor;
  final VoidCallback onOpenLibrary;

  /// Encoge la paleta en una burbuja.
  final VoidCallback onCollapse;
  final bool libraryOpen;

  final bool vertical;

  /// En vertical: herramientas a la izquierda (paleta en el lado izquierdo) o a la derecha.
  final bool toolsFirst;

  /// En vertical: cómo se alinean las dos columnas (arriba, centro o abajo según el anclaje).
  final CrossAxisAlignment sideAlignment;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return vertical ? _buildVertical() : _buildHorizontal();
  }

  List<Widget> _toolButtons({required bool vertical}) => [
        for (final t in CanvasTool.values) ...[
          if (t == CanvasTool.eraser || t == CanvasTool.pen) vertical ? const _HDivider(width: 28) : const _VDivider(height: 28),
          _ToolButton(
            icon: t.icon,
            tooltip: '${t.label}  ·  ${t.shortcut}',
            selected: t == tool,
            danger: t == CanvasTool.eraser,
            vertical: vertical,
            onTap: () => onTool(t),
          ),
        ],
        vertical ? const _HDivider(width: 28) : const _VDivider(height: 28),
        _ToolButton(
          icon: Symbols.widgets,
          tooltip: 'Biblioteca de elementos',
          selected: libraryOpen,
          vertical: vertical,
          onTap: onOpenLibrary,
        ),
        _ToolButton(
          icon: Symbols.close_fullscreen,
          tooltip: 'Hacer bolita',
          selected: false,
          vertical: vertical,
          onTap: onCollapse,
        ),
      ];

  Widget _buildVertical() {
    final tools = _PaletteSurface(
      shadow: 4,
      padding: const EdgeInsets.all(4),
      child: Column(mainAxisSize: MainAxisSize.min, children: _toolButtons(vertical: true)),
    );
    final settings = _PaletteSurface(
      shadow: 3,
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: KraftColors.surfaceContainer,
              borderRadius: BorderRadius.circular(KraftRadius.md),
            ),
            // IntrinsicWidth: dentro del FittedBox el ancho no tiene límite y "stretch" fallaría.
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: tool == CanvasTool.eraser
                    ? [
                        for (final mode in EraserMode.values)
                          _EraserModeChip(mode: mode, selected: mode == eraserMode, compact: true, onTap: () => onEraserMode(mode)),
                      ]
                    : [
                        for (final width in canvasStrokeWidths)
                          _StrokeChip(width: width, selected: width == strokeWidth, onTap: () => onStrokeWidth(width)),
                      ],
              ),
            ),
          ),
          if (tool != CanvasTool.eraser) _PressureToggle(enabled: pressureEnabled, onChanged: onPressureChanged, compact: true),
          _FingerToggle(enabled: fingerDraws, onChanged: onFingerDrawsChanged, compact: true),
          const _HDivider(width: 20),
          for (final (c, name) in canvasColors)
            _ColorChip(color: c, name: name, selected: c == color, vertical: true, onTap: () => onColor(c)),
        ],
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: sideAlignment,
      children: toolsFirst
          ? [tools, const SizedBox(width: KraftSpace.sm), settings]
          : [settings, const SizedBox(width: KraftSpace.sm), tools],
    );
  }

  Widget _buildHorizontal() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PaletteSurface(
          shadow: 3,
          padding: const EdgeInsets.all(6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: KraftColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(KraftRadius.md),
                ),
                child: Row(
                  children: tool == CanvasTool.eraser
                      ? [
                          for (final mode in EraserMode.values)
                            _EraserModeChip(mode: mode, selected: mode == eraserMode, onTap: () => onEraserMode(mode)),
                        ]
                      : [
                          for (final width in canvasStrokeWidths)
                            _StrokeChip(
                              width: width,
                              selected: width == strokeWidth,
                              onTap: () => onStrokeWidth(width),
                            ),
                        ],
                ),
              ),
              if (tool != CanvasTool.eraser) _PressureToggle(enabled: pressureEnabled, onChanged: onPressureChanged),
              _FingerToggle(enabled: fingerDraws, onChanged: onFingerDrawsChanged),
              const _VDivider(height: 20),
              for (final (c, name) in canvasColors)
                _ColorChip(color: c, name: name, selected: c == color, onTap: () => onColor(c)),
            ],
          ),
        ),
        const SizedBox(height: KraftSpace.sm),
        _PaletteSurface(
          shadow: 4,
          padding: const EdgeInsets.all(4),
          child: Row(mainAxisSize: MainAxisSize.min, children: _toolButtons(vertical: false)),
        ),
      ],
    );
  }
}

class _PaletteSurface extends StatelessWidget {
  const _PaletteSurface({required this.child, required this.shadow, required this.padding});

  final Widget child;
  final double shadow;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: KraftColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(KraftRadius.xl),
        border: KraftBorder.ink(),
        boxShadow: KraftShadow.hard(shadow),
      ),
      child: child,
    );
  }
}

class _VDivider extends StatelessWidget {
  const _VDivider({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Container(
      width: 1,
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: KraftColors.outlineVariant,
    );
  }
}

class _HDivider extends StatelessWidget {
  const _HDivider({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Container(
      width: width,
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: KraftColors.outlineVariant,
    );
  }
}

class _StrokeChip extends StatelessWidget {
  const _StrokeChip({required this.width, required this.selected, required this.onTap});

  final double width;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final dot = 4 + width;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Grosor ${width.toInt()}px',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? KraftColors.surfaceContainerLowest : null,
            borderRadius: BorderRadius.circular(KraftRadius.sm),
            boxShadow: selected ? KraftShadow.soft : null,
          ),
          child: Row(
            children: [
              Container(
                width: dot,
                height: dot,
                decoration: BoxDecoration(color: KraftColors.ink, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              Text(
                '${width.toInt()}px',
                style: KraftText.labelCode.copyWith(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? KraftColors.onSurface : KraftColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorChip extends StatelessWidget {
  const _ColorChip({
    required this.color,
    required this.name,
    required this.selected,
    required this.onTap,
    this.vertical = false,
  });

  final Color color;
  final String name;
  final bool selected;
  final VoidCallback onTap;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: vertical ? const EdgeInsets.symmetric(vertical: 3) : const EdgeInsets.symmetric(horizontal: 3),
          width: 32,
          height: 32,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: selected ? KraftColors.ink : Colors.transparent, width: 2),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: KraftColors.ink.withValues(alpha: 0.2)),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
    this.danger = false,
    this.vertical = false,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final bool danger;
  final bool vertical;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final fg = selected
        ? KraftColors.primaryContainer
        : danger
            ? KraftColors.error
            : KraftColors.onSurface;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: KraftMotion.of(context, KraftMotion.fast),
            curve: KraftMotion.settle,
            width: 48,
            height: 48,
            margin: vertical ? const EdgeInsets.symmetric(vertical: 1) : const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: selected ? KraftColors.ink : Colors.transparent,
              borderRadius: BorderRadius.circular(KraftRadius.lg),
            ),
            child: AnimatedScale(
              scale: selected ? 1.12 : 1,
              duration: KraftMotion.of(context, KraftMotion.base),
              curve: KraftMotion.pop,
              child: Icon(icon, size: 22, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}

/// Activa o desactiva el grosor por presión del Apple Pencil.
class _PressureToggle extends StatelessWidget {
  const _PressureToggle({required this.enabled, required this.onChanged, this.compact = false});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  /// Sin texto, para la paleta vertical.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Tooltip(
      message: enabled ? 'Presión activada' : 'Presión desactivada',
      child: Semantics(
        button: true,
        toggled: enabled,
        label: 'Presión del lápiz',
        child: GestureDetector(
          onTap: () => onChanged(!enabled),
          child: AnimatedContainer(
            duration: KraftMotion.of(context, KraftMotion.fast),
            curve: KraftMotion.settle,
            margin: compact ? const EdgeInsets.only(top: 6) : const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: enabled ? KraftColors.primaryContainer : KraftColors.surfaceContainer,
              borderRadius: BorderRadius.circular(KraftRadius.md),
              border: Border.all(color: enabled ? KraftColors.ink : Colors.transparent, width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Tres barras de grosor creciente: la metáfora del trazo sensible a la presión.
                for (final h in const [2.0, 4.0, 6.0])
                  Container(
                    width: h,
                    height: 12,
                    margin: const EdgeInsets.only(right: 2),
                    decoration: BoxDecoration(
                      color: enabled ? KraftColors.ink : KraftColors.onSurfaceVariant,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                if (!compact) ...[
                  const SizedBox(width: 4),
                  Text(
                  'PRESIÓN',
                  style: KraftText.labelCode.copyWith(
                    fontSize: 11,
                    fontWeight: enabled ? FontWeight.w700 : FontWeight.w500,
                    color: enabled ? KraftColors.ink : KraftColors.onSurfaceVariant,
                  ),
                ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Modo del borrador: parcial, trazo completo o elemento.
class _EraserModeChip extends StatelessWidget {
  const _EraserModeChip({required this.mode, required this.selected, required this.onTap, this.compact = false});

  final EraserMode mode;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Tooltip(
      message: mode.description,
      child: Semantics(
        button: true,
        selected: selected,
        label: 'Borrador: ${mode.label}',
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? KraftColors.surfaceContainerLowest : null,
              borderRadius: BorderRadius.circular(KraftRadius.sm),
              boxShadow: selected ? KraftShadow.soft : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(mode.icon, size: 14, color: selected ? KraftColors.error : KraftColors.onSurfaceVariant),
                if (!compact) ...[
                  const SizedBox(width: 4),
                  Text(
                    mode.label.toUpperCase(),
                    style: KraftText.labelCode.copyWith(
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? KraftColors.onSurface : KraftColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Dibujar con el dedo": apagado, el dedo selecciona, mueve y desplaza; sólo el lápiz dibuja.
class _FingerToggle extends StatelessWidget {
  const _FingerToggle({required this.enabled, required this.onChanged, this.compact = false});

  final bool enabled;
  final ValueChanged<bool> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Tooltip(
      message: enabled ? 'El dedo también dibuja' : 'Sólo el Apple Pencil dibuja; el dedo selecciona y mueve',
      child: Semantics(
        button: true,
        toggled: enabled,
        label: 'Dibujar con el dedo',
        child: GestureDetector(
          onTap: () => onChanged(!enabled),
          child: AnimatedContainer(
            duration: KraftMotion.of(context, KraftMotion.fast),
            curve: KraftMotion.settle,
            margin: compact ? const EdgeInsets.only(top: 6) : const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: enabled ? KraftColors.primaryContainer : KraftColors.surfaceContainer,
              borderRadius: BorderRadius.circular(KraftRadius.md),
              border: Border.all(color: enabled ? KraftColors.ink : Colors.transparent, width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Symbols.touch_app, size: 15, color: enabled ? KraftColors.ink : KraftColors.onSurfaceVariant),
                if (!compact) ...[
                  const SizedBox(width: 4),
                  Text(
                    'DEDO',
                    style: KraftText.labelCode.copyWith(
                      fontSize: 11,
                      fontWeight: enabled ? FontWeight.w700 : FontWeight.w500,
                      color: enabled ? KraftColors.ink : KraftColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
