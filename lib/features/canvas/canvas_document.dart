import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'canvas_items.dart';
import 'canvas_models.dart';
import 'connector_geometry.dart';

/// Estado del lienzo: elementos, trazos, selección e historial.
/// Todas las coordenadas son del lienzo (no de pantalla).
class CanvasDocument extends ChangeNotifier {
  CanvasDocument({
    List<CanvasItem>? items,
    List<Stroke> strokes = const [],
    List<CanvasLink>? links,
  }) : _items = items ?? CanvasSeed.items,
       _strokes = strokes,
       _links = links ?? (items == null ? CanvasSeed.links : const []) {
    // Los identificadores nuevos continúan tras los ya guardados.
    _nextStrokeId = strokes.fold(0, (m, s) => math.max(m, s.id)) + 1;
    _nextItemId =
        [
          ..._items.map((i) => i.id),
          ..._links.map((l) => l.id),
          ..._items.map((i) => i.group ?? ''),
          ..._strokes.map((s) => s.group ?? ''),
        ].fold(0, (m, id) => math.max(m, _numericSuffix(id))) +
        1;
  }

  static int _numericSuffix(String id) =>
      int.tryParse(RegExp(r'(\d+)$').firstMatch(id)?.group(1) ?? '') ?? 0;

  static const _historyLimit = 100;

  List<CanvasItem> _items;
  List<Stroke> _strokes;
  List<CanvasLink> _links;
  final _itemSizes = <String, Size>{};

  Set<String> _selectedItems = const {};
  Set<int> _selectedStrokes = const {};
  String? _selectedLink;
  Offset _moveOffset = Offset.zero;

  final _undo = <CanvasSnapshot>[];
  final _redo = <CanvasSnapshot>[];
  int _nextStrokeId = 1;
  int _nextItemId = 1;

  /// Sube con cada cambio de contenido (también al deshacer): sirve para saber si hay algo sin guardar.
  int _revision = 0;
  int get revision => _revision;

  List<CanvasItem> get items => _items;
  List<Stroke> get strokes => _strokes;

  /// Conexiones cuyos dos extremos siguen existiendo.
  /// Conexiones guardadas, incluidas las huérfanas, para revisión y reparación.
  /// Para pintar se usa [links], que solo contiene extremos existentes.
  List<CanvasLink> get allLinks => List.unmodifiable(_links);

  List<CanvasLink> get links {
    final ids = {for (final i in _items) i.id};
    return [
      for (final l in _links)
        if (ids.contains(l.from) && ids.contains(l.to)) l,
    ];
  }

  Set<String> get selectedItemIds => _selectedItems;
  Set<int> get selectedStrokeIds => _selectedStrokes;

  /// Elementos y trazos seleccionados (la conexión seleccionada va aparte: tiene su propia barra).
  int get selectionCount => _selectedItems.length + _selectedStrokes.length;
  bool get hasSelection => selectionCount > 0 || _selectedLink != null;

  CanvasLink? get selectedLink => _selectedLink == null
      ? null
      : links.where((l) => l.id == _selectedLink).firstOrNull;

  /// Desplazamiento provisional de la selección mientras se arrastra.
  Offset get moveOffset => _moveOffset;
  bool get isMoving => _moveOffset != Offset.zero;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  int allocateStrokeId() => _nextStrokeId++;

  bool isItemSelected(String id) => _selectedItems.contains(id);
  bool isStrokeSelected(int id) => _selectedStrokes.contains(id);

  CanvasItem? get singleSelectedItem =>
      _selectedStrokes.isEmpty && _selectedItems.length == 1
      ? _items.firstWhere((i) => i.id == _selectedItems.first)
      : null;

