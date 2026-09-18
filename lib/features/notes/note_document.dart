import 'dart:convert';
import 'note_sketch_model.dart';

import '../../data/db/database.dart';
import '../canvas/canvas_codec.dart';
import '../canvas/canvas_models.dart';

/// Casillas de las listas dentro del texto de una nota. Ambas se dibujan como texto
/// (☑ saldría como emoji en iOS y no casaría con ☐).
const checkboxOpen = '☐';
const checkboxDone = '▣';

/// Casilla marcada de versiones anteriores.
const _legacyDone = '☑';

/// Enlace de una nota a un lienzo o a otra nota (`canvas:3`, `note:5`).
class NoteLink {
  const NoteLink({required this.target, required this.title});

  final String target;
  final String title;

  bool get isNote => target.startsWith('note:');
  int? get id => int.tryParse(target.split(':').last);

  Map<String, Object?> toJson() => {'target': target, 'title': title};

  static NoteLink fromJson(Map<String, Object?> json) => NoteLink(
    target: json['target']! as String,
    title: json['title'] as String? ?? '',
  );

  @override
  bool operator ==(Object other) => other is NoteLink && other.target == target;

  @override
  int get hashCode => target.hashCode;
}

/// Una nota como documento: texto de corrido (la primera línea es el título, las líneas que empiezan
/// por ☐/▣ son tareas), trazos del lápiz encima de la página y enlaces.
class NoteDocument {
  const NoteDocument({
    this.text = '',
    this.strokes = const [],
    this.links = const [],
    this.sketches = const [],
  });

  final String text;

  /// Trazos en coordenadas de la página (origen arriba a la izquierda del texto).
  final List<Stroke> strokes;
  final List<NoteLink> links;
  final List<NoteSketch> sketches;

  static const version = 3;

  List<String> get lines => text.split('\n');

  /// Primera línea con texto (sin prefijos de encabezado markdown ni casillas).
  String get title {
    final first = lines.firstWhere(
      (l) => l.trim().isNotEmpty,
      orElse: () => '',
    );
    final stripped = stripCheckbox(first).trim();
    return stripped.replaceFirst(RegExp(r'^#{1,6}\s*'), '').trim();
  }

  /// Todo menos el título: vista previa y búsqueda.
  String get body {
    final all = lines;
    final index = all.indexWhere((l) => l.trim().isNotEmpty);
    return index < 0 ? '' : all.skip(index + 1).join('\n').trim();
  }

  NoteDocument copyWith({
    String? text,
    List<Stroke>? strokes,
    List<NoteLink>? links,
    List<NoteSketch>? sketches,
  }) => NoteDocument(
    text: text ?? this.text,
    strokes: strokes ?? this.strokes,
    links: links ?? this.links,
    sketches: sketches ?? this.sketches,
  );

  String encode() => jsonEncode({
    'v': version,
    if (sketches.isNotEmpty) 'sketches': [for (final s in sketches) s.toJson()],
    'text': text,
    if (strokes.isNotEmpty) 'strokes': [for (final s in strokes) s.toJson()],
    if (links.isNotEmpty) 'links': [for (final l in links) l.toJson()],
  });

  /// Lee el contenido guardado. Acepta los formatos anteriores:
  /// - vacío: nota antigua con título, idea central, texto y checklist en columnas;
  /// - v2: hoja de bloques del editor de lienzo.
  static NoteDocument decode(
    String raw, {
    Note? legacy,
    List<ChecklistItem> checklist = const [],
  }) {
    if (raw.trim().isEmpty)
      return legacy == null
          ? const NoteDocument()
          : fromLegacy(legacy, checklist);
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      if (json['v'] == version || json.containsKey('text')) {
        return NoteDocument(
          sketches: [
            for (final s in (json['sketches'] as List? ?? const []))
              NoteSketch.fromJson((s as Map).cast()),
          ],
          text: (json['text'] as String? ?? '').replaceAll(
            RegExp('^$_legacyDone ', multiLine: true),
            '$checkboxDone ',
          ),
          strokes: [
            for (final s in (json['strokes'] as List? ?? const []))
              Stroke.fromJson((s as Map).cast()),
          ],
          links: [
            for (final l in (json['links'] as List? ?? const []))
              NoteLink.fromJson((l as Map).cast()),
          ],
        );
      }
      return fromBlocks(CanvasCodec.decode(raw));
    } on Object {
      return NoteDocument(text: raw);
    }
  }

  static NoteDocument fromLegacy(
    Note note,
    List<ChecklistItem> checklist,
  ) => NoteDocument(
    text: [
      note.title,
      if (note.keyIdea.trim().isNotEmpty) note.keyIdea.trim(),
      if (note.body.trim().isNotEmpty) note.body.trim(),
      for (final c in checklist)
        '${c.done ? checkboxDone : checkboxOpen} ${c.content.replaceAll('\n', ' ')}',
    ].join('\n'),
  );

  /// Hoja de bloques (v2) → documento: el texto en orden de lectura, los trazos y los enlaces se conservan.
  static NoteDocument fromBlocks(CanvasData data) {
    final ordered = [...data.items]
      ..sort((a, b) {
        final dy = a.position.dy - b.position.dy;
        return dy.abs() > 12
            ? dy.sign.toInt()
            : a.position.dx.compareTo(b.position.dx);
      });
    final lines = <String>[
      for (final item in ordered)
        ...switch (item.type) {
          CanvasItemType.checklist => [
            for (final (text, done) in item.checklistLines)
              '${done ? checkboxDone : checkboxOpen} $text',
          ],
          CanvasItemType.link ||
          CanvasItemType.wireframe ||
          CanvasItemType.frame => const <String>[],
          _ => [item.title, item.subtitle].where((t) => t.trim().isNotEmpty),
        },
    ];
    return NoteDocument(
      text: lines.join('\n'),
      strokes: data.strokes,
      links: [
        for (final item in ordered)
          if (item.type == CanvasItemType.link && item.target != null)
            NoteLink(target: item.target!, title: item.title),
      ],
    );
  }
}

/// Quita el prefijo de casilla de una línea.
String stripCheckbox(String line) =>
    line.startsWith('$checkboxOpen ') || line.startsWith('$checkboxDone ')
    ? line.substring(2)
    : line;
