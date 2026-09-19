import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kraft/data/db/database.dart';
import 'package:kraft/data/enums.dart';
import 'package:kraft/features/canvas/canvas_codec.dart';
import 'package:kraft/features/canvas/canvas_models.dart';
import 'package:kraft/features/notes/note_document.dart';
import 'package:kraft/features/notes/note_screen.dart';
import 'package:kraft/features/notes/note_text.dart';

import 'helpers.dart';

const _seedTitle = 'Diseño de Experiencia iPad & Stylus';

Future<Note> _note(
  WidgetTester tester,
  AppDatabase db,
  bool Function(Note) where,
) async {
  final rows = await tester.runAsync(() => db.select(db.notes).get());
  return rows!.firstWhere(where);
}

Future<void> _exit(WidgetTester tester) async {
  await tester.tap(find.text('Notas').first);
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await settle(tester);
}

List<TextStyle> _styles(TextSpan span) {
  final out = <TextStyle>[];
  void walk(InlineSpan node) {
    if (node is! TextSpan) return;
    if (node.style != null) out.add(node.style!);
    node.children?.forEach(walk);
  }

  walk(span);
  return out;
}

void main() {
  group('documento', () {
    test('título, cuerpo y codificación', () {
      const doc = NoteDocument(
        text: '\nIdeas de voz\nHablar con la IA\n☐ Probar Gemini',
        links: [NoteLink(target: 'canvas:1', title: 'Boceto')],
      );
      expect(doc.title, 'Ideas de voz');
      expect(doc.body, 'Hablar con la IA\n☐ Probar Gemini');
      final back = NoteDocument.decode(doc.encode());
      expect(back.text, doc.text);
      expect(back.links.single.target, 'canvas:1');
    });

    test('convierte notas antiguas y hojas de bloques', () {
      final legacy = Note(
        id: 1,
        title: 'Plan',
        keyIdea: 'Idea',
        body: 'Cuerpo',
        content: '',
        category: NoteCategory.idea,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final fromLegacy = NoteDocument.decode(
        '',
        legacy: legacy,
        checklist: [
          ChecklistItem(
            id: 1,
            noteId: 1,
            content: 'A',
            done: true,
            position: 0,
          ),
        ],
      );
      expect(fromLegacy.text, 'Plan\nIdea\nCuerpo\n▣ A');

      final blocks = CanvasCodec.encode(
        const CanvasData(
          items: [
            CanvasItem(
              id: 'p1',
              type: CanvasItemType.paragraph,
              position: Offset(64, 72),
              title: 'Título',
            ),
            CanvasItem(
              id: 'c1',
              type: CanvasItemType.checklist,
              position: Offset(64, 200),
              title: 'X\nY',
              checks: [false, true],
            ),
            CanvasItem(
              id: 'l1',
              type: CanvasItemType.link,
              position: Offset(64, 300),
              title: 'Boceto',
              target: 'canvas:2',
            ),
          ],
        ),
      );
      final fromBlocks = NoteDocument.decode(blocks);
      expect(fromBlocks.text, 'Título\n☐ X\n▣ Y');
      expect(fromBlocks.links.single.target, 'canvas:2');
    });
  });

  group('texto', () {
    TextEditingValue type(TextEditingValue old, String text, int cursor) =>
        const TaskContinuationFormatter().formatEditUpdate(
          old,
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: cursor),
          ),
        );

    test(
      'Intro en una tarea continúa la lista y en una tarea vacía la termina',
      () {
        const old = TextEditingValue(
          text: 'Lista\n☐ pan',
          selection: TextSelection.collapsed(offset: 11),
        );
        final next = type(old, 'Lista\n☐ pan\n', 12);
        expect(next.text, 'Lista\n☐ pan\n☐ ');
        final exit = type(next, 'Lista\n☐ pan\n☐ \n', 15);
        expect(exit.text, 'Lista\n☐ pan\n');
      },
    );

    test('Intro normal conserva el salto de línea entre párrafos', () {
      const text = 'Primer párrafo';
      const old = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      final next = type(old, '$text\n', text.length + 1);
      expect(next.text, 'Primer párrafo\n');
      expect(next.selection.baseOffset, text.length + 1);
    });

    test('tocar la casilla la marca y los botones cambian la línea', () {
      final c = NoteTextController(text: 'Lista\n☐ pan');
      c.selection = const TextSelection.collapsed(offset: 6);
      expect(c.toggleCheckboxAtSelection(), isTrue);
      expect(c.text, 'Lista\n▣ pan');
      c.selection = const TextSelection.collapsed(offset: 3);
      c.toggleHeadingLine();
      expect(c.text, '## Lista\n▣ pan');
      c.toggleTaskLine();
      expect(c.text, '☐ Lista\n▣ pan');
    });

    test('pinta markdown y conserva cada carácter', () {
      const src =
          'Guía REST\n'
          '# Completa\n'
          '### Qué es\n'
          'Una **API REST** con `GET`\n'
          '- **POST**: crear\n'
          '---\n'
          '```\n'
          'https://api.ejemplo.com/v1/recurso\n'
          '```\n';
      final span = NoteTextController.spansFor(src);
      expect(span.toPlainText(), src);
      expect(
        _styles(
          span,
        ).any((s) => s.fontSize == 28 && s.fontWeight == FontWeight.w700),
        isTrue,
      );
      expect(
        _styles(
          span,
        ).any((s) => s.fontSize == 20 && s.fontWeight == FontWeight.w700),
        isTrue,
      );
      expect(_styles(span).any((s) => s.fontWeight == FontWeight.w700), isTrue);
      expect(
        _styles(span).any((s) => s.fontFamily == NoteStyles.code.fontFamily),
        isTrue,
      );
      expect(
        NoteTextController.readablePreview(src),
        'Guía REST · Completa · Qué es · Una API REST con GET · POST: crear',
      );
    });

    test('quita un encabezado ### al pulsar H2', () {
      final c = NoteTextController(text: '### Sección');
      c.selection = const TextSelection.collapsed(offset: 4);
      c.toggleHeadingLine();
      expect(c.text, 'Sección');
    });
  });

  testWidgets(
    'una nota antigua se abre como documento y al escribir se guarda',
    (tester) async {
      final db = await pumpKraft(tester, size: const Size(1366, 1024));
      await tapNav(tester, 'Notas');
      await tester.tap(find.text(_seedTitle));
      await settle(tester);
      expect(find.byType(NoteScreen), findsOneWidget);

      final field = find.byType(TextField);
      expect(
        tester.widget<TextField>(field).textInputAction,
        TextInputAction.newline,
      );
      final text = tester.widget<TextField>(field).controller!.text;
      expect(text, startsWith(_seedTitle));
      expect(text, contains('☐ Menú radial flotante'));

      await tester.enterText(field, '$text\n☐ Probar Gemini Live');
      await tester.pump(
        NoteScreen.saveDelay + const Duration(milliseconds: 50),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      final saved = await _note(tester, db, (n) => n.title == _seedTitle);
      expect(
        NoteDocument.decode(saved.content).text,
        endsWith('☐ Probar Gemini Live'),
      );
      expect(saved.body, contains('Probar Gemini Live'));
      await _exit(tester);
    },
  );

  testWidgets(
    'nota nueva: se escribe, se dibuja con el lápiz y el título sale de la primera línea',
    (tester) async {
      final db = await pumpKraft(tester, size: const Size(1366, 1024));
      await tapNav(tester, 'Notas');
      await tester.tap(find.byTooltip('Nueva nota'));
      await settle(tester);

      await tester.enterText(
        find.byType(TextField),
        'Ideas de voz\nHablar con KRAFT desde el inicio',
      );
      await tester.pump();

      await tester.tap(find.text('Lápiz'));
      await tester.pumpAndSettle();
      final g = await tester.startGesture(
        const Offset(500, 600),
        kind: PointerDeviceKind.stylus,
      );
      for (var i = 1; i <= 8; i++) {
        await g.moveTo(Offset(500.0 + i * 20, 600.0 + i * 5));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pumpAndSettle();

      // El dedo en modo lápiz desplaza, no dibuja.
      await tester.dragFrom(const Offset(700, 700), const Offset(0, -40));
      await tester.pumpAndSettle();

      await _exit(tester);
      final note = await _note(tester, db, (n) => n.title == 'Ideas de voz');
      final doc = NoteDocument.decode(note.content);
      expect(doc.strokes, hasLength(1));
      expect(note.body, 'Hablar con KRAFT desde el inicio');
      expect(
        find.text('Ideas de voz'),
        findsOneWidget,
        reason: 'aparece en la cuadrícula',
      );
    },
  );
}
