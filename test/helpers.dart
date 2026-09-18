import 'package:drift/drift.dart' show DatabaseConnection, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kraft/data/db/database.dart';
import 'package:kraft/data/providers.dart';
import 'package:kraft/main.dart';
import 'package:kraft/widgets/kraft_nav_bar.dart';

/// Arranca la app sobre una base SQLite en memoria (sembrada por defecto).
/// Por defecto usa un iPad Pro 12.9" en vertical.
Future<AppDatabase> pumpKraft(
  WidgetTester tester, {
  Size size = const Size(1024, 1366),
  bool seed = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  // Cierre síncrono de streams: evita los Timer(0) que `flutter_test` detecta como pendientes.
  final db = AppDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
    seed: seed,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const KraftApp(),
    ),
  );
  await settle(tester);

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });
  return db;
}

/// Deja que Drift entregue sus resultados (asíncronos reales) y termine las animaciones.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> tapNav(WidgetTester tester, String label) async {
  final semanticDestination = find.bySemanticsLabel(label);
  // La barra táctil expone un botón con este nombre; NavigationRail añade
  // información de pestaña al nombre semántico, así que allí tocamos su rótulo.
  final destination = semanticDestination.evaluate().isNotEmpty
      ? semanticDestination.last
      : find
            .descendant(
              of: find.byType(KraftNavigationRail),
              matching: find.text(label.toUpperCase()),
            )
            .last;
  await tester.tap(destination);
  await settle(tester);
}

/// Abre el lienzo de ejemplo en modo lienzo.
Future<void> openCanvasEditor(
  WidgetTester tester, {
  String title = 'Boceto de Arquitectura',
}) async {
  await tapNav(tester, 'Lienzo');
  await tester.tap(find.text(title));
  await settle(tester);
}

/// Un botón de la paleta por su nombre: el tooltip lleva además el atajo de teclado.
Finder toolButton(String label) =>
    find.byTooltip(RegExp('^${RegExp.escape(label)}'));