  /// Un marco puede estar seleccionado junto con los elementos que contiene,
  /// pero su tamaño debe cambiar de forma independiente de ese grupo.
  CanvasItem? get selectedFrameForResize {
    final frames = _items
        .where(
          (item) =>
              isItemSelected(item.id) && item.type == CanvasItemType.frame,
        )
        .toList();
    if (frames.length != 1) return null;
    final frame = frames.single;
    final group = frame.group;
    if (group == null) return null;
    final onlyItsGroup =
        _items
            .where((item) => isItemSelected(item.id) && item.id != frame.id)
            .every((item) => item.group == group) &&
        _strokes
            .where((stroke) => isStrokeSelected(stroke.id))
            .every((stroke) => stroke.group == group);
    return onlyItsGroup ? frame : null;
  }

  CanvasItem? itemById(String id) =>
      _items.where((i) => i.id == id).firstOrNull;

  // ---------------------------------------------------------------------------
  // Geometría
  // ---------------------------------------------------------------------------

  /// Guarda el tamaño real *sin zoom* tras maquetarse.
  ///
  /// El zoom de un elemento se aplica en [itemRect]. Mantener esta medida base
  /// evita que al arrastrar el tirador se vuelva a la estimación genérica (que
  /// no conoce la altura real de una tarjeta) y las flechas queden separadas.
  void reportItemSize(String id, Size size) {
    final item = itemById(id);
    if (item == null) return;
    final base = Size(size.width / item.zoom, size.height / item.zoom);
    if (_itemSizes[id] == base) return;
    _itemSizes[id] = base;
    notifyListeners();
  }

  /// Rectángulo del elemento, incluido el arrastre en curso si está seleccionado.
  Rect itemRect(CanvasItem item) {
    final offset = isItemSelected(item.id) ? _moveOffset : Offset.zero;
    return (item.position + offset) &
        ((_itemSizes[item.id] ?? canvasItemSize(item)) * item.zoom);
  }

  Rect? get selectionBounds {
    Rect? bounds;
    for (final item in _items) {
      if (isItemSelected(item.id))
        bounds = bounds?.expandToInclude(itemRect(item)) ?? itemRect(item);
    }
    for (final stroke in _strokes) {
      if (isStrokeSelected(stroke.id)) {
        final r = stroke.bounds.shift(_moveOffset);
        bounds = bounds?.expandToInclude(r) ?? r;
      }
    }
    return bounds;
  }

  /// Trazado actual de [link] (sigue a los elementos mientras se arrastran), o `null` si se solapan.
  LinkGeometry? linkGeometry(CanvasLink link) {
    final from = itemById(link.from), to = itemById(link.to);
    if (from == null || to == null) return null;
    return linkBetween(
      from: from,
      fromRect: itemRect(from),
      to: to,
      toRect: itemRect(to),
      style: link.style,
      arrow: link.arrow,
      bend: link.bend,
    );
  }

  /// Lo más alto bajo [point]: primero trazos (se pintan encima), luego elementos de arriba abajo
  /// y por último las conexiones, que van por debajo de todo.
  CanvasHit? hitTest(Offset point, {double strokeTolerance = 10}) {
    for (final stroke in _strokes.reversed) {
      if (stroke.hits(point, strokeTolerance))
        return CanvasHit.stroke(stroke.id);
    }
    return itemHitTest(point) ?? linkHitTest(point, strokeTolerance);
  }

  CanvasHit? itemHitTest(Offset point) {
    // Los marcos van detrás: sólo se cogen si no hay nada encima.
    for (final item in _items.reversed) {
      if (item.type != CanvasItemType.frame && itemRect(item).contains(point))
        return CanvasHit.item(item.id);
    }
    for (final item in _items.reversed) {
      if (item.type == CanvasItemType.frame && itemRect(item).contains(point))
        return CanvasHit.item(item.id);
    }
    return null;
  }

  /// Orden de pintado: los marcos debajo, el resto en el orden en que se añadieron.
  List<CanvasItem> get itemsInPaintOrder => [
    for (final i in _items)
      if (i.type == CanvasItemType.frame) i,
    for (final i in _items)
      if (i.type != CanvasItemType.frame) i,
  ];

