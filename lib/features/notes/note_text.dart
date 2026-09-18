import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/kraft_colors.dart';
import '../../theme/kraft_typography.dart';
import 'note_document.dart';

/// Estilos del texto de una nota.
/// Getters, no `static final`: un `final` se calcula la primera vez y se queda con
/// el color de ese momento, así que al cambiar de tema la nota seguía pintándose
/// con la paleta antigua.
abstract final class NoteStyles {
  static TextStyle get title => KraftText.headlineLg
      .copyWith(fontSize: 32, height: 1.3, fontWeight: FontWeight.w700);
  static TextStyle get body => KraftText.bodyLg
      .copyWith(fontSize: 19, height: 1.6, color: KraftColors.onSurface);
  static TextStyle get heading =>
      body.copyWith(fontSize: 23, fontWeight: FontWeight.w700);
  static TextStyle headingLevel(int level) => switch (level) {
        1 => title.copyWith(fontSize: 28, height: 1.25),
        2 => heading,
        3 => body.copyWith(fontSize: 20, fontWeight: FontWeight.w700, height: 1.4),
        _ => body.copyWith(fontWeight: FontWeight.w700),
      };
  static TextStyle get checkbox =>
      body.copyWith(fontSize: 22, color: KraftColors.ink);
  static TextStyle get checkboxDone =>
      checkbox.copyWith(color: KraftColors.secondary);
  static TextStyle get done => body.copyWith(
        color: KraftColors.onSurfaceVariant,
        decoration: TextDecoration.lineThrough,
      );
  static TextStyle get marker => body.copyWith(
        fontSize: 11,
        height: 1.6,
        color: KraftColors.outline,
        fontWeight: FontWeight.w400,
      );
  static TextStyle get rule => marker.copyWith(letterSpacing: 2);
  static TextStyle get bold => body.copyWith(fontWeight: FontWeight.w700);
  static TextStyle get italic => body.copyWith(fontStyle: FontStyle.italic);
  static TextStyle get code => KraftText.labelCode.copyWith(
        fontSize: 16,
        height: 1.5,
        color: KraftColors.primary,
      );
}

/// Geometría de la página de una nota. La usa el editor para dibujarla y el asistente
/// para colocar un boceto debajo de lo que ya hay escrito.
abstract final class NotePage {
  static const width = 820.0;
  static const padding = EdgeInsets.fromLTRB(48, 36, 48, 220);

  /// Ancho útil del texto (y del boceto más ancho que cabe).
  static const textWidth = width - 96;

  /// Alto que ocupa [text] con los estilos de la nota.
  static double textHeight(String text) {
    final painter = TextPainter(
      text: NoteTextController.spansFor(text),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: textWidth);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  /// Dónde empezar un boceto de lado [size] para no taparlo todo: debajo del texto
  /// y de la tinta que ya hubiera.
  static Offset sketchOrigin(NoteDocument doc, double size) {
    final inkBottom = doc.strokes.fold(
      0.0,
      (m, s) => math.max(m, s.bounds.bottom),
    );
    final top = math.max(padding.top + textHeight(doc.text), inkBottom);
    return Offset(padding.left, top + 24);
  }
}

/// Pinta el texto de la nota sin cambiarlo: Markdown ligero (encabezados, negrita,
/// listas, código) y líneas con ☐/▣ como tareas. Los caracteres se conservan para
/// que el cursor coincida con lo escrito.
class NoteTextController extends TextEditingController {
  NoteTextController({super.text});

  static final _heading = RegExp(r'^(#{1,4}) (.*)$');
  static final _headingPrefix = RegExp(r'^#{1,4} ');
  static final _ul = RegExp(r'^([-*]) (.*)$');
  static final _ol = RegExp(r'^(\d+\.) (.*)$');
  static final _hr = RegExp(r'^(-{3,}|\*{3,}|_{3,})$');
  static final _inline = RegExp(
    r'(`[^`]+`|\*\*[^*]+\*\*|__[^_]+__|\*[^*]+\*)',
  );

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) =>
      spansFor(text);

  /// Los mismos estilos sin necesitar un `BuildContext`: también sirven para medir la página.
  static TextSpan spansFor(String text) {
    final lines = text.split('\n');
    final titleIndex = lines.indexWhere((l) => l.trim().isNotEmpty);
    final children = <InlineSpan>[];
    var inFence = false;
    for (final (i, line) in lines.indexed) {
      final newline = i < lines.length - 1 ? '\n' : '';
      if (line.startsWith('```')) {
        inFence = !inFence;
      children.add(TextSpan(text: line, style: NoteStyles.code));
      if (newline.isNotEmpty) children.add(TextSpan(text: newline, style: NoteStyles.body));
      continue;
    }
    if (inFence) {
      children.add(TextSpan(text: line, style: NoteStyles.code));
      if (newline.isNotEmpty) children.add(TextSpan(text: newline, style: NoteStyles.body));
        continue;
      }
      children.addAll(_lineSpans(line, newline, isTitle: i == titleIndex && !_isTask(line)));
    }
    return TextSpan(style: NoteStyles.body, children: children);
  }

