import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../theme/kraft_colors.dart';
import '../../theme/kraft_tokens.dart';
import '../../theme/kraft_typography.dart';

/// Markdown ligero para las respuestas del asistente.
///
/// No modifica el contenido que llega del proveedor: sólo lo presenta como
/// bloques legibles y da a las vallas de código una superficie propia.
class AssistantMarkdown extends StatelessWidget {
  const AssistantMarkdown({super.key, required this.text});

  final String text;

  static final _heading = RegExp(r'^(#{1,3})\s+(.+)$');
  // Algunas IAs emiten `--**Concepto:**` en vez de la forma canónica
  // `- **Concepto:**`; se acepta como viñeta para no mostrar Markdown crudo.
  static final _bullet = RegExp(r'^\s*(?:[-*+]\s+|--\s?)(.+)$');
  static final _ordered = RegExp(r'^\s*(\d+)\.\s+(.+)$');
  static final _rule = RegExp(r'^\s*(?:-{3,}|\*{3,}|_{3,})\s*$');

  @override
  Widget build(BuildContext context) {
    final blocks = _buildBlocks(text);
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: blocks,
      ),
    );
  }

  List<Widget> _buildBlocks(String source) {
    final lines = source.replaceAll('\r\n', '\n').split('\n');
    final blocks = <Widget>[];
    var index = 0;

    void add(Widget child) {
      if (blocks.isNotEmpty) blocks.add(const SizedBox(height: KraftSpace.sm));
      blocks.add(child);
    }

    while (index < lines.length) {
      final line = lines[index];
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        index++;
        continue;
      }

      if (trimmed.startsWith('```')) {
        final language = trimmed.substring(3).trim();
        final code = <String>[];
        index++;
        while (index < lines.length && !lines[index].trim().startsWith('```')) {
          code.add(lines[index]);
          index++;
        }
        if (index < lines.length) index++;
        add(_CodeBlock(language: language, code: code.join('\n')));
        continue;
      }

      if (_isTableStart(lines, index)) {
        final headers = _tableCells(line);
        final rows = <List<String>>[];
        index += 2; // Cabecera y separador `| --- |`.
        while (index < lines.length && lines[index].contains('|')) {
          final cells = _tableCells(lines[index]);
          if (cells.isEmpty) break;
          rows.add(cells);
          index++;
        }
        add(_MarkdownTable(headers: headers, rows: rows));
        continue;
      }

      final heading = _heading.firstMatch(line);
      if (heading != null) {
        add(_Heading(level: heading[1]!.length, text: heading[2]!));
        index++;
        continue;
      }

      if (_rule.hasMatch(line)) {
        add(Divider(height: 1, color: KraftColors.outlineVariant));
        index++;
        continue;
      }

      if (trimmed.startsWith('>')) {
        final quote = <String>[];
        while (index < lines.length && lines[index].trim().startsWith('>')) {
          quote.add(lines[index].trim().replaceFirst(RegExp(r'^>\s?'), ''));
          index++;
        }
        add(_Quote(text: quote.join('\n')));
        continue;
      }

      final bullet = _bullet.firstMatch(line);
      final ordered = _ordered.firstMatch(line);
      if (bullet != null || ordered != null) {
        final items = <Widget>[];
        while (index < lines.length) {
          final nextBullet = _bullet.firstMatch(lines[index]);
          final nextOrdered = _ordered.firstMatch(lines[index]);
          if (nextBullet == null && nextOrdered == null) break;
          final marker = nextOrdered?.group(1) == null
              ? '•'
              : '${nextOrdered!.group(1)}.';
          final item = nextBullet?.group(1) ?? nextOrdered!.group(2)!;
          if (items.isNotEmpty) items.add(const SizedBox(height: 4));
          items.add(_ListItem(marker: marker, text: item));
          index++;
        }
        add(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: items,
          ),
        );
        continue;
      }

      final paragraph = <String>[];
      while (index < lines.length && lines[index].trim().isNotEmpty) {
        final candidate = lines[index];
        if (paragraph.isNotEmpty &&
            (_isBlockStart(candidate) || candidate.trim().startsWith('```'))) {
          break;
        }
        paragraph.add(candidate);
        index++;
      }
      add(_MarkdownText(text: paragraph.join('\n')));
    }
    return blocks;
  }

  bool _isBlockStart(String line) =>
      _heading.hasMatch(line) ||
      _bullet.hasMatch(line) ||
      _ordered.hasMatch(line) ||
      _rule.hasMatch(line) ||
      line.trim().startsWith('>');

  bool _isTableStart(List<String> lines, int index) {
    if (index + 1 >= lines.length || !lines[index].contains('|')) return false;
    final separator = lines[index + 1].trim();
    return separator.contains('|') &&
        RegExp(
          r'^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$',
        ).hasMatch(separator);
  }

  List<String> _tableCells(String line) {
    var value = line.trim();
    if (value.startsWith('|')) value = value.substring(1);
    if (value.endsWith('|')) value = value.substring(0, value.length - 1);
    return value.split('|').map((cell) => cell.trim()).toList();
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.level, required this.text});

  final int level;
  final String text;

  @override
  Widget build(BuildContext context) {
    final size = switch (level) {
      1 => 19.0,
      2 => 16.0,
      _ => 14.0,
    };
    return _MarkdownText(
      text: text,
      style: KraftText.headlineSm.copyWith(
        fontSize: size,
        height: 1.25,
        color: KraftColors.onSurface,
      ),
    );
  }
}

