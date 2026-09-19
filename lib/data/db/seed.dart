import 'package:drift/drift.dart';

import '../../features/canvas/canvas_codec.dart';
import '../enums.dart';
import 'database.dart';

Future<void> seedCanvas(AppDatabase db) {
  return db
      .into(db.canvases)
      .insert(
        CanvasesCompanion.insert(
          title: 'Boceto de Arquitectura',
          data: Value(CanvasCodec.seed()),
        ),
      );
}

/// Contenido inicial basado en las vistas de Stitch, con fechas relativas a [now].
Future<void> seedDatabase(AppDatabase db, DateTime now) async {
  final today = DateTime(now.year, now.month, now.day);

  await db.transaction(() async {
    await seedCanvas(db);
    final archId = await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            title: 'Arquitectura de App v2',
            description: const Value(
              'Diagrama de módulos, sincronización distribuida y persistencia en memoria local.',
            ),
            kind: ProjectKind.lienzo,
            tags: const Value(['#SISTEMA', '#DIAGRAMA']),
            imageAsset: const Value('assets/images/project_1.jpg'),
            updatedAt: Value(now.subtract(const Duration(minutes: 15))),
          ),
        );
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            title: 'Bocetos Pantalla iPad',
            description: const Value(
              'Flujo de interacción táctil, gestos para Apple Pencil y paletas contextuales.',
            ),
            kind: ProjectKind.stylus,
            tags: const Value(['#DISEÑO', '#UI_UX']),
            imageAsset: const Value('assets/images/project_2.jpg'),
            updatedAt: Value(now.subtract(const Duration(hours: 1))),
          ),
        );
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            title: 'Lista de Funcionalidades',
            description: const Value(
              'Ajustes en el motor de trazo suave, curvas de presión y exportación SVG limpia.',
            ),
            kind: ProjectKind.nota,
            tags: const Value(['#MOTOR', '#NOTAS']),
            imageAsset: const Value('assets/images/project_3.jpg'),
            updatedAt: Value(now.subtract(const Duration(days: 1))),
          ),
        );

    final noteId = await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            projectId: Value(archId),
            title: const Value('Diseño de Experiencia iPad & Stylus'),
            keyIdea: const Value(
              'La interacción táctil debe alternar de forma transparente entre navegación suave con los dedos y trazo preciso con el Apple Pencil, sin fricción de modos manuales.',
            ),
            body: const Value(
              'Para mantener una sensación analógica y moderna, las respuestas cinéticas de la pantalla deben reducir la latencia de dibujo al mínimo posible, reconociendo intenciones antes del toque físico.',
            ),
            category: NoteCategory.boceto,
            updatedAt: Value(now.subtract(const Duration(minutes: 10))),
          ),
        );
    for (final (i, (text, done)) in const [
      ('Detectar apoyo de la palma de la mano (Palm rejection nativo)', true),
      ('Sensibilidad a la presión para variar grosor del trazo orgánico', true),
      ('Menú radial flotante para cambio rápido de herramientas', false),
    ].indexed) {
      await db
          .into(db.checklistItems)
          .insert(
            ChecklistItemsCompanion.insert(
              noteId: noteId,
              content: text,
              done: Value(done),
              position: i,
            ),
          );
    }
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            title: const Value('Reunión de kickoff con cliente'),
            body: const Value(
              'Alcance de la primera entrega, paleta de marca y calendario de revisiones.',
            ),
            category: NoteCategory.reunion,
            updatedAt: Value(now.subtract(const Duration(days: 2))),
          ),
        );

    await db.batch((b) {
      b.insertAll(db.tasks, [
        TasksCompanion.insert(
          title: 'Optimizar fluidez de dibujo a 120Hz',
          done: const Value(true),
          completedAt: Value(now),
        ),
        TasksCompanion.insert(
          title: 'Ajustar tolerancia de presión en Apple Pencil',
          highPriority: const Value(true),
          label: const Value('Lápiz'),
        ),
        TasksCompanion.insert(
          title: 'Exportar esquemas de color para cliente',
          detail: const Value('Pendiente para la tarde'),
        ),
      ]);
      b.insertAll(db.events, [
        EventsCompanion.insert(
          title: 'Review Arquitectura iPad',
          detail: const Value('Sincronización canvas con equipo de diseño'),
          startsAt: today.add(const Duration(hours: 10, minutes: 30)),
          tag: EventTag.lienzo,
          projectId: Value(archId),
        ),
        EventsCompanion.insert(
          title: 'Entrega de Wireframes V2',
          detail: const Value('Exportación SVG y checklist de componentes'),
          startsAt: today.add(const Duration(hours: 16)),
          tag: EventTag.urgente,
        ),
        EventsCompanion.insert(
          title: 'Sesión de bocetos',
          detail: const Value('Pantallas de onboarding'),
          startsAt: today.add(const Duration(days: 1, hours: 11)),
          tag: EventTag.nota,
        ),
        EventsCompanion.insert(
          title: 'Sync con cliente',
          detail: const Value('Revisión de paleta y tipografía'),
          startsAt: today.add(const Duration(days: 3, hours: 9)),
          tag: EventTag.reunion,
        ),
      ]);
    });
  });
}
