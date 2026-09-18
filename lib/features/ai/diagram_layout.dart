import 'dart:math' as math;
import 'dart:ui';

/// Distribuciones automáticas para los diagramas que genera la IA.
enum DiagramLayout {
  /// Flujo de izquierda a derecha por niveles.
  horizontal,

  /// Flujo de arriba abajo por niveles.
  vertical,

  /// Mapa mental: la raíz en el centro y las ramas a izquierda y derecha.
  mindmap,

  /// Cuadrícula sin tener en cuenta las conexiones.
  grid,
}

/// Coloca [ids] (con sus [sizes]) según [layout] y devuelve la esquina superior izquierda de cada uno.
/// El conjunto queda con su caja envolvente empezando en (0, 0).
Map<String, Offset> layoutDiagram({
  required List<String> ids,
  required Map<String, Size> sizes,
  required List<(String, String)> edges,
  required DiagramLayout layout,
  double gapMain = 140,
  double gapCross = 60,
}) {
  if (ids.isEmpty) return const {};
  final known = ids.toSet();
  final validEdges = [
    for (final (a, b) in edges)
      if (known.contains(a) && known.contains(b) && a != b) (a, b),
  ];
  final positions = switch (layout) {
    DiagramLayout.horizontal => _layered(ids, sizes, validEdges, horizontal: true, gapMain: gapMain, gapCross: gapCross),
    DiagramLayout.vertical => _layered(ids, sizes, validEdges, horizontal: false, gapMain: gapMain * 0.8, gapCross: gapCross),
    DiagramLayout.mindmap => _mindmap(ids, sizes, validEdges, gapMain: gapMain * 0.8, gapCross: gapCross * 0.5),
    DiagramLayout.grid => _grid(ids, sizes, gap: gapCross),
  };
  return _normalize(positions, sizes);
}

/// Diagrama con carriles: cada grupo (capa, fase, equipo) ocupa una banda y los nodos avanzan
/// por niveles dentro de ella. Devuelve las posiciones y el rectángulo de cada grupo (para el marco).
({Map<String, Offset> positions, Map<String, Rect> groups}) layoutGrouped({
  required List<String> ids,
  required Map<String, Size> sizes,
  required List<(String, String)> edges,
  required Map<String, String> groupOf,
  required List<String> groupOrder,
  bool horizontal = true,
  double gapMain = 140,
  double gapCross = 48,
  double framePadding = 26,
  double frameHeader = 34,
}) {
  final known = ids.toSet();
  final validEdges = [
    for (final (a, b) in edges)
      if (known.contains(a) && known.contains(b) && a != b) (a, b),
  ];
  final rank = _ranks(ids, validEdges);
  final rankCount = rank.values.fold(0, math.max) + 1;

  double main(Size s) => horizontal ? s.width : s.height;
  double cross(Size s) => horizontal ? s.height : s.width;

  // Ancho (o alto) de cada nivel y comienzo de cada uno.
  final levelSize = List<double>.filled(rankCount, 0);
  for (final id in ids) {
    levelSize[rank[id]!] = math.max(levelSize[rank[id]!], main(sizes[id]!));
  }
  final levelStart = <double>[];
  var cursor = 0.0;
  for (final size in levelSize) {
    levelStart.add(cursor);
    cursor += size + gapMain;
  }
  final totalMain = cursor - gapMain;

  final lanes = [
    for (final group in groupOrder)
      if (ids.any((id) => groupOf[id] == group)) group,
    if (ids.any((id) => groupOf[id] == null)) '',
  ];

  final positions = <String, Offset>{};
  final groups = <String, Rect>{};
  var laneTop = 0.0;
  for (final lane in lanes) {
    final members = [for (final id in ids) if ((groupOf[id] ?? '') == lane) id];
    final byLevel = List.generate(rankCount, (r) => [for (final id in members) if (rank[id] == r) id]);
    final laneContent = byLevel.fold(0.0, (m, level) {
      final stack = level.fold(0.0, (sum, id) => sum + cross(sizes[id]!)) + gapCross * (level.length - 1);
      return math.max(m, stack);
    });
    final header = lane.isEmpty ? 0.0 : frameHeader;
    final padding = lane.isEmpty ? 0.0 : framePadding;

    for (final (r, level) in byLevel.indexed) {
      final stack = level.fold(0.0, (sum, id) => sum + cross(sizes[id]!)) + gapCross * (level.length - 1);
      var crossCursor = laneTop + header + padding + (laneContent - stack) / 2;
      for (final id in level) {
        final size = sizes[id]!;
        final mainPos = levelStart[r] + (levelSize[r] - main(size)) / 2;
        positions[id] = horizontal ? Offset(mainPos, crossCursor) : Offset(crossCursor, mainPos);
        crossCursor += cross(size) + gapCross;
      }
    }

    final laneHeight = header + padding * 2 + laneContent;
    if (lane.isNotEmpty) {
      // El marco abraza sólo los niveles que ocupa de verdad. Antes cruzaba el
      // diagrama entero, así que una capa con un elemento salía como una columna
      // casi vacía del alto de todo el dibujo.
      var mainMin = double.infinity, mainMax = -double.infinity;
      for (final id in members) {
        final start = horizontal ? positions[id]!.dx : positions[id]!.dy;
        mainMin = math.min(mainMin, start);
        mainMax = math.max(mainMax, start + main(sizes[id]!));
      }
      if (!mainMin.isFinite) {
        mainMin = 0;
        mainMax = totalMain;
      }
      final mainStart = mainMin - padding;
      final mainSpan = mainMax - mainMin + padding * 2;
      groups[lane] = horizontal
          ? Rect.fromLTWH(mainStart, laneTop, mainSpan, laneHeight)
          : Rect.fromLTWH(laneTop, mainStart, laneHeight, mainSpan);
    }
    laneTop += laneHeight + gapCross;
  }

  // Todo empieza en (0, 0).
  var origin = const Offset(double.infinity, double.infinity);
  for (final p in [...positions.values, ...groups.values.map((r) => r.topLeft)]) {
    origin = Offset(math.min(origin.dx, p.dx), math.min(origin.dy, p.dy));
  }
  if (!origin.dx.isFinite) origin = Offset.zero;
  return (
    positions: {for (final e in positions.entries) e.key: e.value - origin},
    groups: {for (final e in groups.entries) e.key: e.value.shift(-origin)},
  );
}