class _ListItem extends StatelessWidget {
  const _ListItem({required this.marker, required this.text});

  final String marker;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 22,
        child: Text(
          marker,
          style: KraftText.labelCode.copyWith(
            color: KraftColors.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      Expanded(child: _MarkdownText(text: text)),
    ],
  );
}

class _Quote extends StatelessWidget {
  const _Quote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.only(left: KraftSpace.sm),
    decoration: BoxDecoration(
      border: Border(left: BorderSide(color: KraftColors.primary, width: 3)),
    ),
    child: _MarkdownText(
      text: text,
      style: KraftText.bodySm.copyWith(
        color: KraftColors.onSurfaceVariant,
        fontStyle: FontStyle.italic,
      ),
    ),
  );
}

/// Tabla Markdown con scroll lateral: una fila ancha no comprime ni corta las
/// columnas de la nota en iPad o en una ventana pequeña.
class _MarkdownTable extends StatelessWidget {
  const _MarkdownTable({required this.headers, required this.rows});

  final List<String> headers;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: KraftColors.surfaceContainerLow,
      border: Border.all(color: KraftColors.outlineVariant),
      borderRadius: BorderRadius.circular(KraftRadius.md),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final columns = headers.length;
        final width = math.max(constraints.maxWidth, columns * 180.0);
        final cellWidth = width / columns;
        Widget row(List<String> cells, {required bool header}) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < columns; index++)
              Container(
                width: cellWidth,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: header ? KraftColors.primaryContainer : null,
                  border: Border(
                    right: index == columns - 1
                        ? BorderSide.none
                        : BorderSide(color: KraftColors.outlineVariant),
                    bottom: header
                        ? BorderSide(color: KraftColors.outlineVariant)
                        : BorderSide.none,
                  ),
                ),
                child: _MarkdownText(
                  text: index < cells.length ? cells[index] : '',
                  style: (header ? KraftText.labelCode : KraftText.bodySm)
                      .copyWith(
                        color: header
                            ? KraftColors.onPrimaryContainer
                            : KraftColors.onSurface,
                        fontWeight: header ? FontWeight.w700 : FontWeight.w500,
                      ),
                ),
              ),
          ],
        );
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                row(headers, header: true),
                for (final cells in rows) ...[
                  row(cells, header: false),
                  if (cells != rows.last)
                    Divider(height: 1, color: KraftColors.outlineVariant),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _MarkdownText extends StatelessWidget {
  const _MarkdownText({required this.text, this.style});

  final String text;
  final TextStyle? style;

  static final _token = RegExp(
    r'(`[^`\n]+`|\*\*[^*\n]+\*\*|__[^_\n]+__|\*[^*\n]+\*|_[^_\n]+_)',
  );

  @override
  Widget build(BuildContext context) {
    final base =
        style ?? KraftText.bodySm.copyWith(color: KraftColors.onSurface);
    return RichText(
      text: TextSpan(style: base, children: _spans(text, base)),
      textWidthBasis: TextWidthBasis.parent,
    );
  }

  static List<InlineSpan> _spans(String value, TextStyle base) {
    final spans = <InlineSpan>[];
    var start = 0;
    for (final match in _token.allMatches(value)) {
      if (match.start > start) {
        spans.add(TextSpan(text: value.substring(start, match.start)));
      }
      final token = match.group(0)!;
      if (token.startsWith('`')) {
        spans.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: KraftText.labelCode.copyWith(
              fontSize: 11,
              height: 1.45,
              color: KraftColors.primary,
              backgroundColor: KraftColors.surfaceContainerHighest,
            ),
          ),
        );
      } else {
        final strong = token.startsWith('**') || token.startsWith('__');
        final wrap = strong ? 2 : 1;
        spans.add(
          TextSpan(
            text: token.substring(wrap, token.length - wrap),
            style: strong
                ? base.copyWith(fontWeight: FontWeight.w700)
                : base.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      }
      start = match.end;
    }
    if (start < value.length) spans.add(TextSpan(text: value.substring(start)));
    return spans;
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.language, required this.code});

  final String language;
  final String code;

  static const _background = Color(0xFF1D2021);
  static const _header = Color(0xFF282828);
  static const _code = Color(0xFFFABD2F);
  static const _lineNumber = Color(0xFFA89984);

  @override
  Widget build(BuildContext context) {
    final lines = code.isEmpty ? const [''] : code.split('\n');
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _background,
        border: Border.all(color: KraftColors.border, width: 1.5),
        borderRadius: BorderRadius.circular(KraftRadius.md),
        boxShadow: KraftShadow.hard(2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            color: _header,
            child: Row(
              children: [
                for (final color in const [
                  Color(0xFFFB4934),
                  Color(0xFFFABD2F),
                  Color(0xFFB8BB26),
                ])
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                const SizedBox(width: 5),
                const Icon(Symbols.code, size: 15, color: _lineNumber),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    language.isEmpty ? 'código' : language,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KraftText.techBadge.copyWith(color: _lineNumber),
                  ),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (index, line) in lines.indexed)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 30,
                            child: Text(
                              '${index + 1}',
                              textAlign: TextAlign.right,
                              style: KraftText.labelCode.copyWith(
                                fontSize: 11,
                                height: 1.55,
                                color: _lineNumber,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            line.isEmpty ? ' ' : line,
                            softWrap: false,
                            style: KraftText.labelCode.copyWith(
                              fontSize: 12,
                              height: 1.55,
                              color: _code,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
