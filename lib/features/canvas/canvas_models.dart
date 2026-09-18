import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../theme/kraft_colors.dart';
import 'canvas_icons.dart';
import 'stroke_geometry.dart';

/// Área de trabajo amplia, pero finita, para que matrices, minimapa y puntos
/// de fondo no acumulen coordenadas imposibles después de sesiones largas.
abstract final class CanvasBounds {
  static const extent = 10000.0;

  static Offset clampPoint(Offset point) => Offset(
    point.dx.clamp(-extent, extent).toDouble(),
    point.dy.clamp(-extent, extent).toDouble(),
  );

  static Offset clampItemPosition(Offset position, Size size) {
    final maxX = math.max(-extent, extent - size.width);
    final maxY = math.max(-extent, extent - size.height);
    return Offset(
      position.dx.clamp(-extent, maxX).toDouble(),
      position.dy.clamp(-extent, maxY).toDouble(),
    );
  }

  static Offset clampDelta(Rect bounds, Offset delta) => Offset(
    delta.dx.clamp(-extent - bounds.left, extent - bounds.right).toDouble(),
    delta.dy.clamp(-extent - bounds.top, extent - bounds.bottom).toDouble(),
  );

  /// Mantiene el centro de la cámara dentro del área de trabajo sin alterar
  /// su zoom. El lienzo usa únicamente traslación y escala uniforme.
  static Matrix4 clampView(Matrix4 matrix, Size viewport) {
    if (viewport.isEmpty || matrix.getMaxScaleOnAxis() == 0) return matrix;
    final center = MatrixUtils.transformPoint(
      Matrix4.inverted(matrix),
      viewport.center(Offset.zero),
    );
    final bounded = clampPoint(center);
    if (bounded == center) return matrix;
    final scale = matrix.getMaxScaleOnAxis();
    final screenCenter = viewport.center(Offset.zero);
    return matrix.clone()..setTranslationRaw(
      screenCenter.dx - bounded.dx * scale,
      screenCenter.dy - bounded.dy * scale,
      0,
    );
  }
}

enum CanvasTool {
  /// Tocar selecciona; arrastrar un elemento lo mueve; arrastrar en vacío hace un recuadro.
  select('Selección', Symbols.near_me, 'V'),

  /// Siempre dibuja un lazo libre (salvo si empieza sobre lo ya seleccionado: entonces lo mueve).
  lasso('Lazo de selección', Symbols.lasso_select, 'L'),

  /// Mano: el lápiz desplaza el lienzo.
  hand('Mover lienzo', Symbols.pan_tool, 'H'),
  pen('Lápiz / Trazo libre', Symbols.draw, 'P'),
  highlighter('Resaltador', Symbols.ink_highlighter, 'M'),
  shapes('Figuras & Diagramas', Symbols.crop_square, 'S'),
  sticky('Nota Adhesiva', Symbols.note_alt, 'N'),
  text('Texto', Symbols.title, 'T'),
  eraser('Borrador', Symbols.ink_eraser, 'E');

  const CanvasTool(this.label, this.icon, this.shortcut);

  final String label;
  final IconData icon;

  /// Tecla que la activa con teclado (Mac o iPad con teclado).
  final String shortcut;

  bool get draws => this == pen || this == highlighter || this == eraser;
  bool get places => this == shapes || this == sticky || this == text;
  bool get selects => this == select || this == lasso;
}

/// Las teclas de las herramientas, para el teclado del Mac o del iPad.
const canvasToolKeys = {
  'V': LogicalKeyboardKey.keyV,
  'L': LogicalKeyboardKey.keyL,
  'H': LogicalKeyboardKey.keyH,
  'P': LogicalKeyboardKey.keyP,
  'M': LogicalKeyboardKey.keyM,
  'S': LogicalKeyboardKey.keyS,
  'N': LogicalKeyboardKey.keyN,
  'T': LogicalKeyboardKey.keyT,
  'E': LogicalKeyboardKey.keyE,
};

