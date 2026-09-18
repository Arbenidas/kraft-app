import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app/router.dart';
import '../../data/providers.dart';
import '../../data/repositories.dart';
import '../../platform/apple_pencil.dart';
import '../../theme/kraft_colors.dart';
import '../../theme/kraft_motion.dart';
import '../../theme/kraft_tokens.dart';
import '../../theme/kraft_typography.dart';
import '../../widgets/entrance.dart';
import '../../widgets/kraft_toast.dart';
import '../../widgets/kraft_top_bar.dart';
import '../ai/ai_connection_sheet.dart';
import '../ai/ai_providers.dart';
import '../ai/canvas_bridge.dart';
import 'canvas_codec.dart';
import 'canvas_document.dart';
import 'canvas_input.dart';
import 'canvas_items.dart';
import 'canvas_minimap.dart';
import 'canvas_models.dart';
import 'canvas_painters.dart';
import 'canvas_selection.dart';
import '../../widgets/neo_box.dart';
import 'element_catalog.dart';
import 'element_gallery.dart';
import 'floating_palette.dart';
import 'item_editor.dart';
import 'link_picker.dart';
import 'radial_menu.dart';
import 'text_blocks.dart';
import 'tool_palette.dart';

/// Modo lienzo a pantalla completa: Apple Pencil para dibujar y seleccionar, dedos para mover y hacer zoom.
/// Se guarda al salir con el botón de volver, al pasar la app a segundo plano y al cerrarse.
class CanvasScreen extends ConsumerStatefulWidget {
  const CanvasScreen({super.key, required this.canvasId});

  final int canvasId;