  CanvasHit? linkHitTest(Offset point, double tolerance) {
    for (final link in links.reversed) {
      final geometry = linkGeometry(link);
      if (geometry == null) continue;
      // La píldora de texto también selecciona la conexión: así se puede tocar
      // para cambiar el estilo aunque el trazo quede debajo de otra tarjeta.
      final labelWidth = (link.label.length * 8.0 + 14).clamp(14.0, 194.0);
      final labelRect = Rect.fromCenter(
        center: geometry.mid + link.labelOffset,
        width: labelWidth,
        height: 28,
      );
      if (geometry.hits(point, tolerance) ||
          (link.label.isNotEmpty &&
              labelRect.inflate(tolerance).contains(point)))
        return CanvasHit.link(link.id);
    }
    return null;
  }

  /// Caja que envuelve todo el contenido, o `null` si el lienzo está vacío.
  Rect? get contentBounds {
    Rect? bounds;
    for (final item in _items) {
      bounds = bounds?.expandToInclude(itemRect(item)) ?? itemRect(item);
    }
    for (final stroke in _strokes) {
      bounds = bounds?.expandToInclude(stroke.bounds) ?? stroke.bounds;
    }
    return bounds;
  }

  bool isHitSelected(CanvasHit hit) => hit.itemId != null
      ? isItemSelected(hit.itemId!)
      : hit.strokeId != null
      ? isStrokeSelected(hit.strokeId!)
      : _selectedLink == hit.linkId;

  bool selectionContains(Offset point) =>
      selectionBounds?.inflate(12).contains(point) ?? false;

  // ---------------------------------------------------------------------------
  // Selección
  // ---------------------------------------------------------------------------

  /// [expandGroup] agrupa al tocar un marco: el contenedor mueve a sus hijos.
  /// Un hijo (cajita, texto, trazo) se selecciona solo para poder moverlo dentro.
  void selectOnly(CanvasHit hit, {bool expandGroup = true}) {
    final item = hit.itemId == null ? null : itemById(hit.itemId!);
    final group =
        item?.group ??
        _strokes.where((s) => s.id == hit.strokeId).firstOrNull?.group;
    final expand =
        expandGroup && group != null && item?.type == CanvasItemType.frame;
    _selectedItems = {
      if (hit.itemId != null) hit.itemId!,
      if (expand)
        for (final member in _items)
          if (member.group == group) member.id,
    };
    _selectedStrokes = {
      if (hit.strokeId != null) hit.strokeId!,
      if (expand)
        for (final stroke in _strokes)
          if (stroke.group == group) stroke.id,
    };
    _selectedLink = hit.linkId;
    notifyListeners();
  }

  void toggleSelection(CanvasHit hit) {
    if (hit.linkId != null) {
      selectOnly(hit);
      return;
    }
    final previousItems = Set<String>.of(_selectedItems);
    final previousStrokes = Set<int>.of(_selectedStrokes);
    final removing = isHitSelected(hit);
    selectOnly(hit);
    _selectedItems = removing
        ? previousItems.difference(_selectedItems)
        : previousItems.union(_selectedItems);
    _selectedStrokes = removing
        ? previousStrokes.difference(_selectedStrokes)
        : previousStrokes.union(_selectedStrokes);
    notifyListeners();
  }

  void _expandSelectedGroups() {
    // Sólo un marco seleccionado arrastra al resto del grupo. Si el lazo
    // rodeó una cajita interior, esa queda suelta.
    final groups = {
      for (final i in _items)
        if (isItemSelected(i.id) &&
            i.group != null &&
            i.type == CanvasItemType.frame)
          i.group!,
    };
    if (groups.isEmpty) return;
    _selectedItems = {
      ..._selectedItems,
      for (final i in _items)
        if (groups.contains(i.group)) i.id,
    };
    _selectedStrokes = {
      ..._selectedStrokes,
      for (final s in _strokes)
        if (groups.contains(s.group)) s.id,
    };
  }

  void clearSelection() {
    if (!hasSelection) return;
    _selectedItems = const {};
    _selectedStrokes = const {};
    _selectedLink = null;
    notifyListeners();
  }