/// 1, 2 y 3 para los tres grosores de trazo.
const canvasNumberKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
];

/// Qué borra el borrador.
enum EraserMode {
  partial(
    'Parcial',
    'Borra sólo la parte del trazo que tocas',
    Symbols.ink_eraser,
  ),
  stroke('Trazo', 'Borra trazos completos', Symbols.gesture),
  element(
    'Elemento',
    'Borra notas, tarjetas, formas y conexiones',
    Symbols.select,
  );

  const EraserMode(this.label, this.description, this.icon);
  final String label;
  final String description;
  final IconData icon;
}

final canvasStrokeWidths = [2.0, 4.0, 8.0];

final canvasColors = [
  (KraftColors.ink, 'Negro'),
  (KraftColors.primaryContainer, 'Amarillo'),
  (KraftColors.secondaryContainer, 'Verde Menta'),
  (KraftColors.tertiary, 'Azul Cian'),
];

/// Trazo terminado. Mientras se dibuja, los puntos viven en [LiveStroke] y se congelan al levantar el lápiz.
class Stroke {
  Stroke({
    required this.id,
    required List<Offset> points,
    required this.color,
    required this.width,
    this.highlighter = false,
    this.group,
    List<double>? pressures,
  }) : assert(pressures == null || pressures.length == points.length),
       points = List.unmodifiable(points),
       pressures = pressures == null ? null : List.unmodifiable(pressures);

  final int id;
  final String? group;
  final List<Offset> points;
  final Color color;

  /// Grosor base elegido en la paleta.
  final double width;
  final bool highlighter;

  /// Presión suavizada (0–1) por punto; `null` = grosor uniforme (dedo, ratón o presión desactivada).
  final List<double>? pressures;

  bool get hasPressure => pressures != null;

  /// Grosor real de cada punto.
  late final List<double> widths = [
    for (var i = 0; i < points.length; i++)
      pressures == null ? width : StrokePressure.widthFor(width, pressures![i]),
  ];

  /// Grosor visible máximo (el resaltador pinta el triple).
  late final double paintedWidth = highlighter
      ? width * 3
      : widths.fold(0.0, math.max);

  /// Contornos cacheados: se calculan una vez por trazo, no en cada repintado.
  late final StrokeOutline outline = StrokeOutline.build(points, widths);
  late final StrokeOutline haloOutline = StrokeOutline.build(
    points,
    widths,
    extra: 10,
  );

  late final Rect bounds = _computeBounds();

  Rect _computeBounds() {
    var left = double.infinity,
        top = double.infinity,
        right = -double.infinity,
        bottom = -double.infinity;
    for (final p in points) {
      if (p.dx < left) left = p.dx;
      if (p.dx > right) right = p.dx;
      if (p.dy < top) top = p.dy;
      if (p.dy > bottom) bottom = p.dy;
    }
    return Rect.fromLTRB(left, top, right, bottom).inflate(paintedWidth / 2);
  }

  Stroke grouped(String? value) => Stroke(
    id: id,
    points: points,
    color: color,
    width: width,
    highlighter: highlighter,
    pressures: pressures,
    group: value,
  );

  Stroke translated(Offset delta, {int? id}) => Stroke(
    id: id ?? this.id,
    points: [for (final p in points) p + delta],
    color: color,
    width: width,
    highlighter: highlighter,
    group: group,
    pressures: pressures,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    if (group != null) 'group': group,
    'c': color.toARGB32(),
    'w': width,
    if (highlighter) 'h': true,
    'p': [
      for (final p in points) ...[_round(p.dx), _round(p.dy)],
    ],
    if (pressures != null)
      'pr': [for (final v in pressures!) (v * 100).roundToDouble() / 100],
  };

