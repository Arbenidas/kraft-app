import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../widgets/kraft_top_bar.dart';
import '../ai/ai_connection_sheet.dart';
import '../forms/entity_sheets.dart';
import 'notes_list.dart';

/// Pestaña Notas: cuadrícula de notas. Cada nota se abre como una hoja donde se mezclan
/// texto, escritura a mano, diagramas y enlaces a lienzos.
class NotesScreen extends ConsumerWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        KraftTopBar(
          leading: const KraftBrand(breadcrumb: 'Notas'),
          actions: [
            const AiConnectButton(),
            TopBarIconButton(
              icon: Symbols.add,
              tooltip: 'Nueva nota',
              highlighted: true,
              onTap: () => createNoteAndOpen(context, ref),
            ),
            const KraftAvatar(),
          ],
        ),
        const Expanded(child: NotesList()),
      ],
    );
  }
}
