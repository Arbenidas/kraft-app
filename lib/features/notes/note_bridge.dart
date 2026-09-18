import 'package:flutter/foundation.dart';

import '../canvas/canvas_models.dart';
import 'note_sketch_model.dart';

/// La nota abierta en pantalla, vista desde fuera (el asistente de voz escribe en ella en vivo).
abstract interface class LiveNote {
  int get noteId;
  String get noteText;

  /// Tinta que ya hay en la página: sirve para colocar el siguiente boceto debajo.
  List<Stroke> get noteStrokes;

  void appendText(String text);

  /// Aplica una reescritura sólo si el texto que la IA leyó sigue intacto.
  bool replaceTextIfUnchanged(String expected, String replacement);

  /// Dibuja [strokes] sobre la página como un único paso de deshacer.
  void addStrokes(List<Stroke> strokes);

  void focusText(String phrase);
  Future<void> persist();
}

/// Punto de encuentro entre el asistente y la nota abierta.
class NoteBridge extends ChangeNotifier {
  LiveNote? _live;

  /// La app lo configura para poder abrir una nota desde el asistente.
  Future<void> Function(int noteId)? openHandler;

  LiveNote? get live => _live;

  void attach(LiveNote note) {
    _live = note;
    notifyListeners();
  }

  void detach(LiveNote note) {
    if (!identical(_live, note)) return;
    _live = null;
    notifyListeners();
  }

  Future<void> focusText(int noteId, String phrase) async {
    final live = _live;
    if (live == null || live.noteId != noteId) {
      throw StateError('Abre primero la nota para señalar una parte.');
    }
    live.focusText(phrase);
  }
}

/// Capability for notes that support independent, bounded drawing attachments.
abstract interface class LiveSketchNote {
  void addSketch(NoteSketch sketch);
}