  static Stroke fromJson(Map<String, Object?> json) {
    final flat = (json['p']! as List).cast<num>();
    return Stroke(
      id: json['id']! as int,
      group: json['group'] as String?,
      points: [
        for (var i = 0; i + 1 < flat.length; i += 2)
          Offset(flat[i].toDouble(), flat[i + 1].toDouble()),
      ],
      color: Color(json['c']! as int),
      width: (json['w']! as num).toDouble(),
      highlighter: json['h'] as bool? ?? false,
      pressures: (json['pr'] as List?)
          ?.cast<num>()
          .map((v) => v.toDouble())
          .toList(),
    );
  }

  /// Tramos que quedan al borrar lo que cae dentro de [radius] alrededor de [point].
  /// Devuelve `null` si no toca el trazo. Cada tramo necesita un id nuevo ([nextId]).
  List<Stroke>? erasedAround(
    Offset point,
    double radius,
    int Function() nextId,
  ) {
    if (!hits(point, radius)) return null;
    final runs = <List<int>>[];
    var current = <int>[];
    for (var i = 0; i < points.length; i++) {
      final r = radius + (highlighter ? paintedWidth : widths[i]) / 2;
      if ((points[i] - point).distanceSquared <= r * r) {
        if (current.isNotEmpty) runs.add(current);
        current = <int>[];
      } else {
        current.add(i);
      }
    }
    if (current.isNotEmpty) runs.add(current);
    return [
      for (final run in runs)
        if (run.length >= 2 || (run.length == 1 && points.length == 1))
          Stroke(
            id: nextId(),
            points: [for (final i in run) points[i]],
            color: color,
            width: width,
            highlighter: highlighter,
            group: group,
            pressures: pressures == null
                ? null
                : [for (final i in run) pressures![i]],
          ),
    ];
  }

  Stroke recolored(Color newColor) => Stroke(
    id: id,
    points: points,
    color: newColor,
    width: width,
    highlighter: highlighter,
    group: group,
    pressures: pressures,
  );

  bool hits(Offset point, double radius) {
    // Descarte rápido por caja antes de revisar punto a punto.
    if (!bounds.inflate(radius).contains(point)) return false;
    for (var i = 0; i < points.length; i++) {
      final r = radius + (highlighter ? paintedWidth : widths[i]) / 2;
      if ((points[i] - point).distanceSquared <= r * r) return true;
    }
    return false;
  }
}

/// Trazo en curso: listas mutables que notifican a su pintor sin reconstruir widgets.
class LiveStroke extends ChangeNotifier {
  LiveStroke();

  final List<Offset> _points = [];
  final List<double> _pressures = [];
  Color color = const Color(0xFF000000);
  double width = 4;
  bool highlighter = false;
  bool _usesPressure = false;

  List<Offset> get points => _points;
  bool get isActive => _points.isNotEmpty;
  bool get usesPressure => _usesPressure;

  /// Última presión suavizada (0–1), o `null` si el trazo no usa presión.
  double? get pressure =>
      _usesPressure && _pressures.isNotEmpty ? _pressures.last : null;

  List<double> get widths => [
    for (var i = 0; i < _points.length; i++)
      _usesPressure ? StrokePressure.widthFor(width, _pressures[i]) : width,
  ];

  /// [pressure] es la presión normalizada del primer punto, o `null` para grosor uniforme.
  void start(
    Offset point, {
    required Color color,
    required double width,
    required bool highlighter,
    double? pressure,
  }) {
    _points
      ..clear()
      ..add(point);
    _pressures.clear();
    // El resaltador mantiene grosor constante, como un rotulador.
    _usesPressure = pressure != null && !highlighter;
    if (_usesPressure) _pressures.add(pressure!);
    this.color = color;
    this.width = width;
    this.highlighter = highlighter;
    notifyListeners();
  }