  /// Texto de lista o tarjetas: sin hashes, asteriscos ni vallas de código.
  static String readablePreview(String text) {
    final parts = <String>[];
    var inFence = false;
    for (final line in text.split('\n')) {
      if (line.startsWith('```')) {
        inFence = !inFence;
        continue;
      }
      if (inFence) continue;
      var t = line.replaceFirst(_headingPrefix, '');
      t = t.replaceFirst(RegExp(r'^[-*] '), '');
      t = t.replaceFirst(RegExp(r'^\d+\. '), '');
      if (_hr.hasMatch(t.trim())) continue;
      t = t.replaceAll('**', '').replaceAll('__', '').replaceAll('`', '').replaceAll('*', '').trim();
      if (t.isNotEmpty) parts.add(t);
    }
    return parts.join(' · ');
  }

  static List<InlineSpan> _lineSpans(String line, String newline, {required bool isTitle}) {
    if (isTitle) {
      final heading = _heading.firstMatch(line);
      if (heading != null) {
        return [
          TextSpan(text: '${heading[1]} ', style: NoteStyles.marker),
          ..._inlineSpans(heading[2]!, NoteStyles.title),
          if (newline.isNotEmpty) TextSpan(text: newline, style: NoteStyles.title),
        ];
      }
      return [
        ..._inlineSpans(line, NoteStyles.title),
        if (newline.isNotEmpty) TextSpan(text: newline, style: NoteStyles.title),
      ];
    }
    if (_isTask(line)) {
      final done = line.startsWith(checkboxDone);
      return [
        TextSpan(
          text: line.substring(0, 1),
          style: done ? NoteStyles.checkboxDone : NoteStyles.checkbox,
        ),
        ..._inlineSpans(line.substring(1), done ? NoteStyles.done : NoteStyles.body),
        if (newline.isNotEmpty)
          TextSpan(text: newline, style: done ? NoteStyles.done : NoteStyles.body),
      ];
    }
    if (_hr.hasMatch(line)) {
      return [
        TextSpan(text: line, style: NoteStyles.rule),
        if (newline.isNotEmpty) TextSpan(text: newline, style: NoteStyles.body),
      ];
    }
    final heading = _heading.firstMatch(line);
    if (heading != null) {
      final style = NoteStyles.headingLevel(heading[1]!.length);
      return [
        TextSpan(text: '${heading[1]} ', style: NoteStyles.marker),
        ..._inlineSpans(heading[2]!, style),
        if (newline.isNotEmpty) TextSpan(text: newline, style: style),
      ];
    }
    final ul = _ul.firstMatch(line);
    if (ul != null) {
      return [
        TextSpan(text: '${ul[1]} ', style: NoteStyles.marker.copyWith(fontSize: 19)),
        ..._inlineSpans(ul[2]!, NoteStyles.body),
        if (newline.isNotEmpty) TextSpan(text: newline, style: NoteStyles.body),
      ];
    }
    final ol = _ol.firstMatch(line);
    if (ol != null) {
      return [
        TextSpan(text: '${ol[1]} ', style: NoteStyles.bold),
        ..._inlineSpans(ol[2]!, NoteStyles.body),
        if (newline.isNotEmpty) TextSpan(text: newline, style: NoteStyles.body),
      ];
    }
    return [
      ..._inlineSpans(line, NoteStyles.body),
      if (newline.isNotEmpty) TextSpan(text: newline, style: NoteStyles.body),
    ];
  }

  static List<InlineSpan> _inlineSpans(String text, TextStyle base) {
    if (text.isEmpty) return const [];
    final children = <InlineSpan>[];
    var start = 0;
    for (final match in _inline.allMatches(text)) {
      if (match.start > start) {
        children.add(TextSpan(text: text.substring(start, match.start), style: base));
      }
      children.addAll(_marked(match[0]!, base));
      start = match.end;
    }
    if (start < text.length) {
      children.add(TextSpan(text: text.substring(start), style: base));
    }
    return children;
  }

  static List<InlineSpan> _marked(String token, TextStyle base) {
    if (token.startsWith('`') && token.endsWith('`') && token.length >= 2) {
      return [
        TextSpan(text: '`', style: NoteStyles.marker),
        TextSpan(text: token.substring(1, token.length - 1), style: NoteStyles.code),
        TextSpan(text: '`', style: NoteStyles.marker),
      ];
    }
    final wrap = token.startsWith('**') || token.startsWith('__') ? 2 : 1;
    final inner = token.substring(wrap, token.length - wrap);
    final style = wrap == 2
        ? base.copyWith(fontWeight: FontWeight.w700)
        : base.copyWith(fontStyle: FontStyle.italic);
    return [
      TextSpan(text: token.substring(0, wrap), style: NoteStyles.marker),
      TextSpan(text: inner, style: style),
      TextSpan(text: token.substring(token.length - wrap), style: NoteStyles.marker),
    ];
  }