Map<String, Offset> _normalize(Map<String, Offset> positions, Map<String, Size> sizes) {
  var left = double.infinity, top = double.infinity;
  for (final MapEntry(key: id, value: p) in positions.entries) {
    left = math.min(left, p.dx);
    top = math.min(top, p.dy);
    assert(sizes.containsKey(id));
  }
  final shift = Offset(left, top);
  return {for (final e in positions.entries) e.key: e.value - shift};
}

/// Rango de cada nodo = camino más largo desde un origen; los ciclos se rompen en orden de aparición.
Map<String, int> _ranks(List<String> ids, List<(String, String)> edges) {
  final incoming = {for (final id in ids) id: <String>[]};
  final outgoing = {for (final id in ids) id: <String>[]};
  for (final (a, b) in edges) {
    outgoing[a]!.add(b);
    incoming[b]!.add(a);
  }
  final indegree = {for (final id in ids) id: incoming[id]!.length};
  final rank = <String, int>{};
  final queue = [for (final id in ids) if (indegree[id] == 0) id];
  final done = <String>{};

  while (done.length < ids.length) {
    if (queue.isEmpty) {
      // Ciclo: se toma el primer nodo pendiente como si fuera un origen.
      final next = ids.firstWhere((id) => !done.contains(id));
      queue.add(next);
      indegree[next] = 0;
    }
    final id = queue.removeAt(0);
    if (!done.add(id)) continue;
    rank[id] = incoming[id]!.where(done.contains).where((p) => p != id).fold(-1, (m, p) => math.max(m, rank[p] ?? -1)) + 1;
    for (final child in outgoing[id]!) {
      if (done.contains(child)) continue;
      indegree[child] = indegree[child]! - 1;
      if (indegree[child]! <= 0) queue.add(child);
    }
  }
  return rank;
}