  /// Ignora movimientos menores que [minDistance] (en coordenadas del lienzo) para no inflar el trazo,
  /// pero la presión se sigue suavizando con cada muestra.
  void add(Offset point, {double minDistance = 1, double? pressure}) {
    if (_points.isEmpty) return;
    final smoothed = _usesPressure && pressure != null
        ? StrokePressure.smooth(_pressures.last, pressure)
        : null;
    if ((point - _points.last).distanceSquared < minDistance * minDistance) {
      if (smoothed != null) {
        _pressures[_pressures.length - 1] = smoothed;
        notifyListeners();
      }
      return;
    }
    _points.add(point);
    if (_usesPressure) _pressures.add(smoothed ?? _pressures.last);
    notifyListeners();
  }

  Stroke? finish(int id) {
    if (_points.isEmpty) return null;
    final stroke = Stroke(
      id: id,
      points: _points,
      color: color,
      width: width,
      highlighter: highlighter,
      pressures: _usesPressure ? _pressures : null,
    );
    _points.clear();
    _pressures.clear();
    notifyListeners();
    return stroke;
  }

  /// Descarta el trazo en curso (p. ej. si el gesto se convierte en pellizco).
  void cancel() {
    if (_points.isEmpty) return;
    _points.clear();
    _pressures.clear();
    notifyListeners();
  }
}

/// Lazo de selección en curso, en coordenadas del lienzo.
class LassoPath extends ChangeNotifier {
  final List<Offset> _points = [];

  List<Offset> get points => _points;
  bool get isActive => _points.isNotEmpty;

  void start(Offset point) {
    _points
      ..clear()
      ..add(point);
    notifyListeners();
  }

  void add(Offset point, {double minDistance = 3}) {
    if (_points.isEmpty ||
        (point - _points.last).distanceSquared < minDistance * minDistance)
      return;
    _points.add(point);
    notifyListeners();
  }

  /// Recuadro de selección: el lazo pasa a ser el rectángulo entre [a] y [b].
  void setRect(Offset a, Offset b) {
    final r = Rect.fromPoints(a, b);
    _points
      ..clear()
      ..addAll([r.topLeft, r.topRight, r.bottomRight, r.bottomLeft]);
    notifyListeners();
  }

  List<Offset> finish() {
    final result = List<Offset>.of(_points);
    _points.clear();
    notifyListeners();
    return result;
  }
}

enum CanvasItemType {
  node,
  sticky,
  shape,
  text,
  wireframe,
  icon,
  card,

  /// Bloque de texto con teclado (o Scribble del lápiz), de ancho fijo: la base de las notas.
  paragraph,

  /// Lista de casillas; cada línea de [CanvasItem.title] es una tarea y [CanvasItem.checks] su estado.
  checklist,

  /// Enlace a otro lienzo o nota ([CanvasItem.target] = `canvas:3` o `note:5`).
  link,

  /// Marco con título que agrupa otros elementos (capas de una arquitectura, fases, carriles).
  /// Se pinta detrás de todo.
  frame;

  /// Se editan escribiendo directamente sobre el lienzo, no con la hoja del editor.
  bool get editsInline => this == paragraph || this == checklist;
}

/// Estilo de un bloque de texto.
enum BlockStyle {
  heading('Título'),
  subheading('Subtítulo'),
  body('Texto'),
  callout('Idea central');

  const BlockStyle(this.label);
  final String label;
}

enum ShapeKind {
  rectangle('Rectángulo'),
  ellipse('Círculo'),
  diamond('Rombo'),
  triangle('Triángulo'),
  arrow('Flecha'),
  line('Línea');

  const ShapeKind(this.label);
  final String label;

  /// Formas sin interior donde escribir.
  bool get isStroke => this == arrow || this == line;
}

/// Tamaños relativos que ofrece el editor de elementos.
enum ItemScale {
  small('S', 0.75),
  medium('M', 1),
  large('L', 1.4);

  const ItemScale(this.label, this.factor);
  final String label;
  final double factor;
}