  static bool _isTask(String line) => line.startsWith('$checkboxOpen ') || line.startsWith('$checkboxDone ');

  /// Inicio y fin de la línea que contiene [offset].
  (int, int) lineAt(int offset) {
    final safe = offset.clamp(0, text.length);
    final start = text.lastIndexOf('\n', safe == 0 ? 0 : safe - 1) + 1;
    final end = text.indexOf('\n', safe);
    return (safe == 0 ? 0 : start, end < 0 ? text.length : end);
  }

  /// Si la selección cayó sobre la casilla de una tarea, la marca o desmarca. Devuelve si lo hizo.
  bool toggleCheckboxAtSelection() {
    final offset = selection.baseOffset;
    if (!selection.isCollapsed || offset < 0) return false;
    final (start, end) = lineAt(offset);
    final line = text.substring(start, end);
    if (!_isTask(line) || offset > start + 1) return false;
    final mark = line.startsWith(checkboxOpen) ? checkboxDone : checkboxOpen;
    value = TextEditingValue(
      text: text.replaceRange(start, start + 1, mark),
      selection: TextSelection.collapsed(offset: end),
    );
    return true;
  }

  /// Convierte la línea actual en tarea (o la deja de ser).
  void toggleTaskLine() => _togglePrefix('$checkboxOpen ', alsoRemove: '$checkboxDone ');

  /// Convierte la línea actual en encabezado (o la deja de ser).
  void toggleHeadingLine() {
    final offset = selection.baseOffset < 0 ? text.length : selection.baseOffset;
    final (start, end) = lineAt(offset);
    final line = text.substring(start, end);
    final heading = _heading.firstMatch(line);
    if (heading != null) {
      final existing = '${heading[1]} ';
      value = TextEditingValue(
        text: text.replaceRange(start, start + existing.length, ''),
        selection: TextSelection.collapsed(
          offset: (offset - existing.length).clamp(start, text.length - existing.length),
        ),
      );
      return;
    }
    _togglePrefix('## ');
  }

  void _togglePrefix(String prefix, {String? alsoRemove}) {
    final offset = selection.baseOffset < 0 ? text.length : selection.baseOffset;
    final (start, end) = lineAt(offset);
    final line = text.substring(start, end);
    final existing = line.startsWith(prefix) ? prefix : (alsoRemove != null && line.startsWith(alsoRemove) ? alsoRemove : null);
    if (existing != null) {
      value = TextEditingValue(
        text: text.replaceRange(start, start + existing.length, ''),
        selection: TextSelection.collapsed(offset: (offset - existing.length).clamp(start, text.length - existing.length)),
      );
    } else {
      // Un encabezado no puede ser tarea y viceversa.
      final heading = _heading.firstMatch(line);
      final clean = heading != null ? '${heading[1]} '.length : (_isTask(line) ? 2 : 0);
      final newText = text.replaceRange(start, start + clean, prefix);
      value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: (offset - clean + prefix.length).clamp(0, newText.length)),
      );
    }
  }

  /// Añade [addition] al final del documento (p. ej. lo que dicta la IA).
  void appendText(String addition) {
    final trimmed = addition.trimRight();
    if (trimmed.isEmpty) return;
    final base = text.trimRight();
    final joined = base.isEmpty ? trimmed : '$base\n$trimmed';
    value = TextEditingValue(text: joined, selection: TextSelection.collapsed(offset: joined.length));
  }
}

/// Al pulsar Intro en una tarea, la siguiente línea empieza con ☐. En una tarea vacía, Intro la quita.
class TaskContinuationFormatter extends TextInputFormatter {
  const TaskContinuationFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final inserted = newValue.text.length - oldValue.text.length;
    final cursor = newValue.selection.baseOffset;
    if (inserted != 1 || cursor <= 0 || !newValue.selection.isCollapsed || newValue.text[cursor - 1] != '\n') {
      return newValue;
    }
    final text = newValue.text;
    final lineStart = text.lastIndexOf('\n', cursor - 2) + 1;
    final previous = text.substring(lineStart, cursor - 1);
    if (!previous.startsWith('$checkboxOpen ') && !previous.startsWith('$checkboxDone ')) return newValue;

    if (previous.trim().length <= 1) {
      // Tarea vacía + Intro: se sale de la lista.
      final cleaned = text.replaceRange(lineStart, cursor, '');
      return TextEditingValue(text: cleaned, selection: TextSelection.collapsed(offset: lineStart));
    }
    const prefix = '$checkboxOpen ';
    return TextEditingValue(
      text: text.replaceRange(cursor, cursor, prefix),
      selection: TextSelection.collapsed(offset: cursor + prefix.length),
    );
  }
}
