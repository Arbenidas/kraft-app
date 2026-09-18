import 'dart:convert';

import 'package:flutter/painting.dart';

import 'canvas_models.dart';

/// Contenido de un lienzo tal como se guarda en la base de datos.
class CanvasData {
  const CanvasData({
    this.items = const [],
    this.strokes = const [],
    this.links = const [],
    this.viewCenter,
    this.viewScale,
  });

  final List<CanvasItem> items;
  final List<Stroke> strokes;
  final List<CanvasLink> links;

  /// Última vista usada (centro en coordenadas del lienzo y zoom), para reabrir donde se dejó.
  final Offset? viewCenter;
  final double? viewScale;

  bool get isEmpty => items.isEmpty && strokes.isEmpty;
}

/// JSON versionado. Si cambia el formato, sube [version] y migra en [decode].
/// v2: las conexiones son objetos con id, etiqueta y estilo (v1 las guardaba como `[from, to]`).
abstract final class CanvasCodec {
  static const version = 2;

  static String encode(CanvasData data) => jsonEncode({
        'v': version,
        'items': [for (final i in data.items) i.toJson()],
        'strokes': [for (final s in data.strokes) s.toJson()],
        'links': [for (final l in data.links) l.toJson()],
        if (data.viewCenter != null)
          'view': {'x': data.viewCenter!.dx, 'y': data.viewCenter!.dy, 's': data.viewScale ?? 1},
      });

  /// Tolera cadenas vacías o inválidas devolviendo un lienzo vacío.
  static CanvasData decode(String raw) {
    if (raw.trim().isEmpty) return const CanvasData();
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      final view = json['view'] as Map<String, Object?>?;
      return CanvasData(
        items: [for (final i in (json['items'] as List? ?? const [])) CanvasItem.fromJson((i as Map).cast())],
        strokes: [for (final s in (json['strokes'] as List? ?? const [])) Stroke.fromJson((s as Map).cast())],
        links: [
          for (final (i, l) in (json['links'] as List? ?? const []).indexed)
            CanvasLink.fromJson(l as Object, fallbackId: 'link-${i + 1}'),
        ],
        viewCenter: view == null ? null : Offset((view['x']! as num).toDouble(), (view['y']! as num).toDouble()),
        viewScale: (view?['s'] as num?)?.toDouble(),
      );
    } on Object {
      return const CanvasData();
    }
  }

  /// El boceto de ejemplo.
  static String seed() => encode(const CanvasData(items: CanvasSeed.items, links: CanvasSeed.links));
}
