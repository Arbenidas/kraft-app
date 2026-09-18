import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'canvas_document.dart';
import 'canvas_models.dart';
import 'stroke_geometry.dart';

/// Recibe todos los punteros del lienzo y decide qué hacer según herramienta y dispositivo,
/// siguiendo las convenciones de iPadOS:
///
/// * **Apple Pencil** (y ratón): usa la herramienta activa: seleccionar, lazo, mover lienzo, dibujar, borrar o colocar.
/// * **Dedo**: nunca dibuja (salvo que se active "Dibujar con el dedo"). Toca para seleccionar,
///   toca dos veces para editar, arrastra un elemento para moverlo y arrastra en vacío para desplazar.
///   Mantener pulsado y arrastrar = lazo; mantener quieto = rueda para añadir.
/// * **Dos dedos**: desplazar y hacer zoom, cancelando cualquier gesto de un dedo.
class CanvasInputLayer extends StatefulWidget {
  const CanvasInputLayer({
    super.key,
    required this.document,
    required this.viewer,
    required this.live,
    required this.lasso,
    required this.tool,
    required this.color,
    required this.strokeWidth,
    required this.pressureEnabled,
    required this.fingerDraws,
    this.eraserMode = EraserMode.partial,
    required this.onPencilDetected,
    required this.onEditItem,
    required this.onPlaced,
    required this.child,
    this.onGestureStart,
    this.onHold,
    this.onHoldMove,
    this.onHoldEnd,
    this.ignoreAt,
    this.onTapItem,
    this.enableNavigation = true,
  });

  final bool enableNavigation;
  final CanvasDocument document;
  final TransformationController viewer;
  final LiveStroke live;
  final LassoPath lasso;
  final CanvasTool tool;
  final Color color;
  final double strokeWidth;

  /// Si el grosor sigue la presión del Apple Pencil.
  final bool pressureEnabled;

  /// Ajuste "Dibujar con el dedo": el dedo usa la herramienta activa como el lápiz.
  final bool fingerDraws;
  final EraserMode eraserMode;
  final VoidCallback onPencilDetected;
  final ValueChanged<CanvasItem> onEditItem;
  final VoidCallback onPlaced;
  final Widget child;

  /// Cualquier contacto nuevo (p. ej. para detener una animación de la vista).
  final VoidCallback? onGestureStart;

  /// Mantener el lápiz quieto (o el dedo, con herramientas de dibujo y sin Pencil detectado).
  /// Recibe el punto en pantalla y en el lienzo; devuelve `true` si se abrió algo (menú radial).
  final bool Function(Offset local, Offset world)? onHold;

  /// Movimiento y fin del gesto mientras el menú de pulsación mantenida está abierto
  /// ([onHoldEnd] recibe `null` si el gesto se canceló).
  final ValueChanged<Offset>? onHoldMove;
  final ValueChanged<Offset?>? onHoldEnd;

  /// Puntos del lienzo que el lienzo no debe tocar (p. ej. el campo de texto que se está editando,
  /// para que el teclado, la selección de texto y Scribble funcionen).
  final bool Function(Offset board)? ignoreAt;

  /// Toque sobre un elemento; devuelve `true` si lo gestionó (p. ej. marcar una casilla).
  final bool Function(CanvasItem item, Offset board)? onTapItem;

  static const minScale = 0.3;
  static const maxScale = 4.0;
  static const longPress = Duration(milliseconds: 350);
  static const doubleTapWindow = Duration(milliseconds: 320);
  static const hold = Duration(milliseconds: 450);

  /// El dedo tarda más en abrir la rueda: antes pasa por el lazo (pulsación larga + arrastre).
  static const fingerHold = Duration(milliseconds: 650);

  /// El pulso nunca está totalmente quieto: moverse menos que esto no cancela la pulsación mantenida.
  static const holdTolerance = 8.0;

  @override
  State<CanvasInputLayer> createState() => _CanvasInputLayerState();
}

enum _Mode {
  idle,
  draw,
  erase,
  place,
  pendingSelect,
  move,
  lasso,
  marquee,
  pan,
  pinch,
  hold,
  ignored,
}

class _CanvasInputLayerState extends State<CanvasInputLayer> {
  final _pointers = <int, (Offset position, PointerDeviceKind kind)>{};

  int? _primary;
  PointerDeviceKind _primaryKind = PointerDeviceKind.touch;
  _Mode _mode = _Mode.idle;
  Offset _downLocal = Offset.zero;
  Offset _downBoard = Offset.zero;
  Offset _lastLocal = Offset.zero;
  bool _moved = false;