@immutable
class CanvasItem {
  const CanvasItem({
    required this.id,
    required this.type,
    required this.position,
    this.title = '',
    this.subtitle = '',
    this.label = '',
    this.iconKey,
    this.active = false,
    this.color,
    this.scale = ItemScale.medium,
    this.shape = ShapeKind.rectangle,
    this.width,
    this.height,
    this.bullets = const [],
    this.block = BlockStyle.body,
    this.checks = const [],
    this.target,
    this.group,
    this.zoom = 1,
  });

  final String id;
  final CanvasItemType type;
  final Offset position;
  final String title;
  final String subtitle;

  /// Etiqueta técnica de cabecera (p. ej. `PASO 01`).
  final String label;

  /// Clave de [canvasIcons]; `null` sin icono.
  final String? iconKey;
  final bool active;

  /// Fondo (notas, formas, tarjetas, iconos) o tinta (texto). `null` = color por defecto del tipo.
  final Color? color;
  final ItemScale scale;
  final ShapeKind shape;

  /// Ancho de párrafos, checklists y marcos (el alto crece con el texto). `null` = ancho por defecto.
  final double? width;

  /// Alto de los marcos.
  final double? height;

  /// Puntos de detalle de una tarjeta ("• …"), para explicar sin llenar el lienzo de texto suelto.
  final List<String> bullets;
  final BlockStyle block;
  final List<bool> checks;

  /// Destino de un enlace: `canvas:<id>` o `note:<id>`.
  final String? target;

  /// Diagrama al que pertenece (lo pone la IA para poder editarlo después).
  final String? group;
  final double zoom;

  IconData? get icon => canvasIcon(iconKey);

  /// Líneas de una checklist con su estado.
  List<(String, bool)> get checklistLines {
    final lines = title.isEmpty ? const <String>[] : title.split('\n');
    return [
      for (final (i, l) in lines.indexed) (l, i < checks.length && checks[i]),
    ];
  }

  bool get editable => type != CanvasItemType.wireframe;

  CanvasItem copyWith({
    String? id,
    Offset? position,
    String? title,
    String? subtitle,
    String? label,
    String? iconKey,
    bool clearIcon = false,
    bool? active,
    Color? color,
    ItemScale? scale,
    ShapeKind? shape,
    double? width,
    double? height,
    List<String>? bullets,
    BlockStyle? block,
    List<bool>? checks,
    String? target,
    bool clearTarget = false,
    String? group,
    bool clearGroup = false,
    double? zoom,
  }) => CanvasItem(
    id: id ?? this.id,
    type: type,
    position: position ?? this.position,
    title: title ?? this.title,
    subtitle: subtitle ?? this.subtitle,
    label: label ?? this.label,
    iconKey: clearIcon ? null : (iconKey ?? this.iconKey),
    active: active ?? this.active,
    color: color ?? this.color,
    scale: scale ?? this.scale,
    shape: shape ?? this.shape,
    width: width ?? this.width,
    height: height ?? this.height,
    bullets: bullets ?? this.bullets,
    block: block ?? this.block,
    checks: checks ?? this.checks,
    target: clearTarget ? null : (target ?? this.target),
    group: clearGroup ? null : (group ?? this.group),
    zoom: zoom ?? this.zoom,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    't': type.name,
    'x': _round(position.dx),
    'y': _round(position.dy),
    if (title.isNotEmpty) 'title': title,
    if (subtitle.isNotEmpty) 'sub': subtitle,
    if (label.isNotEmpty) 'label': label,
    if (iconKey != null) 'icon': iconKey,
    if (active) 'active': true,
    if (color != null) 'color': color!.toARGB32(),
    if (scale != ItemScale.medium) 'scale': scale.name,
    if (type == CanvasItemType.shape) 'shape': shape.name,
    if (width != null) 'w': _round(width!),
    if (height != null) 'h': _round(height!),
    if (bullets.isNotEmpty) 'bullets': bullets,
    if (block != BlockStyle.body) 'block': block.name,
    if (checks.isNotEmpty) 'checks': [for (final c in checks) c ? 1 : 0],
    if (target != null) 'target': target,
    if (group != null) 'group': group,
    if (zoom != 1) 'zoom': zoom,
  };