  @override
  ConsumerState<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends ConsumerState<CanvasScreen>
    with SingleTickerProviderStateMixin
    implements LiveCanvas {
  late final CanvasesRepository _repo;
  late final CanvasBridge _bridge;

  /// Bloque de texto que se está escribiendo en el sitio.
  String? _editingId;
  bool _editingIsNew = false;
  final _loaded = Completer<void>();
  late CanvasDocument _doc;
  _LoadState _load = _LoadState.loading;
  CanvasData? _initialData;
  late final AppLifecycleListener _lifecycle;

  /// Revisión y título guardados por última vez: si coinciden no hace falta volver a guardar.
  int _savedRevision = 0;
  String _savedTitle = '';
  bool _exiting = false;

  // Paleta, galería y menú radial.
  bool _paletteCollapsed = false;
  PaletteDock _dock = PaletteDock.bottomCenter;
  PaletteDock _lastCornerDock = PaletteDock.bottomRight;
  bool _galleryOpen = false;
  bool _gallerySearchFocused = false;
  Size? _paletteSize;
  final _radial = ValueNotifier<RadialMenuState?>(null);
  final _viewportKey = GlobalKey();

  // Conectores.
  final _connect = ValueNotifier<ConnectorDrag?>(null);

  /// Elemento de origen si al soltar el conector en vacío se abrió la rueda (lo que se añada queda conectado).
  String? _pendingLinkFrom;

  /// Elemento de origen tras tocar el tirador: el siguiente elemento que se toque se conecta.
  String? _tapConnectFrom;

  final _viewer = TransformationController();
  final _live = LiveStroke();
  final _lasso = LassoPath();
  final _focus = FocusNode(debugLabel: 'lienzo');

  CanvasTool _tool = CanvasTool.select;
  CanvasTool _previousTool = CanvasTool.pen;
  double _strokeWidth = 4;
  bool _pressureEnabled = true;

  /// Ajuste guardado: por defecto sólo el Apple Pencil dibuja y el dedo selecciona, edita y mueve.
  bool _fingerDraws = false;
  EraserMode _eraserMode = EraserMode.partial;
  static const _fingerDrawsKey = 'canvas.fingerDraws';
  static const _eraserModeKey = 'canvas.eraserMode';
  Color _color = KraftColors.ink;
  String _title = '';

  /// Se activa con el primer toque de un Apple Pencil: a partir de ahí el dedo sólo mueve el lienzo.
  bool _pencilDetected = false;

  Size _viewportSize = Size.zero;
  StreamSubscription<PencilEvent>? _pencilEvents;

  /// La vista se centra en el contenido tras la primera maquetación (hace falta el tamaño del visor).
  bool _viewReady = false;
  bool _userMovedView = false;
  bool _minimapExpanded = true;

  // Se crea en initState (no perezoso): crearlo por primera vez en dispose falla al buscar TickerMode.
  late final AnimationController _viewAnimation;
  Matrix4Tween? _viewTween;

  @override
  void initState() {
    super.initState();
    _viewAnimation =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 380),
        )..addListener(() {
          final tween = _viewTween;
          if (tween != null) {
            _viewer.value = tween.evaluate(
              CurvedAnimation(
                parent: _viewAnimation,
                curve: Curves.easeOutCubic,
              ),
            );
          }
        });
    _pencilEvents = ApplePencil.events.listen(_onPencilEvent);
    _repo = ref.read(canvasesRepositoryProvider);
    // La IA (servidor MCP) edita este lienzo en vivo mientras está abierto.
    _bridge = ref.read(canvasBridgeProvider)..attach(this);
    _lifecycle = AppLifecycleListener(onHide: _save, onInactive: _save);
    _live.addListener(_onLiveStroke);
    _loadCanvas();
    _loadInputSettings();
  }

  Future<void> _loadCanvas() async {
    final record = await _repo.get(widget.canvasId);
    if (!mounted || record == null) {
      if (mounted) setState(() => _load = _LoadState.missing);
      _loaded.complete();
      return;
    }
    final data = CanvasCodec.decode(record.data);
    setState(() {
      _initialData = data;
      _doc = CanvasDocument(
        items: data.items,
        strokes: data.strokes,
        links: data.links,
      )..addListener(_onDocChanged);
      _title = record.title;
      _savedTitle = record.title;
      _savedRevision = _doc.revision;
      _load = _LoadState.ready;
    });
    _loaded.complete();
  }

  // ---- LiveCanvas (servidor MCP) ----

  @override
  int get canvasId => widget.canvasId;

  @override
  String get canvasTitle => _title;

  @override
  CanvasDocument? get document =>
      _load == _LoadState.ready && mounted ? _doc : null;

  @override
  Future<void> get ready => _loaded.future;

  @override
  Future<void> persist() => _save();

  @override
  void reveal(Rect world) {
    // No se mueve la vista bajo el lápiz ni antes de tener tamaño.
    if (!mounted ||
        !_viewReady ||
        _viewportSize.isEmpty ||
        _live.isActive ||
        _doc.isMoving)
      return;
    final visible = MatrixUtils.transformRect(
      Matrix4.inverted(_viewer.value),
      Offset.zero & _viewportSize,
    ).deflate(24);
    if (visible.contains(world.topLeft) && visible.contains(world.bottomRight))
      return;
    _userMovedView = true;
    final fit = math.min(
      _viewportSize.width * 0.8 / world.width,
      _viewportSize.height * 0.7 / world.height,
    );
    final scale = math
        .min(_viewer.value.getMaxScaleOnAxis(), fit)
        .clamp(CanvasInputLayer.minScale, CanvasInputLayer.maxScale);
    _animateView(_viewCentering(world.center, scale));
  }

  @override
  void announceRemoteEdit(String summary) {
    if (!mounted) return;
    HapticFeedback.lightImpact();
    KraftToast.show(
      context,
      'IA · $summary',
      icon: Symbols.auto_awesome,
      actionLabel: 'Deshacer',
      onAction: _doc.undo,
    );
  }

  @override
  void focusItem(String itemId) {
    if (!mounted || _load != _LoadState.ready) return;
    final item = _doc.itemById(itemId);
    if (item == null) return;
    _doc.selectOnly(CanvasHit.item(itemId));
    reveal(_doc.itemRect(item).inflate(18));
    HapticFeedback.selectionClick();
  }

  Future<void> _loadInputSettings() async {
    final settings = ref.read(settingsRepositoryProvider);
    final fingerDraws = await settings.get(_fingerDrawsKey) == 'true';
    final eraser = EraserMode.values
        .asNameMap()[await settings.get(_eraserModeKey)];
    if (!mounted) return;
    setState(() {
      _fingerDraws = fingerDraws;
      if (eraser != null) _eraserMode = eraser;
    });
  }

  void _setFingerDraws(bool value) {
    setState(() => _fingerDraws = value);
    ref.read(settingsRepositoryProvider).set(_fingerDrawsKey, '$value');
    KraftToast.show(
      context,
      value ? 'El dedo también dibuja' : 'Sólo el Apple Pencil dibuja',
      icon: Symbols.touch_app,
    );
  }

  void _setEraserMode(EraserMode mode) {
    setState(() => _eraserMode = mode);
    ref.read(settingsRepositoryProvider).set(_eraserModeKey, mode.name);
  }

  bool get _dirty =>
      _load == _LoadState.ready &&
      (_doc.revision != _savedRevision || _title != _savedTitle);

  CanvasData _snapshot() {
    final scale = _viewer.value.getMaxScaleOnAxis();
    final center = _viewportSize.isEmpty
        ? null
        : _viewer.toScene(_viewportSize.center(Offset.zero));
    return CanvasData(
      items: _doc.items,
      strokes: _doc.strokes,
      links: _doc.links,
      viewCenter: center,
      viewScale: center == null ? null : scale,
    );
  }

  String get _titleToSave =>
      _title.trim().isEmpty ? 'Lienzo sin título' : _title.trim();

  Future<void> _save() async {
    if (_load != _LoadState.ready) return;
    _commitDraft();
    final revision = _doc.revision;
    final title = _title;
    // La vista también se guarda aunque no haya cambios de contenido.
    await _repo.save(
      widget.canvasId,
      title: _titleToSave,
      data: CanvasCodec.encode(_snapshot()),
    );
    _savedRevision = revision;
    _savedTitle = title;
  }

  Future<void> _saveAndExit() async {
    if (_exiting) return;
    _exiting = true;
    _live.cancel();
    _finishEditing();
    await _save();
    if (!mounted) return;
    KraftToast.show(context, 'Lienzo guardado', icon: Symbols.save);
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.canvas);
    }
  }

  /// Al empezar a dibujar, la paleta se hace bolita en su última esquina.
  /// Espera a que el trazo avance: apoyar el lápiz sin moverlo puede ser para abrir la rueda.
  void _onLiveStroke() {
    if (_live.points.length > 3 && !_paletteCollapsed) {
      setState(() {
        _paletteCollapsed = true;
        _galleryOpen = false;
        _gallerySearchFocused = false;
        if (_dock == PaletteDock.bottomCenter) _dock = _lastCornerDock;
      });
    }
  }

  @override
  void dispose() {
    // Red de seguridad: si se sale sin el botón (p. ej. cambiando de pestaña), se guarda igualmente.
    if (_load == _LoadState.ready) _commitDraft();
    if (_dirty && !_exiting)
      _repo.save(
        widget.canvasId,
        title: _titleToSave,
        data: CanvasCodec.encode(_snapshot()),
      );
    _bridge.detach(this);
    _lifecycle.dispose();
    _live.removeListener(_onLiveStroke);
    _radial.dispose();
    _connect.dispose();
    _pencilEvents?.cancel();
    _viewAnimation.dispose();
    if (_load == _LoadState.ready) _doc.dispose();
    _viewer.dispose();
    _live.dispose();
    _lasso.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ---- Conectores ----

  /// Modo "tocar el destino": en cuanto se selecciona otro elemento, se conectan.
  void _onDocChanged() {
    final from = _tapConnectFrom;
    if (from == null) return;
    final single = _doc.singleSelectedItem;
    if (single != null && single.id == from) return;
    setState(() => _tapConnectFrom = null);
    if (single != null) {
      _doc
        ..addLink(from, single.id)
        ..selectOnly(CanvasHit.item(from));
      HapticFeedback.mediumImpact();
    }
  }

  Offset? _globalToWorld(Offset global) {
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return _viewer.toScene(box.globalToLocal(global));
  }

  void _connectStart(String fromId, Offset global) {
    final world = _globalToWorld(global);
    if (world == null) return;
    setState(() => _tapConnectFrom = null);
    _connect.value = ConnectorDrag(fromId: fromId, point: world);
    HapticFeedback.selectionClick();
  }

  void _connectUpdate(Offset global) {
    final state = _connect.value;
    final world = _globalToWorld(global);
    if (state == null || world == null) return;
    final hit = _doc.itemHitTest(world)?.itemId;
    final target = hit == state.fromId ? null : hit;
    if (target != state.targetId && target != null)
      HapticFeedback.selectionClick();
    _connect.value = ConnectorDrag(
      fromId: state.fromId,
      point: world,
      targetId: target,
    );
  }

  void _connectEnd() {
    final state = _connect.value;
    _connect.value = null;
    if (state == null) return;
    final target = state.targetId;
    if (target != null) {
      _doc.addLink(state.fromId, target);
      HapticFeedback.mediumImpact();
      return;
    }
    final from = _doc.itemById(state.fromId);
    if (from == null || _doc.itemRect(from).inflate(24).contains(state.point))
      return;
    // Soltado en vacío: la rueda ofrece qué crear ahí, ya conectado.
    _pendingLinkFrom = state.fromId;
    final local = MatrixUtils.transformPoint(_viewer.value, state.point);
    _radial.value = RadialMenuState(
      center: RadialMenu.clampCenter(local, _viewportSize),
      world: state.point,
      held: false,
    );
  }

  Future<void> _editLinkLabel(CanvasLink link) async {
    final text = await _promptText(
      context,
      'Etiqueta de la conexión',
      link.label,
    );
    if (text != null) _doc.updateLink(link.copyWith(label: text));
  }

  void _moveLinkBend(CanvasLink link, Offset global) {
    final world = _globalToWorld(global);
    if (world != null) _doc.updateLinkBend(world);
  }

  void _moveLinkLabel(CanvasLink link, Offset global) {
    final world = _globalToWorld(global);
    final geometry = _doc.linkGeometry(link);
    if (world != null && geometry != null)
      _doc.updateLinkLabelOffset(world - geometry.mid);
  }

  // ---- Herramientas ----

  void _setTool(CanvasTool tool) {
    if (tool == _tool) return;
    setState(() {
      if (!_tool.selects && _tool != CanvasTool.hand) _previousTool = _tool;
      _tool = tool;
    });
    // Al pasar a dibujar se suelta la selección, como en Notas.
    if (!tool.selects) _doc.clearSelection();
  }

  void _setColor(Color color) {
    setState(() => _color = color);
    if (_doc.recolorSelection(color)) HapticFeedback.selectionClick();
  }

  /// Doble toque / apretón del Apple Pencil según la preferencia del sistema.
  void _onPencilEvent(PencilEvent event) {
    if (!mounted) return;
    setState(() => _pencilDetected = true);
    if (event.gesture == PencilGesture.squeeze) {
      // Apretón: alterna entre seleccionar y la última herramienta de dibujo.
      _swapTool(_tool.selects ? _previousTool : CanvasTool.select);
      return;
    }
    switch (event.action) {
      case PencilAction.ignore || PencilAction.runSystemShortcut:
        return;
      case PencilAction.switchPrevious:
        _swapTool(_previousTool);
      case PencilAction.showColorPalette ||
          PencilAction.showInkAttributes ||
          PencilAction.showContextualPalette:
        final i = canvasColors.indexWhere((c) => c.$1 == _color);
        final next = canvasColors[(i + 1) % canvasColors.length];
        _setColor(next.$1);
        KraftToast.show(context, 'Color: ${next.$2}', icon: Symbols.palette);
      case PencilAction.switchEraser:
        _swapTool(
          _tool == CanvasTool.eraser ? _previousTool : CanvasTool.eraser,
        );
    }
  }

  void _swapTool(CanvasTool next) {
    final current = _tool;
    _setTool(next);
    if (next != current) setState(() => _previousTool = current);
    HapticFeedback.selectionClick();
    KraftToast.show(context, 'Herramienta: ${next.label}', icon: next.icon);
  }

  // ---- Vista ----

  /// Matriz que deja [world] en el centro del visor con la escala [scale].
  Matrix4 _viewCentering(Offset world, double scale) {
    final c = _viewportSize.center(Offset.zero);
    return Matrix4.identity()
      ..translateByDouble(
        c.dx - world.dx * scale,
        c.dy - world.dy * scale,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void _setView(Matrix4 m) =>
      _viewer.value = CanvasBounds.clampView(m, _viewportSize);

  void _animateView(Matrix4 target) {
    final bounded = CanvasBounds.clampView(target, _viewportSize);
    if (KraftMotion.reduced(context)) {
      _viewer.value = bounded;
      return;
    }
    _viewTween = Matrix4Tween(begin: _viewer.value.clone(), end: bounded);
    _viewAnimation.forward(from: 0);
  }

  /// Centra y encuadra todo el contenido (sin ampliar más allá del 100 %).
  void _fitContent({bool animate = true}) {
    final bounds = _doc.contentBounds;
    var scale = 1.0;
    var center = Offset.zero;
    if (bounds != null) {
      center = bounds.center;
      final fit = math.min(
        _viewportSize.width * 0.8 / bounds.width,
        _viewportSize.height * 0.7 / bounds.height,
      );
      scale = fit.clamp(CanvasInputLayer.minScale, 1.0);
    }
    final target = _viewCentering(center, scale);
    animate ? _animateView(target) : _viewer.value = target;
  }

  void _centerOn(Offset world, {required bool animate}) {
    final target = _viewCentering(world, _viewer.value.getMaxScaleOnAxis());
    if (animate) {
      _animateView(target);
    } else {
      _viewAnimation.stop();
      _setView(target);
    }
  }

  // ---- Zoom con botones ----

  void _zoomBy(double factor) {
    final current = _viewer.value.getMaxScaleOnAxis();
    final target = (current * factor).clamp(
      CanvasInputLayer.minScale,
      CanvasInputLayer.maxScale,
    );
    final f = target / current;
    final focal = _viewer.toScene(_viewportSize.center(Offset.zero));
    _setView(
      _viewer.value.clone()
        ..translateByDouble(focal.dx, focal.dy, 0, 1)
        ..scaleByDouble(f, f, 1, 1)
        ..translateByDouble(-focal.dx, -focal.dy, 0, 1),
    );
  }

  // ---- Texto ----

  Future<void> _editItem(CanvasItem item) async {
    if (item.type.editsInline) {
      _startEditing(item);
      return;
    }
    if (item.type == CanvasItemType.link) {
      await _openLink(item);
      return;
    }
    final result = await showItemEditor(context, item);
    switch (result) {
      case ItemEdited(:final item):
        _doc.updateItem(item);
      case ItemDeleted():
        _doc
          ..selectOnly(CanvasHit.item(item.id))
          ..deleteSelection();
      case null:
        break;
    }
  }

  // ---- Bloques de texto (escribir en el sitio) ----

  String? _editingDraft;

  void _startEditing(CanvasItem item, {bool isNew = false}) {
    if (_editingId != null) _finishEditing();
    _doc.clearSelection();
    setState(() {
      _editingId = item.id;
      _editingIsNew = isNew;
      _editingDraft = null;
    });
  }

  void _finishEditing() {
    final id = _editingId;
    if (id == null) return;
    final draft = _editingDraft;
    final wasNew = _editingIsNew;
    setState(() {
      _editingId = null;
      _editingDraft = null;
      _editingIsNew = false;
    });
    _focus.requestFocus();
    final item = _doc.itemById(id);
    if (item == null) return;
    if ((draft ?? item.title).trim().isEmpty && wasNew) {
      _doc.removeByIds({id});
      return;
    }
    _applyText(item, draft ?? item.title);
  }

  /// Guarda lo escrito sin cerrar el campo (antes de guardar la nota o el lienzo).
  void _commitDraft() {
    final id = _editingId, draft = _editingDraft;
    final item = id == null ? null : _doc.itemById(id);
    if (item == null || draft == null) return;
    _editingDraft = null;
    if (draft.trim().isNotEmpty) _editingIsNew = false;
    _applyText(item, draft);
  }

  void _applyText(CanvasItem item, String text) {
    if (item.type == CanvasItemType.checklist) {
      text = text.split('\n').where((l) => l.trim().isNotEmpty).join('\n');
    }
    if (text == item.title) return;
    // Las casillas marcadas siguen a su texto aunque cambie el orden de las líneas.
    final done = {
      for (final (line, checked) in item.checklistLines)
        if (checked) line,
    };
    _doc.updateItem(
      item.copyWith(
        title: text,
        checks: item.type == CanvasItemType.checklist
            ? [for (final line in text.split('\n')) done.contains(line)]
            : null,
      ),
    );
  }

  bool _isInsideEditor(Offset board) {
    final id = _editingId;
    final item = id == null ? null : _doc.itemById(id);
    return item != null && _doc.itemRect(item).inflate(12).contains(board);
  }

  /// Marcar una casilla de checklist al tocarla.
  bool _onTapItem(CanvasItem item, Offset board) {
    final row = TextBlocks.checkboxAt(
      item,
      board - _doc.itemRect(item).topLeft,
    );
    if (row == null) return false;
    final lines = item.checklistLines;
    _doc
      ..updateItem(
        item.copyWith(
          checks: [
            for (final (i, (_, done)) in lines.indexed) i == row ? !done : done,
          ],
        ),
      )
      ..clearSelection();
    HapticFeedback.selectionClick();
    return true;
  }

  // ---- Enlaces a lienzos y notas ----

  Future<void> _addLink() async {
    final picked = await showLinkPicker(
      context,
      exclude: 'canvas:${widget.canvasId}',
    );
    if (picked == null || !mounted) return;
    final center = _viewer.toScene(_viewportSize.center(Offset.zero));
    final size = TextBlocks.linkSize;
    final position = center - Offset(size.width / 2, size.height / 2);
    _doc.addItem(
      CanvasItem(
        id: 'template',
        type: CanvasItemType.link,
        position: position,
        title: picked.title,
        target: picked.target,
      ),
    );
    HapticFeedback.lightImpact();
  }

  Future<void> _openLink(CanvasItem item) async {
    final target = item.target ?? '';
    final id = int.tryParse(target.split(':').last);
    if (id == null) return;
    await _save();
    if (!mounted) return;
    context.push(
      target.startsWith('note:')
          ? Routes.noteEditor(id)
          : Routes.canvasEditor(id),
    );
  }

  // ---- Galería y menú radial ----

  CanvasItem _insert(ElementTemplate template, Offset world) {
    final item = _doc.addItem(template.placeAt(world));
    HapticFeedback.lightImpact();
    // Con herramientas de dibujo no hay barra de selección: se suelta para no confundir.
    if (!_tool.selects) _doc.clearSelection();
    if (item.type.editsInline && item.title.isEmpty)
      _startEditing(item, isNew: true);
    return item;
  }

  void _insertAtCenter(ElementTemplate template) {
    _insert(template, _viewer.toScene(_viewportSize.center(Offset.zero)));
    setState(() {
      _galleryOpen = false;
      _gallerySearchFocused = false;
    });
  }

  void _dropTemplate(ElementTemplate template, Offset globalPointer) {
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(globalPointer);
    if (!(Offset.zero & box.size).contains(local)) return;
    _insert(template, _viewer.toScene(local));
  }

  bool _onHold(Offset local, Offset world) {
    setState(() {
      _galleryOpen = false;
      _gallerySearchFocused = false;
    });
    _radial.value = RadialMenuState(
      center: RadialMenu.clampCenter(local, _viewportSize),
      world: world,
    );
    return true;
  }

  void _onHoldMove(Offset local) {
    final state = _radial.value;
    if (state == null) return;
    final index = RadialMenu.indexAt(state.center, local);
    if (index != state.hovered) {
      if (index != null) HapticFeedback.selectionClick();
      _radial.value = index == null
          ? state.copyWith(clearHovered: true)
          : state.copyWith(hovered: index);
    }
  }

  void _onHoldEnd(Offset? local) {
    final state = _radial.value;
    if (state == null) return;
    final index = local == null
        ? null
        : RadialMenu.indexAt(state.center, local);
    if (index != null) {
      _chooseRadial(index);
    } else if (local == null) {
      _radial.value = null;
    } else {
      // Soltó en el centro: la rueda queda abierta para elegir con un toque.
      _radial.value = state.copyWith(held: false, clearHovered: true);
    }
  }

  void _chooseRadial(int index) {
    final state = _radial.value;
    if (state == null) return;
    _radial.value = null;
    final from = _pendingLinkFrom;
    _pendingLinkFrom = null;
    _doc.batch(() {
      final item = _insert(radialOptions[index].template, state.world);
      if (from != null) _doc.addLink(from, item.id);
    });
  }

  void _dismissRadial() {
    _radial.value = null;
    _pendingLinkFrom = null;
  }

  Future<void> _editTitle() async {
    final text = await _promptText(context, 'Nombre del lienzo', _title);
    if (text != null && text.isNotEmpty) setState(() => _title = text);
  }

  KeyEventResult _onCanvasKey(FocusNode _, KeyEvent event) {
    // Los campos de texto (incluido Buscar elementos) conservan todas sus
    // teclas. Sólo el lienzo con foco directo recibe atajos globales.
    if (event is! KeyDownEvent ||
        FocusManager.instance.primaryFocus != _focus ||
        _editingId != null ||
        _galleryOpen ||
        _gallerySearchFocused) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final command =
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (command) {
      if (key == LogicalKeyboardKey.keyA) {
        _setTool(CanvasTool.select);
        _doc.selectAll();
      } else if (key == LogicalKeyboardKey.keyD) {
        _doc.duplicateSelection();
      } else if (key == LogicalKeyboardKey.keyZ) {
        shift ? _doc.redo() : _doc.undo();
      } else if (key == LogicalKeyboardKey.equal) {
        _zoomBy(1.25);
      } else if (key == LogicalKeyboardKey.minus) {
        _zoomBy(0.8);
      } else if (key == LogicalKeyboardKey.digit0) {
        _fitContent();
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      _doc.deleteSelection();
    } else if (key == LogicalKeyboardKey.escape) {
      _doc.clearSelection();
    } else if (key == LogicalKeyboardKey.slash && shift) {
      _showShortcuts();
    } else if (canvasToolKeys.entries
            .where((entry) => entry.value == key)
            .firstOrNull
        case final entry?) {
      _setTool(
        CanvasTool.values.firstWhere((tool) => tool.shortcut == entry.key),
      );
    } else {
      final index = canvasNumberKeys.indexOf(key);
      if (index < 0) return KeyEventResult.ignored;
      setState(() => _strokeWidth = canvasStrokeWidths[index]);
    }
    return KeyEventResult.handled;
  }

  // ---- UI ----

  String get _hint {
    if (_tapConnectFrom != null) return 'Toca el elemento que quieres conectar';
    if (_editingId != null)
      return 'Escribe con el teclado o a mano con el lápiz · Toca fuera para terminar';
    final finger = _fingerDraws ? '' : ' · Dedo: tocar, mover y editar';
    return switch (_tool) {
      CanvasTool.select => 'Lápiz: toca o arrastra un recuadro$finger',
      CanvasTool.lasso => 'Lápiz: rodea lo que quieras seleccionar$finger',
      CanvasTool.hand => 'Arrastra para mover el lienzo',
      CanvasTool.eraser =>
        'Borrador ${_eraserMode.label.toLowerCase()}: ${_eraserMode.description.toLowerCase()}',
      _ when _tool.draws =>
        _fingerDraws
            ? 'Dibuja con el lápiz o el dedo'
            : 'Dibuja con el lápiz$finger',
      _ => 'Toca el lienzo para colocar',
    };
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    // El modo lienzo vive fuera de las pestañas (navegador raíz): necesita su propio Scaffold,
    // si no el fondo queda negro y los textos sin tema de Material.
    return Scaffold(
      backgroundColor: KraftColors.surface,
      resizeToAvoidBottomInset: false,
      body: _load != _LoadState.ready
          ? _buildPlaceholder()
          : PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) _saveAndExit();
              },
              child: _buildEditor(),
            ),
    );
  }

  Widget _buildPlaceholder() {
    return ColoredBox(
      color: KraftColors.surface,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: InfiniteDotGridPainter(_viewer)),
          ),
          Center(
            child: _load == _LoadState.loading
                ? CircularProgressIndicator(color: KraftColors.ink)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Este lienzo ya no existe',
                        style: KraftText.headlineSm,
                      ),
                      const SizedBox(height: KraftSpace.md),
                      TextButton(
                        onPressed: () => context.go(Routes.canvas),
                        child: const Text('Volver a lienzos'),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Chuleta de atajos: se abre con "?" o desde la barra superior.
  void _showShortcuts() {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: NeoBox(
            shadow: 5,
            radius: KraftRadius.lg,
            padding: const EdgeInsets.all(KraftSpace.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Symbols.keyboard, size: 20),
                    const SizedBox(width: KraftSpace.sm),
                    Expanded(
                      child: Text(
                        'ATAJOS DEL LIENZO',
                        style: KraftText.techBadge.copyWith(letterSpacing: 1),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Symbols.close, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: KraftSpace.sm),
                for (final (keys, what) in [
                  for (final tool in CanvasTool.values)
                    (tool.shortcut, tool.label),
                  ('1 2 3', 'Grosor del trazo'),
                  ('⌘Z / ⇧⌘Z', 'Deshacer y rehacer'),
                  ('⌘A', 'Seleccionar todo'),
                  ('⌘D', 'Duplicar la selección'),
                  ('⌫', 'Borrar la selección'),
                  ('Esc', 'Quitar la selección'),
                  ('⌘+ / ⌘−', 'Acercar y alejar'),
                  ('⌘0', 'Encajar el contenido'),
                  ('?', 'Esta ayuda'),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 92,
                          child: Text(
                            keys,
                            style: KraftText.labelCode.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(child: Text(what, style: KraftText.bodySm)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditor() {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onCanvasKey,
      child: Column(
        children: [
          ListenableBuilder(
            listenable: _doc,
            builder: (context, _) => _CanvasTopBar(
              title: _title.isEmpty ? _titleToSave : _title,
              onBack: _saveAndExit,
              onLink: _addLink,
              viewer: _viewer,
              canUndo: _doc.canUndo,
              canRedo: _doc.canRedo,
              onEditTitle: _editTitle,
              onZoomIn: () => _zoomBy(1.25),
              onZoomOut: () => _zoomBy(0.8),
              onFit: _fitContent,
              onUndo: _doc.undo,
              onRedo: _doc.redo,
              onShare: () => KraftToast.show(
                context,
                'Compartir estará disponible próximamente',
                icon: Symbols.schedule,
              ),
              onShortcuts: _showShortcuts,
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _viewportSize = constraints.biggest;
                if (!_viewReady && !_viewportSize.isEmpty) {
                  // Primer fotograma: se centra el contenido antes de mostrar el lienzo.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted || _viewReady) return;
                    final saved = _initialData;
                    if (saved?.viewCenter != null) {
                      // Se reabre donde se dejó.
                      _userMovedView = true;
                      _setView(
                        _viewCentering(
                          saved!.viewCenter!,
                          saved.viewScale ?? 1,
                        ),
                      );
                    } else {
                      _fitContent(animate: false);
                    }
                    setState(() => _viewReady = true);
                    // Dos fotogramas después los elementos ya informaron su tamaño real: se reencuadra
                    // con esas medidas, salvo que el usuario ya haya tocado el lienzo.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && !_userMovedView)
                          _fitContent(animate: false);
                      });
                    });
                  });
                }
                return Stack(
                  children: [
                    Positioned.fill(child: _buildViewport()),
                    if (_editingId != null)
                      Positioned.fill(child: _buildInlineEditor()),
                    Positioned.fill(child: _buildSelectionToolbar()),
                    Positioned(
                      top: KraftSpace.sm,
                      left: KraftSpace.md,
                      right:
                          KraftSpace.md +
                          (_minimapExpanded
                              ? CanvasMinimap.mapSize.width + 16
                              : 100),
                      child: IgnorePointer(
                        child: _StatusRow(
                          pencilDetected: _pencilDetected,
                          hint: _hint,
                          live: _live,
                        ),
                      ),
                    ),
                    Positioned(
                      top: KraftSpace.sm,
                      right: KraftSpace.md,
                      child: CanvasMinimap(
                        document: _doc,
                        viewer: _viewer,
                        viewportSize: _viewportSize,
                        expanded: _minimapExpanded,
                        onExpandedChanged: (v) =>
                            setState(() => _minimapExpanded = v),
                        onJump: (world) => _centerOn(world, animate: true),
                        onDrag: (world) => _centerOn(world, animate: false),
                      ),
                    ),
                    Positioned.fill(child: _buildFloatingPalette()),
                    if (_galleryOpen) _buildGallery(),
                    Positioned.fill(
                      child: ValueListenableBuilder(
                        valueListenable: _radial,
                        builder: (context, state, _) => state == null
                            ? const SizedBox.shrink()
                            : RadialMenu(
                                state: state,
                                onSelect: _chooseRadial,
                                onDismiss: _dismissRadial,
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewport() {
    return DragTarget<ElementTemplate>(
      onAcceptWithDetails: (details) =>
          _dropTemplate(details.data, details.offset),
      builder: (context, candidates, _) => ClipRect(
        key: _viewportKey,
        child: CanvasInputLayer(
          document: _doc,
          viewer: _viewer,
          live: _live,
          lasso: _lasso,
          tool: _tool,
          color: _color,
          strokeWidth: _strokeWidth,
          pressureEnabled: _pressureEnabled,
          fingerDraws: _fingerDraws,
          eraserMode: _eraserMode,
          onPencilDetected: () {
            if (!_pencilDetected) setState(() => _pencilDetected = true);
          },
          onEditItem: _editItem,
          onPlaced: () => _setTool(CanvasTool.select),
          ignoreAt: _isInsideEditor,
          onTapItem: _onTapItem,
          onGestureStart: () {
            // Tocar fuera del bloque que se escribe lo termina.
            if (_editingId != null)
              FocusManager.instance.primaryFocus?.unfocus();
            _userMovedView = true;
            if (!_galleryOpen && _editingId == null) _focus.requestFocus();
            _viewAnimation.stop();
            if (_galleryOpen) {
              setState(() {
                _galleryOpen = false;
                _gallerySearchFocused = false;
              });
            }
          },
          onHold: _onHold,
          onHoldMove: _onHoldMove,
          onHoldEnd: _onHoldEnd,
          child: Stack(
            children: [
              // Los puntos se pintan en pantalla: el fondo no se acaba nunca.
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(painter: InfiniteDotGridPainter(_viewer)),
                ),
              ),
              if (_viewReady)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _viewer,
                    builder: (context, board) =>
                        Transform(transform: _viewer.value, child: board),
                    // El tablero no tiene tamaño: el contenido vive en coordenadas del lienzo, positivas o negativas.
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox.shrink(child: _buildBoard()),
                    ),
                  ),
                ),
              // Resalte mientras se arrastra un elemento desde la galería.
              if (candidates.isNotEmpty)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: KraftColors.primaryContainer.withValues(
                          alpha: 0.08,
                        ),
                        border: Border.all(
                          color: KraftColors.primaryContainer,
                          width: 4,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Paleta flotante y galería ----

  /// Márgenes de la paleta: arriba deja libre la barra de estado y, a la derecha, el minimapa.
  EdgeInsets get _paletteInsets => EdgeInsets.fromLTRB(
    KraftSpace.md,
    _dock.isRight ? (_minimapExpanded ? 196 : 64) : 56,
    KraftSpace.md,
    KraftSpace.md,
  );

  Widget _buildFloatingPalette() {
    return FloatingPalette(
      collapsed: _paletteCollapsed,
      dock: _dock,
      insets: _paletteInsets,
      onExpand: () => setState(() => _paletteCollapsed = false),
      onPaletteSize: (size) {
        if (size != _paletteSize) setState(() => _paletteSize = size);
      },
      onDockChanged: (dock) => setState(() {
        _dock = dock;
        if (dock != PaletteDock.bottomCenter) _lastCornerDock = dock;
      }),
      bubble: Stack(
        alignment: Alignment.center,
        children: [
          Icon(_tool.icon, size: 26, color: KraftColors.ink),
          Positioned(
            right: 10,
            bottom: 10,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: _color,
                shape: BoxShape.circle,
                border: Border.all(color: KraftColors.ink, width: 1.5),
              ),
            ),
          ),
        ],
      ),
      palette: ToolPalette(
        tool: _tool,
        strokeWidth: _strokeWidth,
        color: _color,
        pressureEnabled: _pressureEnabled,
        fingerDraws: _fingerDraws,
        onFingerDrawsChanged: _setFingerDraws,
        eraserMode: _eraserMode,
        onEraserMode: _setEraserMode,
        libraryOpen: _galleryOpen,
        vertical: _dock.isVertical,
        toolsFirst: !_dock.isRight,
        sideAlignment: switch (_dock.alignment.y) {
          < 0 => CrossAxisAlignment.start,
          > 0 => CrossAxisAlignment.end,
          _ => CrossAxisAlignment.center,
        },
        onPressureChanged: (v) => setState(() => _pressureEnabled = v),
        onTool: _setTool,
        onStrokeWidth: (w) => setState(() => _strokeWidth = w),
        onColor: _setColor,
        onOpenLibrary: () => setState(() {
          _galleryOpen = !_galleryOpen;
          if (!_galleryOpen) _gallerySearchFocused = false;
        }),
        onCollapse: () => setState(() {
          _galleryOpen = false;
          _gallerySearchFocused = false;
          _paletteCollapsed = true;
          if (_dock == PaletteDock.bottomCenter) _dock = _lastCornerDock;
        }),
      ),
    );
  }

  /// La galería se despliega pegada a la paleta: encima si está abajo en horizontal, al lado si está en vertical.
  Widget _buildGallery() {
    const gap = 10.0;
    final inset = _paletteInsets;
    final palette =
        _paletteSize ??
        (_dock.isVertical ? const Size(130, 560) : const Size(640, 128));
    final gallery = SelectionPop(
      child: ElementGallery(
        onInsert: _insertAtCenter,
        onDragStarted: () => setState(() {
          _galleryOpen = false;
          _gallerySearchFocused = false;
        }),
        onClose: () => setState(() {
          _galleryOpen = false;
          _gallerySearchFocused = false;
        }),
        onSearchFocusChanged: (focused) {
          if (mounted) setState(() => _gallerySearchFocused = focused);
        },
      ),
    );
    if (!_dock.isVertical) {
      return Positioned(
        left: inset.left,
        right: inset.right,
        bottom: inset.bottom + palette.height + gap,
        child: Align(alignment: Alignment.bottomCenter, child: gallery),
      );
    }
    return Positioned(
      left: inset.left + (_dock.isLeft ? palette.width + gap : 0),
      right: inset.right + (_dock.isRight ? palette.width + gap : 0),
      top: inset.top,
      bottom: inset.bottom,
      child: Align(alignment: _dock.alignment, child: gallery),
    );
  }

  /// Campo de texto sobre el bloque que se escribe. Va en pantalla (no dentro del tablero sin tamaño)
  /// para que reciba toques: cursor, selección de texto y Scribble.
  Widget _buildInlineEditor() {
    return AnimatedBuilder(
      animation: Listenable.merge([_viewer, _doc]),
      builder: (context, _) {
        final id = _editingId;
        final item = id == null ? null : _doc.itemById(id);
        if (item == null) return const SizedBox.shrink();
        final origin = MatrixUtils.transformPoint(_viewer.value, item.position);
        return Stack(
          children: [
            Positioned(
              left: origin.dx,
              top: origin.dy,
              child: Transform.scale(
                scale: _viewer.value.getMaxScaleOnAxis(),
                alignment: Alignment.topLeft,
                child: SizeReporter(
                  onSize: (size) => _doc.reportItemSize(item.id, size),
                  child: InlineBlockEditor(
                    key: ValueKey('editor-${item.id}'),
                    item: item,
                    onChanged: (text) => _editingDraft = text,
                    onDone: _finishEditing,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBoard() {
    return SizedBox.shrink(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ListenableBuilder(
              listenable: _doc,
              builder: (context, _) => Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: ValueListenableBuilder(
                      valueListenable: _viewer,
                      builder: (context, matrix, _) => CustomPaint(
                        painter: LinksPainter(
                          _doc,
                          scale: matrix.getMaxScaleOnAxis(),
                        ),
                      ),
                    ),
                  ),
                  // Mientras se arrastra, lo seleccionado se pinta encima (al soltar pasa al frente de verdad).
                  for (final (i, item) in [
                    // El bloque que se escribe se pinta encima, como campo de texto (ver _buildInlineEditor).
                    for (final it in _doc.itemsInPaintOrder)
                      if (it.id != _editingId &&
                          (!_doc.isMoving || !_doc.isItemSelected(it.id)))
                        it,
                    if (_doc.isMoving)
                      for (final it in _doc.itemsInPaintOrder)
                        if (_doc.isItemSelected(it.id)) it,
                  ].indexed)
                    Positioned(
                      key: ValueKey(item.id),
                      left: _doc.itemRect(item).left,
                      top: _doc.itemRect(item).top,
                      child: SizeReporter(
                        onSize: (size) => _doc.reportItemSize(item.id, size),
                        child: Entrance(
                          index:
                              item.id.startsWith('node') ||
                                  item.id.startsWith('sticky') ||
                                  item.id.startsWith('wire')
                              ? i
                              : 0,
                          offset: const Offset(0, -18),
                          scale: 0.92,
                          child: CanvasItemView(item: item),
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: StrokesPainter(
                          strokes: _doc.strokes,
                          selected: _doc.selectedStrokeIds,
                          moveOffset: _doc.moveOffset,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: LiveStrokePainter(_live)),
            ),
          ),
          Positioned.fill(
            child: ValueListenableBuilder(
              valueListenable: _viewer,
              builder: (context, matrix, _) {
                final scale = matrix.getMaxScaleOnAxis();
                return Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: SelectionPainter(_doc, scale: scale),
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: LassoPainter(_lasso, scale: scale),
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: ConnectorPreviewPainter(
                          _doc,
                          _connect,
                          scale: scale,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Barra de acciones anclada encima de la selección, en coordenadas de pantalla.
  Widget _buildSelectionToolbar() {
    return ListenableBuilder(
      listenable: Listenable.merge([_doc, _viewer, _lasso, _connect]),
      builder: (context, _) {
        // También con herramientas de dibujo: el dedo selecciona y edita mientras el lápiz dibuja.
        if (_doc.isMoving || _lasso.isActive) return const SizedBox.shrink();
        const toolbarHeight = 50.0;
        double toolbarTop(Rect screen) {
          // Encima de la selección; si no cabe, debajo.
          var top = screen.top - toolbarHeight - 16;
          if (top < 56) top = screen.bottom + 16;
          return top.clamp(
            56.0,
            (_viewportSize.height - toolbarHeight - 140).clamp(
              56.0,
              double.infinity,
            ),
          );
        }

        Alignment horizontal(double x) => Alignment(
          _viewportSize.width == 0
              ? 0
              : ((x / _viewportSize.width) * 2 - 1).clamp(-0.9, 0.9),
          0,
        );

        final link = _doc.selectedLink;
        final linkGeometry = link == null ? null : _doc.linkGeometry(link);
        if (link != null && linkGeometry != null) {
          final mid = MatrixUtils.transformPoint(
            _viewer.value,
            linkGeometry.mid,
          );
          final bend = MatrixUtils.transformPoint(
            _viewer.value,
            linkGeometry.control ?? linkGeometry.mid,
          );
          final label = MatrixUtils.transformPoint(
            _viewer.value,
            linkGeometry.mid + link.labelOffset,
          );
          return Stack(
            children: [
              // La etiqueta se arrastra directamente; el pequeño tirador encima
              // deja ajustar el recorrido sin confundir ambos gestos.
              Positioned(
                left: label.dx - 80,
                top: label.dy - 18,
                width: 160,
                height: 36,
                child: _LinkDragTarget(
                  tooltip: 'Arrastra la etiqueta',
                  onStart: () => _doc.beginLinkLabelMove(link.id),
                  onUpdate: (global) => _moveLinkLabel(link, global),
                  onEnd: _doc.endLinkLabelMove,
                  onCancel: () => _doc.endLinkLabelMove(cancel: true),
                ),
              ),
              Positioned(
                left: bend.dx - 16,
                top: bend.dy - 48,
                child: _LinkRouteHandle(
                  onStart: () => _doc.beginLinkBend(link.id),
                  onUpdate: (global) => _moveLinkBend(link, global),
                  onEnd: _doc.endLinkBend,
                  onCancel: () => _doc.endLinkBend(cancel: true),
                ),
              ),
              Positioned(
                top: toolbarTop(
                  Rect.fromCenter(center: mid, width: 1, height: 24),
                ),
                left: 0,
                right: 0,
                child: Align(
                  alignment: horizontal(mid.dx),
                  child: SelectionPop(
                    key: ValueKey(link.id),
                    child: LinkToolbar(
                      link: link,
                      onLabel: () => _editLinkLabel(link),
                      onChanged: _doc.updateLink,
                      onDelete: () {
                        _doc.deleteSelection();
                        HapticFeedback.mediumImpact();
                        KraftToast.show(
                          context,
                          'Conexión borrada',
                          icon: Symbols.delete,
                          actionLabel: 'Deshacer',
                          onAction: _doc.undo,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        final bounds = _doc.selectionBounds;
        if (bounds == null) return const SizedBox.shrink();
        final screen = MatrixUtils.transformRect(_viewer.value, bounds);
        final single = _doc.singleSelectedItem;
        final resizeItem = single ?? _doc.selectedFrameForResize;
        final resizeScreen = resizeItem == null
            ? null
            : MatrixUtils.transformRect(
                _viewer.value,
                _doc.itemRect(resizeItem),
              );
        final top = toolbarTop(screen);
        final dragging = _connect.value != null;

        // El tirador va a la derecha del elemento; si no cabe, a la izquierda.
        const knob = ConnectorKnob.size;
        final knobRight = screen.right + 14 + knob < _viewportSize.width - 8;
        final knobLeft = knobRight
            ? screen.right + 14
            : screen.left - 14 - knob;

        return Stack(
          children: [
            if (resizeItem != null && resizeScreen != null)
              Positioned(
                left: resizeScreen.right - 14,
                top: resizeScreen.bottom - 14,
                child: _ResizeHandle(
                  document: _doc,
                  item: resizeItem,
                  extent: resizeScreen.size,
                ),
              ),
            if (single != null)
              Positioned(
                left: knobLeft,
                top: (screen.center.dy - knob / 2).clamp(
                  8.0,
                  math.max(8.0, _viewportSize.height - knob - 8),
                ),
                child: AnimatedOpacity(
                  opacity: dragging ? 0.4 : 1,
                  duration: KraftMotion.of(context, KraftMotion.fast),
                  child: SelectionPop(
                    key: ValueKey('knob-${single.id}'),
                    child: ConnectorKnob(
                      active: _tapConnectFrom == single.id,
                      onTap: () => setState(
                        () => _tapConnectFrom = _tapConnectFrom == single.id
                            ? null
                            : single.id,
                      ),
                      onDragStart: (g) => _connectStart(single.id, g),
                      onDragUpdate: _connectUpdate,
                      onDragEnd: _connectEnd,
                      onDragCancel: () => _connect.value = null,
                    ),
                  ),
                ),
              ),
            if (!dragging)
              Positioned(
                top: top,
                left: 0,
                right: 0,
                child: Align(
                  alignment: horizontal(screen.center.dx),
                  child: SelectionPop(
                    key: ValueKey(
                      Object.hashAll([
                        ..._doc.selectedItemIds,
                        ..._doc.selectedStrokeIds,
                      ]),
                    ),
                    child: SelectionToolbar(
                      onGroup: _doc.selectionCount > 1
                          ? _doc.groupSelection
                          : null,
                      onUngroup: _doc.canUngroup ? _doc.ungroupSelection : null,
                      count: _doc.selectionCount,
                      hasStrokes: _doc.selectedStrokeIds.isNotEmpty,
                      canEdit: single != null && single.editable,
                      canOpenTarget: single?.target != null,
                      onOpenTarget: single == null
                          ? null
                          : () => _openLink(single),
                      blockStyle: single?.type == CanvasItemType.paragraph
                          ? single!.block
                          : null,
                      onBlockStyle: (style) => single == null
                          ? null
                          : _doc.updateItem(single.copyWith(block: style)),
                      scale:
                          single == null ||
                              single.type == CanvasItemType.frame ||
                              single.type == CanvasItemType.paragraph ||
                              single.type == CanvasItemType.checklist
                          ? null
                          : single.scale,
                      onScale: single == null
                          ? null
                          : (scale) =>
                                _doc.updateItem(single.copyWith(scale: scale)),
                      color: _color,
                      onEdit: () => single == null ? null : _editItem(single),
                      onDuplicate: _doc.duplicateSelection,
                      onFront: _doc.bringSelectionToFront,
                      onRecolor: () => _doc.recolorSelection(_color),
                      onDelete: () {
                        final n = _doc.selectionCount;
                        _doc.deleteSelection();
                        HapticFeedback.mediumImpact();
                        KraftToast.show(
                          context,
                          n == 1 ? 'Elemento borrado' : '$n elementos borrados',
                          icon: Symbols.delete,
                          actionLabel: 'Deshacer',
                          onAction: _doc.undo,
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

Future<String?> _promptText(
  BuildContext context,
  String title,
  String initial,
) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextPromptDialog(title: title, initial: initial),
  );
}

/// El diálogo es dueño de su controlador: se libera cuando el diálogo sale del árbol,
/// no al cerrarse, porque el campo sigue visible durante la animación de salida.
class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return AlertDialog(
      backgroundColor: KraftColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KraftRadius.lg),
        side: BorderSide(color: KraftColors.ink, width: 2),
      ),
      title: Text(widget.title, style: KraftText.headlineSm),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: null,
        style: KraftText.bodyLg,
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: KraftColors.primaryContainer,
            foregroundColor: KraftColors.onSurface,
          ),
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _CanvasTopBar extends StatelessWidget {
  const _CanvasTopBar({
    required this.title,
    required this.onBack,
    required this.viewer,
    required this.canUndo,
    required this.canRedo,
    required this.onEditTitle,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
    required this.onUndo,
    required this.onRedo,
    required this.onShare,
    required this.onLink,
    required this.onShortcuts,
  });

  final String title;

  /// Guarda y sale del modo lienzo.
  final VoidCallback onBack;

  /// El porcentaje escucha al controlador: el pellizco no reconstruye la pantalla.
  final TransformationController viewer;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onEditTitle;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onShare;

  /// Abre la chuleta de atajos de teclado.
  final VoidCallback onShortcuts;

  /// Añade un enlace a otro lienzo o nota.
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return KraftTopBar(
      leading: Row(
        children: [
          Tooltip(
            message: 'Guardar y salir',
            child: Semantics(
              button: true,
              label: 'Guardar y salir',
              child: GestureDetector(
                onTap: onBack,
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.only(left: 8, right: 12),
                  decoration: BoxDecoration(
                    color: KraftColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(KraftRadius.md),
                    border: KraftBorder.ink(),
                    boxShadow: KraftShadow.hard(2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Symbols.arrow_back, size: 20),
                      const SizedBox(width: 6),
                      Text(
                        'SALIR',
                        style: KraftText.labelCode.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: 1,
            height: 20,
            margin: const EdgeInsets.symmetric(horizontal: KraftSpace.sm + 4),
            color: KraftColors.outlineVariant,
          ),
          Flexible(
            child: _BarChip(
              onTap: onEditTitle,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Symbols.edit_note,
                    size: 16,
                    color: KraftColors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: KraftText.headlineSm.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Symbols.edit,
                    size: 14,
                    color: KraftColors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        const AiConnectButton(),
        _BarChip(
          child: Row(
            children: [
              _SmallIconButton(
                icon: Symbols.remove,
                tooltip: 'Alejar',
                onTap: onZoomOut,
              ),
              SizedBox(
                width: 52,
                child: ValueListenableBuilder(
                  valueListenable: viewer,
                  builder: (_, matrix, _) => Text(
                    '${(matrix.getMaxScaleOnAxis() * 100).round()}%',
                    textAlign: TextAlign.center,
                    style: KraftText.labelCode.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              _SmallIconButton(
                icon: Symbols.add,
                tooltip: 'Acercar',
                onTap: onZoomIn,
              ),
            ],
          ),
        ),
        _SquareButton(
          icon: Symbols.add_link,
          tooltip: 'Enlazar lienzo o nota',
          onTap: onLink,
        ),
        _SquareButton(
          icon: Symbols.fit_screen,
          tooltip: 'Centrar contenido  ·  \u2318 0',
          onTap: onFit,
        ),
        _SquareButton(
          icon: Symbols.keyboard,
          tooltip: 'Atajos de teclado  ·  ?',
          onTap: onShortcuts,
        ),
        Row(
          children: [
            _SquareButton(
              icon: Symbols.undo,
              tooltip: 'Deshacer',
              onTap: canUndo ? onUndo : null,
            ),
            const SizedBox(width: 4),
            _SquareButton(
              icon: Symbols.redo,
              tooltip: 'Rehacer',
              onTap: canRedo ? onRedo : null,
            ),
          ],
        ),
        GestureDetector(
          onTap: onShare,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: KraftColors.primaryContainer,
              borderRadius: BorderRadius.circular(KraftRadius.md),
              border: Border.all(color: KraftColors.ink),
              boxShadow: KraftShadow.hard(2),
            ),
            child: Row(
              children: [
                Icon(
                  Symbols.share,
                  size: 16,
                  color: KraftColors.onPrimaryContainer,
                ),
                const SizedBox(width: 6),
                Text(
                  'COMPARTIR',
                  style: KraftText.labelCode.copyWith(
                    color: KraftColors.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BarChip extends StatelessWidget {
  const _BarChip({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: KraftColors.surfaceContainer,
          borderRadius: BorderRadius.circular(KraftRadius.md),
          border: Border.all(color: KraftColors.ink.withValues(alpha: 0.1)),
        ),
        child: child,
      ),
    );
  }
}

class _SmallIconButton extends StatelessWidget {
  const _SmallIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      icon: Icon(icon, color: KraftColors.onSurface),
    );
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: KraftColors.surfaceContainer,
            borderRadius: BorderRadius.circular(KraftRadius.md),
            border: Border.all(color: KraftColors.ink.withValues(alpha: 0.1)),
          ),
          child: Icon(
            icon,
            size: 20,
            color: enabled
                ? KraftColors.onSurface
                : KraftColors.onSurface.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.pencilDetected,
    required this.hint,
    required this.live,
  });

  final bool pencilDetected;

  /// Mientras se dibuja con presión, el chip muestra un medidor en vivo.
  final LiveStroke live;

  /// Cómo usar la herramienta actual con lápiz y dedos.
  final String hint;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: KraftColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: KraftColors.ink.withValues(alpha: 0.15)),
            boxShadow: KraftShadow.hard(2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: pencilDetected
                      ? KraftColors.secondaryContainer
                      : KraftColors.outlineVariant,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                pencilDetected ? 'APPLE PENCIL ACTIVO' : 'MODO TÁCTIL',
                style: KraftText.techBadge.copyWith(letterSpacing: 1),
              ),
              _PressureMeter(live: live),
            ],
          ),
        ),
        const SizedBox(width: KraftSpace.sm),
        Flexible(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.centerLeft,
              children: [...previous, ?current],
            ),
            child: _FloatingChip(
              key: ValueKey(hint),
              icon: Symbols.info,
              label: hint,
              hardShadow: false,
            ),
          ),
        ),
      ],
    );
  }
}

class _FloatingChip extends StatelessWidget {
  const _FloatingChip({
    super.key,
    required this.icon,
    required this.label,
    this.hardShadow = true,
  });

  final IconData icon;
  final String label;
  final bool hardShadow;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: KraftColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(KraftRadius.md),
        border: Border.all(color: KraftColors.ink.withValues(alpha: 0.15)),
        boxShadow: hardShadow ? KraftShadow.hard(2) : KraftShadow.soft,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: KraftColors.secondary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: KraftText.labelCode.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Barra de presión en vivo: aparece sólo mientras se dibuja con un trazo que usa presión.
class _PressureMeter extends StatelessWidget {
  const _PressureMeter({required this.live});

  final LiveStroke live;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return ListenableBuilder(
      listenable: live,
      builder: (context, _) {
        final pressure = live.isActive ? live.pressure : null;
        return AnimatedSize(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: pressure == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 8,
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(
                          color: KraftColors.surfaceContainer,
                          border: Border.all(
                            color: KraftColors.ink,
                            width: 1.5,
                          ),
                        ),
                        child: FractionallySizedBox(
                          widthFactor: pressure,
                          child: Container(color: KraftColors.primaryContainer),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 34,
                        child: Text(
                          '${(pressure * 100).round()}%',
                          style: KraftText.techBadge,
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

enum _LoadState { loading, ready, missing }

class _LinkDragTarget extends StatelessWidget {
  const _LinkDragTarget({
    required this.tooltip,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  final String tooltip;
  final VoidCallback onStart;
  final ValueChanged<Offset> onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => onStart(),
      onPanUpdate: (details) => onUpdate(details.globalPosition),
      onPanEnd: (_) => onEnd(),
      onPanCancel: onCancel,
      child: const SizedBox.expand(),
    ),
  );
}

class _LinkRouteHandle extends StatelessWidget {
  const _LinkRouteHandle({
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  final VoidCallback onStart;
  final ValueChanged<Offset> onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Arrastra para ajustar el recorrido',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => onStart(),
      onPanUpdate: (details) => onUpdate(details.globalPosition),
      onPanEnd: (_) => onEnd(),
      onPanCancel: onCancel,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: KraftColors.primaryContainer,
          border: Border.all(color: KraftColors.border),
          borderRadius: BorderRadius.circular(16),
          boxShadow: KraftShadow.hard(2),
        ),
        child: Icon(
          Symbols.drag_indicator,
          size: 18,
          color: KraftColors.onPrimaryContainer,
        ),
      ),
    ),
  );
}

class _ResizeHandle extends StatefulWidget {
  const _ResizeHandle({
    required this.document,
    required this.item,
    required this.extent,
  });
  final CanvasDocument document;
  final CanvasItem item;
  final Size extent;
  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  Offset _delta = Offset.zero;
  Size _start = Size.zero;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Arrastra para cambiar el tamaño',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) {
        _delta = Offset.zero;
        _start = widget.extent;
        widget.document.beginResize(widget.item.id);
      },
      onPanUpdate: (d) {
        _delta += d.delta;
        final length =
            _start.width * _start.width + _start.height * _start.height;
        if (length > 0)
          widget.document.updateResize(
            1 + (_delta.dx * _start.width + _delta.dy * _start.height) / length,
          );
      },
      onPanEnd: (_) => widget.document.endResize(),
      onPanCancel: () => widget.document.endResize(cancel: true),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: KraftColors.primaryContainer,
          border: Border.all(color: KraftColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Symbols.open_in_full,
          size: 20,
          color: KraftColors.onPrimaryContainer,
        ),
      ),
    ),
  );
}