  void selectAll() {
    _selectedLink = null;
    _selectedItems = {for (final i in _items) i.id};
    _selectedStrokes = {for (final s in _strokes) s.id};
    notifyListeners();
  }

  /// Selecciona los elementos cuyo centro cae dentro del lazo y los trazos con la mayoría de puntos dentro.
  /// Devuelve cuántos quedaron seleccionados.
  int selectInLasso(List<Offset> lasso) {
    if (lasso.length < 3) return selectionCount;
    final polygon = Path()..addPolygon(lasso, true);
    final polyBounds = polygon.getBounds();
    _selectedLink = null;

    _selectedItems = {
      for (final item in _items)
        if (polygon.contains(itemRect(item).center)) item.id,
    };
    _selectedStrokes = {
      for (final stroke in _strokes)
        if (stroke.bounds.overlaps(polyBounds) &&
            _mostlyInside(stroke, polygon))
          stroke.id,
    };
    _expandSelectedGroups();
    notifyListeners();
    return selectionCount;
  }

  static bool _mostlyInside(Stroke stroke, Path polygon) {
    // Muestra como máximo ~40 puntos para que trazos largos no penalicen.
    final step = math.max(1, stroke.points.length ~/ 40);
    var inside = 0, total = 0;
    for (var i = 0; i < stroke.points.length; i += step) {
      total++;
      if (polygon.contains(stroke.points[i])) inside++;
    }
    return total > 0 && inside / total >= 0.6;
  }

  // ---------------------------------------------------------------------------
  // Mover la selección
  // ---------------------------------------------------------------------------

  void updateMove(Offset delta) {
    if (selectionCount == 0) return;
    final bounds = _selectedContentBounds;
    final bounded = bounds == null
        ? delta
        : CanvasBounds.clampDelta(bounds, delta);
    if (bounded == _moveOffset) return;
    _moveOffset = bounded;
    notifyListeners();
  }

  Rect? get _selectedContentBounds {
    Rect? bounds;
    for (final item in _items) {
      if (!isItemSelected(item.id)) continue;
      final rect =
          item.position &
          ((_itemSizes[item.id] ?? canvasItemSize(item)) * item.zoom);
      bounds = bounds?.expandToInclude(rect) ?? rect;
    }
    for (final stroke in _strokes) {
      if (!isStrokeSelected(stroke.id)) continue;
      bounds = bounds?.expandToInclude(stroke.bounds) ?? stroke.bounds;
    }
    return bounds;
  }

  void commitMove() {
    if (_moveOffset == Offset.zero) return;
    final delta = _moveOffset;
    _checkpoint();
    // Lo que se suelta pasa al frente: si no, quedaría tapado por lo que tenga debajo.
    _items = [
      for (final i in _items)
        if (!isItemSelected(i.id)) i,
      for (final i in _items)
        if (isItemSelected(i.id)) i.copyWith(position: i.position + delta),
    ];
    _strokes = [
      for (final s in _strokes)
        if (!isStrokeSelected(s.id)) s,
      for (final s in _strokes)
        if (isStrokeSelected(s.id)) s.translated(delta),
    ];
    _moveOffset = Offset.zero;
    notifyListeners();
  }