  static CanvasItem fromJson(Map<String, Object?> json) => CanvasItem(
    id: json['id']! as String,
    type: CanvasItemType.values.byName(json['t']! as String),
    position: Offset(
      (json['x']! as num).toDouble(),
      (json['y']! as num).toDouble(),
    ),
    title: json['title'] as String? ?? '',
    subtitle: json['sub'] as String? ?? '',
    label: json['label'] as String? ?? '',
    iconKey: json['icon'] as String?,
    active: json['active'] as bool? ?? false,
    color: json['color'] == null ? null : Color(json['color']! as int),
    scale: json['scale'] == null
        ? ItemScale.medium
        : ItemScale.values.byName(json['scale']! as String),
    shape: json['shape'] == null
        ? ShapeKind.rectangle
        : ShapeKind.values.byName(json['shape']! as String),
    width: (json['w'] as num?)?.toDouble(),
    height: (json['h'] as num?)?.toDouble(),
    bullets: [for (final b in (json['bullets'] as List? ?? const [])) '$b'],
    block: BlockStyle.values.asNameMap()[json['block']] ?? BlockStyle.body,
    checks: [
      for (final c in (json['checks'] as List? ?? const []))
        c == 1 || c == true,
    ],
    target: json['target'] as String?,
    group: json['group'] as String?,
    zoom: ((json['zoom'] as num?)?.toDouble() ?? 1).clamp(0.2, 5),
  );
}

double _round(double v) => (v * 10).roundToDouble() / 10;

/// Instantánea completa del lienzo para deshacer/rehacer.
@immutable
class CanvasSnapshot {
  const CanvasSnapshot({
    required this.strokes,
    required this.items,
    required this.links,
  });

  final List<Stroke> strokes;
  final List<CanvasItem> items;
  final List<CanvasLink> links;
}

/// Lo que hay bajo un punto del lienzo: un elemento, un trazo o una conexión.
@immutable
class CanvasHit {
  const CanvasHit.item(String this.itemId) : strokeId = null, linkId = null;
  const CanvasHit.stroke(int this.strokeId) : itemId = null, linkId = null;
  const CanvasHit.link(String this.linkId) : itemId = null, strokeId = null;

  final String? itemId;
  final int? strokeId;
  final String? linkId;

  @override
  bool operator ==(Object other) =>
      other is CanvasHit &&
      other.itemId == itemId &&
      other.strokeId == strokeId &&
      other.linkId == linkId;

  @override
  int get hashCode => Object.hash(itemId, strokeId, linkId);
}

/// Trazado de la conexión. Ambos se enganchan al contorno real de cada elemento,
/// en el punto que mira hacia el otro: no hay anclas fijas.
enum LinkStyle {
  curved('Curva'),
  straight('Recta');

  const LinkStyle(this.label);
  final String label;
}

enum LinkArrow {
  end('Flecha'),
  both('Doble'),
  none('Sin punta');

  const LinkArrow(this.label);
  final String label;
}

/// Conexión dibujada entre dos elementos.
@immutable
class CanvasLink {
  const CanvasLink({
    required this.id,
    required this.from,
    required this.to,
    this.label = '',
    this.style = LinkStyle.curved,
    this.arrow = LinkArrow.end,
    this.bend,
    this.labelOffset = Offset.zero,
  });

  final String id;
  final String from;
  final String to;

  /// Texto opcional sobre la línea (p. ej. "sí" / "no").
  final String label;
  final LinkStyle style;
  final LinkArrow arrow;

  /// Punto intermedio opcional que el usuario arrastra para apartar la ruta.
  final Offset? bend;

  /// Desplazamiento de la etiqueta respecto al centro del trazado.
  final Offset labelOffset;

  bool connects(String a, String b) =>
      (from == a && to == b) || (from == b && to == a);

