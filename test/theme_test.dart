import 'dart:ui' show Brightness;

import 'package:flutter_test/flutter_test.dart';
import 'package:kraft/features/canvas/canvas_items.dart';
import 'package:kraft/features/notes/note_text.dart';
import 'package:kraft/theme/kraft_colors.dart';
import 'package:kraft/theme/kraft_typography.dart';

void main() {
  // La paleta es global y mutable: hay que dejarla como estaba.
  tearDown(() => KraftColors.use(Brightness.light));

  test('todo lo que pinta color sigue al tema al cambiarlo', () {
    KraftColors.use(Brightness.light);
    final claro = (
      body: NoteStyles.body.color,
      titulo: NoteStyles.title.color,
      casilla: NoteStyles.checkbox.color,
      relleno: canvasFillColors.first.$1,
      tinta: canvasInkColors.first.$1,
      texto: KraftText.bodyMd.color,
    );

    KraftColors.use(Brightness.dark);

    // Un `static final` se calcula una vez y se queda con el color de ese momento:
    // así es como la nota seguía en claro después de pasar a oscuro.
    expect(NoteStyles.body.color, isNot(claro.body));
    expect(NoteStyles.title.color, isNot(claro.titulo));
    expect(NoteStyles.checkbox.color, isNot(claro.casilla));
    expect(canvasFillColors.first.$1, isNot(claro.relleno));
    expect(canvasInkColors.first.$1, isNot(claro.tinta));
    expect(KraftText.bodyMd.color, isNot(claro.texto));
  });
}