  /// En selección, qué hacer si el gesto se convierte en arrastre.
  _Mode _dragIntent = _Mode.pan;
  CanvasHit? _downHit;
  Timer? _longPressTimer;
  Timer? _holdTimer;

  // Doble toque para editar texto.
  // Marcas de tiempo de los eventos (no el reloj): el doble toque no depende de lo cargado que esté el sistema.
  Duration? _lastTapAt;
  String? _lastTapItemId;
  bool _fingerPlaces = false;

  // Pellizco.
  late double _pinchStartDistance;
  late Offset _pinchStartFocal;
  late Matrix4 _pinchStartMatrix;

  CanvasDocument get _doc => widget.document;
  double get _scale => widget.viewer.value.getMaxScaleOnAxis();

  Offset _toBoard(Offset local) =>
      MatrixUtils.transformPoint(Matrix4.inverted(widget.viewer.value), local);

  bool _isPencil(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _holdTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Punteros
  // ---------------------------------------------------------------------------

  /// El lápiz y el ratón usan la herramienta; el dedo sólo si el usuario lo activó.
  bool _usesTool(PointerDeviceKind kind) =>
      _isPencil(kind) || kind == PointerDeviceKind.mouse || widget.fingerDraws;

  void _onDown(PointerDownEvent e) {
    if (widget.ignoreAt?.call(_toBoard(e.localPosition)) ?? false) return;
    widget.onGestureStart?.call();
    if (_isPencil(e.kind)) widget.onPencilDetected();
    _pointers[e.pointer] = (e.localPosition, e.kind);

    final touches = _pointers.entries
        .where((p) => !_isPencil(p.value.$2))
        .toList();
    if (touches.length >= 2 && !_isPencil(e.kind)) {
      // Dos dedos mandan: se cancela lo que hiciera el primero y empieza el pellizco.
      if (_primary != null && !_isPencil(_primaryKind)) _cancelActive();
      if (!widget.enableNavigation) {
        _mode = _Mode.ignored;
        return;
      }
      _startPinch(touches[0].value.$1, touches[1].value.$1);
      return;
    }
    if (_primary != null || _mode == _Mode.pinch) return;

    _primary = e.pointer;
    _primaryKind = e.kind;
    _downLocal = _lastLocal = e.localPosition;
    _downBoard = _toBoard(e.localPosition);
    _moved = false;

    if (!_usesTool(e.kind)) {
      _startFinger(e);
      return;
    }

    final tool = widget.tool;

    if (tool == CanvasTool.hand) {
      _mode = _Mode.pan;
      return;
    }

    // Pulsación mantenida → menú radial.
    if (widget.onHold != null) {
      final pointer = e.pointer;
      _holdTimer = Timer(CanvasInputLayer.hold, () => _fireHold(pointer));
    }

    if (tool.draws) {
      if (tool == CanvasTool.eraser) {
        _mode = _Mode.erase;
        _doc.beginErase();
        _eraseAt(_downBoard);
      } else {
        _mode = _Mode.draw;
        widget.live.start(
          _downBoard,
          color: widget.color,
          width: widget.strokeWidth,
          highlighter: tool == CanvasTool.highlighter,
          pressure: widget.pressureEnabled
              ? StrokePressure.normalized(e)
              : null,
        );
      }
      return;
    }

    if (tool.places) {
      _mode = _Mode.place;
      return;
    }

    // Selección / lazo.
    _mode = _Mode.pendingSelect;
    _downHit = _doc.hitTest(_downBoard, strokeTolerance: _hitTolerance(e.kind));
    final onSelection =
        (_downHit != null &&
            _doc.isHitSelected(_downHit!) &&
            _downHit!.linkId == null) ||
        _doc.selectionContains(_downBoard);

    if (tool == CanvasTool.lasso) {
      // El lazo siempre es lazo, también si empieza encima de un elemento.
      _dragIntent = onSelection ? _Mode.move : _Mode.lasso;
      if (onSelection) _holdTimer?.cancel();
    } else if (_downHit?.linkId != null) {
      _dragIntent = _Mode.marquee;
    } else if (_downHit != null || onSelection) {
      _holdTimer?.cancel(); // Sobre un elemento, mantener y arrastrar lo mueve.
      if (_downHit != null && !_doc.isHitSelected(_downHit!)) {
        _doc.selectOnly(_downHit!);
        HapticFeedback.selectionClick();
      } else {
        _isolateGroupedChild(_downHit);
      }
      _dragIntent = _Mode.move;
    } else {
      // Selección en vacío: recuadro (el lazo libre es su propia herramienta).
      _dragIntent = _Mode.marquee;
    }
  }

  /// Dedo sin "Dibujar con el dedo": seleccionar, mover, editar y desplazar, con cualquier herramienta.
  void _startFinger(PointerDownEvent e) {
    _mode = _Mode.pendingSelect;
    // Los trazos no se cogen con el dedo: arrastrar sobre la escritura desplaza el lienzo.
    final item = _doc.itemHitTest(_downBoard);
    final link = item == null
        ? _doc.linkHitTest(_downBoard, _hitTolerance(e.kind))
        : null;
    _downHit = item ?? link;
    final onSelection =
        (item != null && _doc.isHitSelected(item)) ||
        _doc.selectionContains(_downBoard);

    if (widget.tool == CanvasTool.hand) {
      _mode = _Mode.pan;
      return;
    }
    if (onSelection && link == null) {
      _isolateGroupedChild(item);
      _dragIntent = _Mode.move;
      return;
    }
    // An unselected element does not capture a scrolling gesture. Select on release.
    _dragIntent = _Mode.pan;
    if (link != null) return;
    // Colocar (texto, nota, figura) no es dibujar: un toque del dedo en vacío también coloca.
    _fingerPlaces = widget.tool.places;
    final pointer = e.pointer;
    _longPressTimer = Timer(CanvasInputLayer.longPress, () {
      if (_primary == pointer && _mode == _Mode.pendingSelect && !_moved) {
        _dragIntent = _Mode.lasso;
        widget.lasso.start(_downBoard);
        HapticFeedback.mediumImpact();
      }
    });
    if (widget.onHold != null) {
      _holdTimer = Timer(CanvasInputLayer.fingerHold, () => _fireHold(pointer));
    }
  }

  void _eraseAt(Offset board) {
    switch (widget.eraserMode) {
      case EraserMode.partial:
        _doc.erasePartialAt(board, _eraserRadius);
      case EraserMode.stroke:
        _doc.eraseAt(board, _eraserRadius);
      case EraserMode.element:
        _doc.eraseItemsAt(board, _eraserRadius);
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = (e.localPosition, e.kind);

    if (_mode == _Mode.hold) {
      if (e.pointer == _primary) widget.onHoldMove?.call(e.localPosition);
      return;
    }
    if (_holdTimer != null &&
        e.pointer == _primary &&
        (e.localPosition - _downLocal).distance >
            CanvasInputLayer.holdTolerance) {
      _holdTimer!.cancel();
      _holdTimer = null;
    }

    if (_mode == _Mode.pinch) {
      final touches = _pointers.values.where((p) => !_isPencil(p.$2)).toList();
      if (touches.length >= 2) _updatePinch(touches[0].$1, touches[1].$1);
      return;
    }
    if (e.pointer != _primary) return;

    final local = e.localPosition;
    final board = _toBoard(local);

    if (!_moved && (local - _downLocal).distance > _slop(e.kind)) {
      _moved = true;
      _longPressTimer?.cancel();
      if (_mode == _Mode.pendingSelect) {
        _mode = _dragIntent;
        if (_mode == _Mode.lasso && !widget.lasso.isActive)
          widget.lasso.start(_downBoard);
      } else if (_mode == _Mode.place) {
        _mode = _Mode.ignored;
      }
    }

    switch (_mode) {
      case _Mode.draw:
        widget.live.add(
          board,
          minDistance: 1 / _scale,
          pressure: StrokePressure.normalized(e),
        );
      case _Mode.erase:
        _eraseAt(board);
      case _Mode.lasso:
        widget.lasso.add(board, minDistance: 3 / _scale);
      case _Mode.marquee:
        widget.lasso.setRect(_downBoard, board);
      case _Mode.move:
        _doc.updateMove(board - _downBoard);
      case _Mode.pan:
        _panBy(local - _lastLocal);
      default:
        break;
    }
    _lastLocal = local;
  }

  void _onUp(PointerUpEvent e) {
    _pointers.remove(e.pointer);
    if (e.pointer == _primary) _holdTimer?.cancel();
    if (_mode == _Mode.hold && e.pointer == _primary) {
      widget.onHoldEnd?.call(e.localPosition);
      _reset();
      return;
    }
    if (_mode == _Mode.pinch) {
      if (_pointers.values.where((p) => !_isPencil(p.$2)).length < 2) {
        // El dedo que queda no retoma ningún gesto hasta levantar todos.
        _mode = _pointers.isEmpty ? _Mode.idle : _Mode.ignored;
        _primary = null;
      }
      return;
    }
    if (e.pointer != _primary) {
      if (_pointers.isEmpty && _mode == _Mode.ignored) _mode = _Mode.idle;
      return;
    }
    _longPressTimer?.cancel();

    switch (_mode) {
      case _Mode.draw:
        final stroke = widget.live.finish(_doc.allocateStrokeId());
        if (stroke != null) _doc.addStroke(stroke);
      case _Mode.lasso || _Mode.marquee:
        final points = widget.lasso.finish();
        final count = _doc.selectInLasso(points);
        if (count > 0) HapticFeedback.selectionClick();
      case _Mode.move:
        _doc.commitMove();
      case _Mode.place:
        _place();
      case _Mode.pendingSelect
          when _fingerPlaces && _downHit == null && !widget.lasso.isActive:
        _place();
      case _Mode.pendingSelect:
        if (widget.lasso.isActive) {
          // Pulsación larga sin arrastre: no hay lazo que aplicar.
          widget.lasso.finish();
        } else {
          _handleTap(e);
        }
      default:
        break;
    }
    _reset();
  }

  void _place() {
    _doc.place(widget.tool, _downBoard);
    HapticFeedback.lightImpact();
    widget.onPlaced();
  }

  void _onCancel(PointerCancelEvent e) {
    _pointers.remove(e.pointer);
    if (_mode == _Mode.hold && e.pointer == _primary)
      widget.onHoldEnd?.call(null);
    if (e.pointer == _primary || _mode == _Mode.pinch) {
      _cancelActive();
      _reset();
    }
  }

  void _fireHold(int pointer) {
    _holdTimer = null;
    if (_primary != pointer || _mode == _Mode.pinch) return;
    final opened = widget.onHold?.call(_downLocal, _downBoard) ?? false;
    if (!opened) return;
    // Lo que hubiera empezado el lápiz se descarta: la pulsación era para el menú.
    _longPressTimer?.cancel();
    switch (_mode) {
      case _Mode.draw:
        widget.live.cancel();
      case _Mode.lasso || _Mode.marquee || _Mode.pendingSelect:
        if (widget.lasso.isActive) widget.lasso.finish();
      default:
        break;
    }
    _mode = _Mode.hold;
    HapticFeedback.mediumImpact();
  }

  void _handleTap(PointerUpEvent e) {
    final hit = _downHit;
    final now = e.timeStamp;
    if (hit == null) {
      if (!_doc.selectionContains(_downBoard)) _doc.clearSelection();
      _lastTapItemId = null;
      return;
    }
    final tapped = hit.itemId == null ? null : _doc.itemById(hit.itemId!);
    if (tapped != null &&
        (widget.onTapItem?.call(tapped, _downBoard) ?? false)) {
      _lastTapItemId = null;
      return;
    }
    if (hit.linkId != null) {
      _doc.selectOnly(hit);
      HapticFeedback.selectionClick();
      _lastTapItemId = null;
      return;
    }
    final alreadyInGroup = _doc.isHitSelected(hit) && _doc.selectionCount > 1;
    if (!_doc.isHitSelected(hit)) _doc.selectOnly(hit);

    final isDoubleTap =
        hit.itemId != null &&
        hit.itemId == _lastTapItemId &&
        _lastTapAt != null &&
        now - _lastTapAt! <= CanvasInputLayer.doubleTapWindow;
    if (isDoubleTap) {
      _lastTapItemId = null;
      final item = _doc.items.firstWhere((i) => i.id == hit.itemId);
      if (item.editable) widget.onEditItem(item);
      return;
    }
    // Tocar un hijo con el grupo ya seleccionado lo aísla para moverlo solo.
    if (alreadyInGroup) _isolateGroupedChild(hit);
    _lastTapItemId = hit.itemId;
    _lastTapAt = now;
  }

  /// Un hijo tocado dentro de un grupo ya seleccionado se queda solo; el marco sigue moviendo a todos.
  void _isolateGroupedChild(CanvasHit? hit) {
    if (hit == null || _doc.selectionCount <= 1 || !_doc.isHitSelected(hit)) {
      return;
    }
    final item = hit.itemId == null ? null : _doc.itemById(hit.itemId!);
    if (item?.type == CanvasItemType.frame) return;
    _doc.selectOnly(hit, expandGroup: false);
  }

  void _cancelActive() {
    _longPressTimer?.cancel();
    _holdTimer?.cancel();
    switch (_mode) {
      case _Mode.draw:
        widget.live.cancel();
      case _Mode.lasso || _Mode.marquee || _Mode.pendingSelect:
        if (widget.lasso.isActive) widget.lasso.finish();
      case _Mode.move:
        _doc.cancelMove();
      default:
        break;
    }
  }

  void _reset() {
    _fingerPlaces = false;
    _primary = null;
    _downHit = null;
    _mode = _pointers.isEmpty ? _Mode.idle : _Mode.ignored;
  }

  double get _eraserRadius => 14 / _scale;

  double _hitTolerance(PointerDeviceKind kind) =>
      (_isPencil(kind) ? 8 : 16) / _scale;

  double _slop(PointerDeviceKind kind) => _isPencil(kind) ? 3 : kTouchSlop;

  // ---------------------------------------------------------------------------
  // Vista: desplazar y zoom
  // ---------------------------------------------------------------------------

  void _panBy(Offset delta) {
    if (delta == Offset.zero) return;
    _setView(
      Matrix4.translationValues(delta.dx, delta.dy, 0)
        ..multiply(widget.viewer.value),
    );
  }

  void _startPinch(Offset a, Offset b) {
    _mode = _Mode.pinch;
    _primary = null;
    _pinchStartDistance = math.max((a - b).distance, 1);
    _pinchStartFocal = (a + b) / 2;
    _pinchStartMatrix = widget.viewer.value.clone();
  }

  void _updatePinch(Offset a, Offset b) {
    final focal = (a + b) / 2;
    final startScale = _pinchStartMatrix.getMaxScaleOnAxis();
    final target = (startScale * (a - b).distance / _pinchStartDistance).clamp(
      CanvasInputLayer.minScale,
      CanvasInputLayer.maxScale,
    );
    _applyZoom(_pinchStartMatrix, _pinchStartFocal, focal, target / startScale);
  }

  /// Escala [base] alrededor de [from] y lo lleva a [to] (el punto bajo los dedos se mantiene bajo los dedos).
  void _applyZoom(Matrix4 base, Offset from, Offset to, double factor) {
    final m = Matrix4.identity()
      ..translateByDouble(to.dx, to.dy, 0, 1)
      ..scaleByDouble(factor, factor, 1, 1)
      ..translateByDouble(-from.dx, -from.dy, 0, 1)
      ..multiply(base);
    _setView(m);
  }

  void _setView(Matrix4 m) {
    if (widget.enableNavigation)
      widget.viewer.value = CanvasBounds.clampView(
        m,
        context.size ?? Size.zero,
      );
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      if (HardwareKeyboard.instance.isMetaPressed ||
          HardwareKeyboard.instance.isControlPressed) {
        final factor = math.exp(-e.scrollDelta.dy / 300);
        final target = (_scale * factor).clamp(
          CanvasInputLayer.minScale,
          CanvasInputLayer.maxScale,
        );
        _applyZoom(
          widget.viewer.value.clone(),
          e.localPosition,
          e.localPosition,
          target / _scale,
        );
      } else {
        _panBy(-e.scrollDelta);
      }
    }
  }

  // Trackpad del iPad: dos dedos desplazan y pellizcan.
  Matrix4? _panZoomStart;

  void _onPanZoomStart(PointerPanZoomStartEvent e) {
    widget.onGestureStart?.call();
    _panZoomStart = widget.viewer.value.clone();
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent e) {
    final start = _panZoomStart;
    if (start == null) return;
    final startScale = start.getMaxScaleOnAxis();
    final target = (startScale * e.scale).clamp(
      CanvasInputLayer.minScale,
      CanvasInputLayer.maxScale,
    );
    _applyZoom(
      start,
      e.localPosition,
      e.localPosition + e.pan,
      target / startScale,
    );
  }

  void _onPanZoomEnd(PointerPanZoomEndEvent e) => _panZoomStart = null;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onCancel,
      onPointerSignal: _onSignal,
      onPointerPanZoomStart: _onPanZoomStart,
      onPointerPanZoomUpdate: _onPanZoomUpdate,
      onPointerPanZoomEnd: _onPanZoomEnd,
      child: widget.child,
    );
  }
}