  CanvasLink copyWith({
    String? id,
    String? from,
    String? to,
    String? label,
    LinkStyle? style,
    LinkArrow? arrow,
    Offset? bend,
    bool clearBend = false,
    Offset? labelOffset,
  }) => CanvasLink(
    id: id ?? this.id,
    from: from ?? this.from,
    to: to ?? this.to,
    label: label ?? this.label,
    style: style ?? this.style,
    arrow: arrow ?? this.arrow,
    bend: clearBend ? null : (bend ?? this.bend),
    labelOffset: labelOffset ?? this.labelOffset,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'from': from,
    'to': to,
    if (label.isNotEmpty) 'label': label,
    if (style != LinkStyle.curved) 'style': style.name,
    if (arrow != LinkArrow.end) 'arrow': arrow.name,
    if (bend != null) 'bend': [_round(bend!.dx), _round(bend!.dy)],
    if (labelOffset != Offset.zero)
      'labelOffset': [_round(labelOffset.dx), _round(labelOffset.dy)],
  };

  /// Acepta el formato antiguo `[from, to]` (v1).
  static CanvasLink fromJson(Object json, {required String fallbackId}) {
    if (json is List)
      return CanvasLink(
        id: fallbackId,
        from: json[0] as String,
        to: json[1] as String,
      );
    final map = (json as Map).cast<String, Object?>();
    return CanvasLink(
      id: map['id'] as String? ?? fallbackId,
      from: map['from']! as String,
      to: map['to']! as String,
      label: map['label'] as String? ?? '',
      style: LinkStyle.values.asNameMap()[map['style']] ?? LinkStyle.curved,
      arrow: LinkArrow.values.asNameMap()[map['arrow']] ?? LinkArrow.end,
      bend: _offset(map['bend']),
      labelOffset: _offset(map['labelOffset']) ?? Offset.zero,
    );
  }

  static Offset? _offset(Object? value) {
    if (value is! List || value.length != 2) return null;
    final x = value[0], y = value[1];
    if (x is! num || y is! num) return null;
    return Offset(x.toDouble(), y.toDouble());
  }

  @override
  bool operator ==(Object other) =>
      other is CanvasLink &&
      other.id == id &&
      other.from == from &&
      other.to == to &&
      other.label == label &&
      other.style == style &&
      other.arrow == arrow &&
      other.bend == bend &&
      other.labelOffset == labelOffset;

  @override
  int get hashCode =>
      Object.hash(id, from, to, label, style, arrow, bend, labelOffset);
}

/// Contenido inicial: el boceto de arquitectura de la vista de Stitch.
abstract final class CanvasSeed {
  /// El boceto queda centrado en el origen del lienzo (0, 0).
  static const origin = Offset(-400, -310);

  static const items = [
    CanvasItem(
      id: 'node-1',
      type: CanvasItemType.node,
      position: Offset(-376, -130),
      label: 'PASO 01',
      iconKey: 'smartphone',
      title: '1. Registro Móvil',
      subtitle: 'Ingreso de teléfono o email',
    ),
    CanvasItem(
      id: 'node-2',
      type: CanvasItemType.node,
      position: Offset(-130, -130),
      label: 'PASO 02',
      iconKey: 'fingerprint',
      title: '2. Biometría',
      subtitle: 'FaceID o TouchID sin contraseñas',
      active: true,
    ),
    CanvasItem(
      id: 'sticky-1',
      type: CanvasItemType.sticky,
      position: Offset(160, -260),
      label: 'IDEA PRINCIPAL',
      title: 'Flujo de autenticación sin contraseñas con biometría táctil.',
      subtitle: 'Apple Pencil · Nota rápida',
    ),
    CanvasItem(
      id: 'wire-1',
      type: CanvasItemType.wireframe,
      position: Offset(-364, 30),
      label: '#BOCETO_PANTALLA_ACCESO',
    ),
  ];

  static const links = [CanvasLink(id: 'link-1', from: 'node-1', to: 'node-2')];
}
