import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../data/repositories.dart';
import '../canvas/canvas_codec.dart';
import '../canvas/canvas_document.dart';

/// Error que se devuelve a la IA como resultado de la herramienta (no rompe la conexión).
class McpToolError implements Exception {
  const McpToolError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// El lienzo abierto en pantalla, visto desde fuera: la IA edita su documento en vivo.
abstract interface class LiveCanvas {
  int get canvasId;
  String get canvasTitle;

  /// `null` mientras carga o si el lienzo no existe.
  CanvasDocument? get document;

  /// Se completa cuando terminó de cargar.
  Future<void> get ready;
  Future<void> persist();

  /// Enseña [world] (lo que acaba de añadir la IA) si queda fuera de la vista.
  void reveal(Rect world);

  /// Aviso visible de un cambio hecho por la IA.
  void announceRemoteEdit(String summary);

  /// Lleva la vista y la selección a un elemento durante una explicación.
  void focusItem(String itemId);
}

/// Punto de encuentro entre el servidor MCP y los lienzos: si el lienzo está abierto se edita en vivo
/// (con deshacer); si no, se lee y se guarda directamente en la base de datos.
class CanvasBridge extends ChangeNotifier {
  CanvasBridge(this._repo);

  final CanvasesRepository _repo;
  LiveCanvas? _live;
  final _attachWaiters = <int, Completer<void>>{};

  /// La app lo configura para poder abrir un lienzo desde la IA.
  Future<void> Function(int canvasId)? openHandler;

  LiveCanvas? get live => _live;
  int? get openCanvasId => _live?.canvasId;

  void attach(LiveCanvas canvas) {
    _live = canvas;
    _attachWaiters.remove(canvas.canvasId)?.complete();
    notifyListeners();
  }

  void detach(LiveCanvas canvas) {
    if (!identical(_live, canvas)) return;
    _live = null;
    notifyListeners();
  }

  int resolveId(int? canvasId) =>
      canvasId ??
      _live?.canvasId ??
      (throw const McpToolError(
        'No hay ningún lienzo abierto en KRAFT. Indica canvas_id (usa list_canvases) o crea uno con create_canvas.',
      ));

  /// Abre el lienzo en pantalla y espera a que cargue.
  Future<void> open(int canvasId) async {
    if (_live?.canvasId == canvasId) return;
    final handler = openHandler;
    if (handler == null)
      throw const McpToolError('KRAFT no puede abrir lienzos ahora mismo.');
    if (await _repo.get(canvasId) == null)
      throw McpToolError('No existe el lienzo $canvasId.');
    final attached = _attachWaiters.putIfAbsent(canvasId, Completer.new).future;
    await handler(canvasId);
    await attached.timeout(const Duration(seconds: 3), onTimeout: () {});
    _attachWaiters.remove(canvasId);
    await _live?.ready;
  }

  /// Aplica [op] al documento del lienzo [canvasId] (o al abierto) como un único paso de deshacer y lo guarda.
  /// [reveal] indica qué zona enseñar después.
  Future<T> edit<T>(
    int? canvasId,
    T Function(CanvasDocument doc) op, {
    Rect? Function(T result, CanvasDocument doc)? reveal,
    String Function(T result)? summary,
  }) async {
    final id = resolveId(canvasId);
    final live = _live;
    if (live != null && live.canvasId == id) {
      await live.ready;
      final doc =
          live.document ??
          (throw McpToolError('No se pudo cargar el lienzo $id.'));
      final revision = doc.revision;
      final result = doc.batch(() => op(doc));
      if (doc.revision != revision) {
        final area = reveal?.call(result, doc);
        if (area != null) live.reveal(area);
        if (summary != null) live.announceRemoteEdit(summary(result));
        await live.persist();
      }
      return result;
    }

    final record =
        await _repo.get(id) ?? (throw McpToolError('No existe el lienzo $id.'));
    final data = CanvasCodec.decode(record.data);
    final doc = CanvasDocument(
      items: data.items,
      strokes: data.strokes,
      links: data.links,
    );
    try {
      final result = op(doc);
      if (doc.revision != 0) {
        // Al abrirlo después, la vista empieza en lo último que añadió la IA.
        final area = reveal?.call(result, doc);
        await _repo.save(
          id,
          title: record.title,
          data: CanvasCodec.encode(
            CanvasData(
              items: doc.items,
              strokes: doc.strokes,
              links: doc.links,
              viewCenter: area?.center ?? data.viewCenter,
              viewScale: area == null
                  ? data.viewScale
                  : (data.viewScale ?? 1).clamp(0.3, 1.0),
            ),
          ),
        );
      }
      return result;
    } finally {
      doc.dispose();
    }
  }

  /// Lectura sin cambios: usa el documento vivo si está abierto.
  Future<T> read<T>(
    int? canvasId,
    T Function(CanvasDocument doc, String title) op,
  ) async {
    final id = resolveId(canvasId);
    final live = _live;
    if (live != null && live.canvasId == id) {
      await live.ready;
      final doc =
          live.document ??
          (throw McpToolError('No se pudo cargar el lienzo $id.'));
      return op(doc, live.canvasTitle);
    }
    final record =
        await _repo.get(id) ?? (throw McpToolError('No existe el lienzo $id.'));
    final data = CanvasCodec.decode(record.data);
    final doc = CanvasDocument(
      items: data.items,
      strokes: data.strokes,
      links: data.links,
    );
    try {
      return op(doc, record.title);
    } finally {
      doc.dispose();
    }
  }

  /// Selecciona un elemento del lienzo abierto para acompañar una explicación
  /// hablada. Sólo tiene efecto si ese mismo lienzo está visible.
  Future<void> focusItem(int? canvasId, String itemId) async {
    final id = resolveId(canvasId);
    final live = _live;
    if (live == null || live.canvasId != id) {
      throw const McpToolError(
        'Abre primero el lienzo para señalar sus elementos.',
      );
    }
    await live.ready;
    final doc =
        live.document ??
        (throw McpToolError('No se pudo cargar el lienzo $id.'));
    if (doc.itemById(itemId) == null)
      throw McpToolError('No existe el elemento "$itemId" en este lienzo.');
    live.focusItem(itemId);
  }
}
