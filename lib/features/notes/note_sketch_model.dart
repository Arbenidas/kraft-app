import '../canvas/canvas_codec.dart';

/// Self-contained note attachment: copying its JSON creates an independent drawing.
class NoteSketch {
  const NoteSketch({required this.id, required this.data});
  final String id;
  final CanvasData data;
  Map<String, Object?> toJson() => {'id': id, 'data': CanvasCodec.encode(data)};
  factory NoteSketch.fromJson(Map<String, Object?> json) => NoteSketch(
    id: json['id']! as String,
    data: CanvasCodec.decode(json['data']! as String),
  );
}