  void cancelMove() {
    if (_moveOffset == Offset.zero) return;
    _moveOffset = Offset.zero;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Acciones sobre la selección
  // ---------------------------------------------------------------------------

  bool get canUngroup =>
      _items.any((i) => isItemSelected(i.id) && i.group != null) ||
      _strokes.any((s) => isStrokeSelected(s.id) && s.group != null);

  void groupSelection() {
    if (selectionCount < 2) return;
    _checkpoint();
    final group = 'group-${_nextItemId++}';
    _items = [
      for (final i in _items)
        isItemSelected(i.id) ? i.copyWith(group: group) : i,
    ];
    _strokes = [
      for (final s in _strokes) isStrokeSelected(s.id) ? s.grouped(group) : s,
    ];
    notifyListeners();
  }

  void ungroupSelection() {
    if (!canUngroup) return;
    _checkpoint();
    _items = [
      for (final i in _items)
        isItemSelected(i.id) ? i.copyWith(clearGroup: true) : i,
    ];
    _strokes = [
      for (final s in _strokes) isStrokeSelected(s.id) ? s.grouped(null) : s,
    ];
    notifyListeners();
  }

  CanvasItem? _resizeOriginal;
  void beginResize(String id) => _resizeOriginal = itemById(id);
  void updateResize(double factor) {
    final original = _resizeOriginal;
    if (original == null || !factor.isFinite) return;
    _items = [
      for (final i in _items)
        i.id == original.id
            ? original.copyWith(zoom: (original.zoom * factor).clamp(0.2, 5))
            : i,
    ];
    notifyListeners();
  }

  void endResize({bool cancel = false}) {
    final original = _resizeOriginal;
    if (original == null) return;
    final resized = itemById(original.id)!;
    _items = [for (final i in _items) i.id == original.id ? original : i];
    _resizeOriginal = null;
    if (!cancel && resized.zoom != original.zoom)
      updateItem(resized);
    else
      notifyListeners();
  }

  CanvasLink? _linkBendOriginal;
  CanvasLink? _linkLabelOriginal;

  void beginLinkBend(String id) =>
      _linkBendOriginal = _links.where((link) => link.id == id).firstOrNull;

  void updateLinkBend(Offset point) {
    final original = _linkBendOriginal;
    if (original == null || !point.dx.isFinite || !point.dy.isFinite) return;
    _replaceLink(original.copyWith(bend: point));
  }

  void endLinkBend({bool cancel = false}) {
    final original = _linkBendOriginal;
    if (original == null) return;
    final edited = _links.where((link) => link.id == original.id).firstOrNull;
    _replaceLink(original, notify: false);
    _linkBendOriginal = null;
    if (!cancel && edited != null && edited != original) {
      updateLink(edited);
    } else {
      notifyListeners();
    }
  }

  void beginLinkLabelMove(String id) =>
      _linkLabelOriginal = _links.where((link) => link.id == id).firstOrNull;

  void updateLinkLabelOffset(Offset offset) {
    final original = _linkLabelOriginal;
    if (original == null || !offset.dx.isFinite || !offset.dy.isFinite) return;
    _replaceLink(original.copyWith(labelOffset: offset));
  }

  void endLinkLabelMove({bool cancel = false}) {
    final original = _linkLabelOriginal;
    if (original == null) return;
    final edited = _links.where((link) => link.id == original.id).firstOrNull;
    _replaceLink(original, notify: false);
    _linkLabelOriginal = null;
    if (!cancel && edited != null && edited != original) {
      updateLink(edited);
    } else {
      notifyListeners();
    }
  }

  void _replaceLink(CanvasLink link, {bool notify = true}) {
    final index = _links.indexWhere((current) => current.id == link.id);
    if (index < 0 || _links[index] == link) return;
    _links = [..._links]..[index] = link;
    if (notify) notifyListeners();
  }

  void deleteSelection() {
    if (!hasSelection) return;
    _checkpoint();
    _items = [
      for (final i in _items)
        if (!isItemSelected(i.id)) i,
    ];
    _strokes = [
      for (final s in _strokes)
        if (!isStrokeSelected(s.id)) s,
    ];
    // Las conexiones de lo borrado se van con ello.
    final ids = {for (final i in _items) i.id};
    _links = [
      for (final l in _links)
        if (l.id != _selectedLink && ids.contains(l.from) && ids.contains(l.to))
          l,
    ];
    _selectedItems = const {};
    _selectedStrokes = const {};
    _selectedLink = null;
    notifyListeners();
  }

  /// Duplica desplazado 24 pt y deja seleccionadas las copias.
  void duplicateSelection() {
    if (!hasSelection) return;
    _checkpoint();
    const shift = Offset(24, 24);
    final newItems = <CanvasItem>[];
    final groups = <String, String>{};
    final newStrokes = <Stroke>[];
    for (final item in _items) {
      if (!isItemSelected(item.id)) continue;
      final copy = item.copyWith(
        id: 'copy-${_nextItemId++}',
        position: item.position + shift,
        group: item.group == null
            ? null
            : groups.putIfAbsent(item.group!, () => 'group-${_nextItemId++}'),
      );
      // La copia mide lo mismo que el original hasta que se maquete.
      final size = _itemSizes[item.id];
      if (size != null) _itemSizes[copy.id] = size;
      newItems.add(copy);
    }
    for (final stroke in _strokes) {
      if (isStrokeSelected(stroke.id))
        newStrokes.add(
          stroke
              .translated(shift, id: allocateStrokeId())
              .grouped(
                stroke.group == null
                    ? null
                    : groups.putIfAbsent(
                        stroke.group!,
                        () => 'group-${_nextItemId++}',
                      ),
              ),
        );
    }
    // Las conexiones internas del grupo también se duplican.
    final copyOf = {
      for (final (i, item) in _items.where((i) => isItemSelected(i.id)).indexed)
        item.id: newItems[i].id,
    };
    final newLinks = [
      for (final l in links)
        if (copyOf.containsKey(l.from) && copyOf.containsKey(l.to))
          l.copyWith(
            id: 'link-${_nextItemId++}',
            from: copyOf[l.from],
            to: copyOf[l.to],
          ),
    ];
    _items = [..._items, ...newItems];
    _strokes = [..._strokes, ...newStrokes];
    _links = [..._links, ...newLinks];
    _selectedItems = {for (final i in newItems) i.id};
    _selectedStrokes = {for (final s in newStrokes) s.id};
    notifyListeners();
  }

  void bringSelectionToFront() {
    if (!hasSelection) return;
    _checkpoint();
    _items = [
      for (final i in _items)
        if (!isItemSelected(i.id)) i,
      for (final i in _items)
        if (isItemSelected(i.id)) i,
    ];
    _strokes = [
      for (final s in _strokes)
        if (!isStrokeSelected(s.id)) s,
      for (final s in _strokes)
        if (isStrokeSelected(s.id)) s,
    ];
    notifyListeners();
  }

  /// Cambia el color de los trazos seleccionados. Devuelve si había trazos que recolorear.
  bool recolorSelection(Color color) {
    if (_selectedStrokes.isEmpty) return false;
    if (_strokes.every((s) => !isStrokeSelected(s.id) || s.color == color))
      return true;
    _checkpoint();
    _strokes = [
      for (final s in _strokes) isStrokeSelected(s.id) ? s.recolored(color) : s,
    ];
    notifyListeners();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Contenido
  // ---------------------------------------------------------------------------

  void addStroke(Stroke stroke) {
    _checkpoint();
    _strokes = [..._strokes, stroke];
    notifyListeners();
  }

  bool _erasing = false;

  void beginErase() => _erasing = false;

  void eraseAt(Offset point, double radius) {
    final remaining = [
      for (final s in _strokes)
        if (!s.hits(point, radius)) s,
    ];
    if (remaining.length == _strokes.length) return;
    _beginEraseStep();
    final removed = {
      for (final s in _strokes) s.id,
    }.difference({for (final s in remaining) s.id});
    _strokes = remaining;
    if (_selectedStrokes.any(removed.contains))
      _selectedStrokes = _selectedStrokes.difference(removed);
    notifyListeners();
  }

  /// Borrador parcial: corta los trazos por donde pasa.
  void erasePartialAt(Offset point, double radius) {
    var changed = false;
    final next = <Stroke>[];
    final removed = <int>{};
    for (final s in _strokes) {
      final pieces = s.erasedAround(point, radius, allocateStrokeId);
      if (pieces == null) {
        next.add(s);
      } else {
        changed = true;
        removed.add(s.id);
        next.addAll(pieces);
      }
    }
    if (!changed) return;
    _beginEraseStep();
    _strokes = next;
    if (_selectedStrokes.any(removed.contains))
      _selectedStrokes = _selectedStrokes.difference(removed);
    notifyListeners();
  }

  /// Borrador de elementos: quita notas, tarjetas, formas (con sus conexiones) y conexiones que toque.
  void eraseItemsAt(Offset point, double radius) {
    final ids = <String>{
      for (final item in _items)
        if (itemRect(item).inflate(radius).contains(point)) item.id,
      for (final link in links)
        if (linkGeometry(link)?.hits(point, radius) ?? false) link.id,
    };
    if (ids.isEmpty) return;
    _beginEraseStep();
    _batchDepth++;
    _batchCheckpointed = true;
    try {
      removeByIds(ids);
    } finally {
      _batchDepth--;
      _batchCheckpointed = false;
    }
  }

  /// Un solo paso de historial por gesto de borrado, sea cual sea el modo.
  void _beginEraseStep() {
    if (_erasing) {
      _revision++;
      return;
    }
    _checkpoint();
    _erasing = true;
  }

  /// Añade [template] con un identificador nuevo y lo deja seleccionado.
  CanvasItem addItem(CanvasItem template, {bool select = true}) {
    final item = template.copyWith(
      id: '${template.type.name}-${_nextItemId++}',
      position: CanvasBounds.clampItemPosition(
        template.position,
        canvasItemSize(template) * template.zoom,
      ),
    );
    _checkpoint();
    _items = [..._items, item];
    if (select) {
      _selectedItems = {item.id};
      _selectedStrokes = const {};
      _selectedLink = null;
    }
    notifyListeners();
    return item;
  }

  /// Borra elementos y conexiones por id (los que no existan se ignoran). Devuelve cuántos borró.
  int removeByIds(Set<String> ids) {
    final itemsLeft = [
      for (final i in _items)
        if (!ids.contains(i.id)) i,
    ];
    final linksLeft = [
      for (final l in _links)
        if (!ids.contains(l.id) && !ids.contains(l.from) && !ids.contains(l.to))
          l,
    ];
    final removed =
        (_items.length - itemsLeft.length) + (_links.length - linksLeft.length);
    if (removed == 0) return 0;
    _checkpoint();
    _items = itemsLeft;
    _links = linksLeft;
    _selectedItems = _selectedItems.difference(ids);
    if (ids.contains(_selectedLink)) _selectedLink = null;
    notifyListeners();
    return removed;
  }

  // ---------------------------------------------------------------------------
  // Conexiones
  // ---------------------------------------------------------------------------

  /// Conecta [from] con [to]. Si ya estaban conectados devuelve la conexión existente sin duplicarla.
  CanvasLink? addLink(
    String from,
    String to, {
    String label = '',
    LinkStyle style = LinkStyle.curved,
    LinkArrow arrow = LinkArrow.end,
    bool select = false,
  }) {
    if (from == to || itemById(from) == null || itemById(to) == null)
      return null;
    final existing = links.where((l) => l.connects(from, to)).firstOrNull;
    if (existing != null) return existing;
    final link = CanvasLink(
      id: 'link-${_nextItemId++}',
      from: from,
      to: to,
      label: label,
      style: style,
      arrow: arrow,
    );
    _checkpoint();
    _links = [..._links, link];
    if (select) {
      _selectedItems = const {};
      _selectedStrokes = const {};
      _selectedLink = link.id;
    }
    notifyListeners();
    return link;
  }

  void updateLink(CanvasLink link) {
    final index = _links.indexWhere((l) => l.id == link.id);
    if (index < 0 || _links[index] == link) return;
    _checkpoint();
    _links = [..._links]..[index] = link;
    notifyListeners();
  }

  /// Sustituye el elemento con el mismo id (edición desde el inspector).
  void updateItem(CanvasItem item) {
    final index = _items.indexWhere((i) => i.id == item.id);
    if (index < 0) return;
    _checkpoint();
    // Sólo se descarta la medida si cambió la maqueta. Un cambio de `zoom`
    // reaprovecha la medida base para que el borde y las flechas no salten
    // durante ni justo después de soltar el tirador.
    if (!_sameIntrinsicSize(_items[index], item)) _itemSizes.remove(item.id);
    _items = [..._items]
      ..[index] = item.copyWith(
        position: CanvasBounds.clampItemPosition(
          item.position,
          canvasItemSize(item) * item.zoom,
        ),
      );
    notifyListeners();
  }

  static bool _sameIntrinsicSize(CanvasItem a, CanvasItem b) =>
      a.type == b.type &&
      a.title == b.title &&
      a.subtitle == b.subtitle &&
      a.label == b.label &&
      a.iconKey == b.iconKey &&
      a.active == b.active &&
      a.scale == b.scale &&
      a.shape == b.shape &&
      a.width == b.width &&
      a.height == b.height &&
      listEquals(a.bullets, b.bullets) &&
      a.block == b.block &&
      listEquals(a.checks, b.checks) &&
      a.target == b.target;

  CanvasItem place(CanvasTool tool, Offset point) {
    final n = _nextItemId++;
    final label = n.toString().padLeft(2, '0');
    final item = switch (tool) {
      CanvasTool.sticky => CanvasItem(
        id: 'placed-$n',
        type: CanvasItemType.sticky,
        position: point,
        label: 'NOTA $label',
        title: 'Nueva idea',
        subtitle: 'Toca dos veces para editar',
      ),
      CanvasTool.shapes => CanvasItem(
        id: 'placed-$n',
        type: CanvasItemType.shape,
        position: point,
        title: 'Bloque $label',
      ),
      _ => CanvasItem(
        id: 'placed-$n',
        type: CanvasItemType.text,
        position: point,
        title: 'Texto',
      ),
    };
    final bounded = item.copyWith(
      position: CanvasBounds.clampItemPosition(
        item.position,
        canvasItemSize(item) * item.zoom,
      ),
    );
    _checkpoint();
    _items = [..._items, bounded];
    _selectedItems = {bounded.id};
    _selectedStrokes = const {};
    notifyListeners();
    return bounded;
  }

  void editItemTitle(String id, String title) {
    final item = _items.firstWhere((i) => i.id == id);
    if (item.title == title) return;
    _checkpoint();
    _items = [
      for (final i in _items) i.id == id ? i.copyWith(title: title) : i,
    ];
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Historial
  // ---------------------------------------------------------------------------

  int _batchDepth = 0;
  bool _batchCheckpointed = false;

  /// Agrupa varias operaciones en un solo paso de deshacer (p. ej. un diagrama que añade la IA).
  T batch<T>(T Function() run) {
    _batchDepth++;
    try {
      return run();
    } finally {
      if (--_batchDepth == 0) _batchCheckpointed = false;
    }
  }

  void _checkpoint() {
    _revision++;
    if (_batchDepth > 0) {
      if (_batchCheckpointed) return;
      _batchCheckpointed = true;
    }
    _undo.add(CanvasSnapshot(strokes: _strokes, items: _items, links: _links));
    if (_undo.length > _historyLimit) _undo.removeAt(0);
    _redo.clear();
  }

  void undo() => _restore(_undo, _redo);

  void redo() => _restore(_redo, _undo);

  void _restore(List<CanvasSnapshot> from, List<CanvasSnapshot> to) {
    if (from.isEmpty) return;
    _revision++;
    to.add(CanvasSnapshot(strokes: _strokes, items: _items, links: _links));
    final snap = from.removeLast();
    _strokes = snap.strokes;
    _items = snap.items;
    _itemSizes.clear();
    _links = snap.links;
    _moveOffset = Offset.zero;
    // La selección sólo conserva lo que sigue existiendo.
    final itemIds = {for (final i in _items) i.id};
    final strokeIds = {for (final s in _strokes) s.id};
    _selectedItems = _selectedItems.intersection(itemIds);
    _selectedStrokes = _selectedStrokes.intersection(strokeIds);
    if (_selectedLink != null && selectedLink == null) _selectedLink = null;
    notifyListeners();
  }
}