Map<String, Offset> _layered(
  List<String> ids,
  Map<String, Size> sizes,
  List<(String, String)> edges, {
  required bool horizontal,
  required double gapMain,
  required double gapCross,
}) {
  final rank = _ranks(ids, edges);
  final layerCount = rank.values.fold(0, math.max) + 1;
  final layers = List.generate(layerCount, (_) => <String>[]);
  for (final id in ids) {
    layers[rank[id]!].add(id);
  }

  double main(Size s) => horizontal ? s.width : s.height;
  double cross(Size s) => horizontal ? s.height : s.width;

  // Orden dentro de cada capa: media de la posición de sus padres (menos cruces).
  final order = <String, double>{};
  for (final (l, layer) in layers.indexed) {
    if (l > 0) {
      double key(String id) {
        final parents = [for (final (a, b) in edges) if (b == id && order.containsKey(a)) order[a]!];
        return parents.isEmpty ? double.infinity : parents.reduce((x, y) => x + y) / parents.length;
      }

      final indexed = [for (final (i, id) in layer.indexed) (id, key(id), i)];
      indexed.sort((a, b) => a.$2 == b.$2 ? a.$3.compareTo(b.$3) : a.$2.compareTo(b.$2));
      layer
        ..clear()
        ..addAll(indexed.map((e) => e.$1));
    }
    for (final (i, id) in layer.indexed) {
      order[id] = i.toDouble();
    }
  }

  final crossSpans = [
    for (final layer in layers) layer.fold(0.0, (sum, id) => sum + cross(sizes[id]!)) + gapCross * (layer.length - 1),
  ];
  final widest = crossSpans.fold(0.0, math.max);

  final positions = <String, Offset>{};
  var mainCursor = 0.0;
  for (final (l, layer) in layers.indexed) {
    final thickness = layer.fold(0.0, (m, id) => math.max(m, main(sizes[id]!)));
    var crossCursor = (widest - crossSpans[l]) / 2;
    for (final id in layer) {
      final s = sizes[id]!;
      // Centrado en el grosor de la capa.
      final m = mainCursor + (thickness - main(s)) / 2;
      positions[id] = horizontal ? Offset(m, crossCursor) : Offset(crossCursor, m);
      crossCursor += cross(s) + gapCross;
    }
    mainCursor += thickness + gapMain;
  }
  return positions;
}

Map<String, Offset> _mindmap(
  List<String> ids,
  Map<String, Size> sizes,
  List<(String, String)> edges, {
  required double gapMain,
  required double gapCross,
}) {
  final hasIncoming = {for (final (_, b) in edges) b};
  final root = ids.firstWhere((id) => !hasIncoming.contains(id), orElse: () => ids.first);

  // Árbol por recorrido en anchura sobre las conexiones sin dirección.
  final neighbours = {for (final id in ids) id: <String>[]};
  for (final (a, b) in edges) {
    neighbours[a]!.add(b);
    neighbours[b]!.add(a);
  }
  final children = {for (final id in ids) id: <String>[]};
  final seen = {root};
  final queue = [root];
  while (queue.isNotEmpty) {
    final id = queue.removeAt(0);
    for (final n in neighbours[id]!) {
      if (seen.add(n)) {
        children[id]!.add(n);
        queue.add(n);
      }
    }
  }
  // Lo que no cuelga de la raíz se engancha a ella para no perderlo.
  for (final id in ids) {
    if (seen.add(id)) children[root]!.add(id);
  }

  final positions = <String, Offset>{};
  final rootSize = sizes[root]!;
  positions[root] = Offset(-rootSize.width / 2, -rootSize.height / 2);

  double subtreeHeight(String id) {
    final kids = children[id]!;
    final own = sizes[id]!.height;
    if (kids.isEmpty) return own;
    final kidsHeight = kids.fold(0.0, (sum, k) => sum + subtreeHeight(k)) + gapCross * (kids.length - 1);
    return math.max(own, kidsHeight);
  }

  // Coloca los hijos de [id] a un lado (dir = 1 derecha, -1 izquierda) repartidos en [top, top + height].
  void place(String id, List<String> kids, double parentEdgeX, double top, int dir) {
    var cursor = top;
    for (final kid in kids) {
      final h = subtreeHeight(kid);
      final s = sizes[kid]!;
      final x = dir > 0 ? parentEdgeX + gapMain : parentEdgeX - gapMain - s.width;
      positions[kid] = Offset(x, cursor + (h - s.height) / 2);
      final edge = dir > 0 ? x + s.width : x;
      place(kid, children[kid]!, edge, cursor, dir);
      cursor += h + gapCross;
    }
  }

  // Ramas alternadas: la mitad a la derecha, la otra mitad a la izquierda.
  final right = <String>[], left = <String>[];
  for (final (i, kid) in children[root]!.indexed) {
    (i.isEven ? right : left).add(kid);
  }
  for (final (side, dir) in [(right, 1), (left, -1)]) {
    if (side.isEmpty) continue;
    final total = side.fold(0.0, (sum, k) => sum + subtreeHeight(k)) + gapCross * (side.length - 1);
    place(root, side, dir > 0 ? rootSize.width / 2 : -rootSize.width / 2, -total / 2, dir);
  }
  return positions;
}

Map<String, Offset> _grid(List<String> ids, Map<String, Size> sizes, {required double gap}) {
  final columns = math.max(1, math.sqrt(ids.length).ceil());
  final cellW = ids.fold(0.0, (m, id) => math.max(m, sizes[id]!.width)) + gap;
  final cellH = ids.fold(0.0, (m, id) => math.max(m, sizes[id]!.height)) + gap;
  return {
    for (final (i, id) in ids.indexed) id: Offset((i % columns) * cellW, (i ~/ columns) * cellH),
  };
}
