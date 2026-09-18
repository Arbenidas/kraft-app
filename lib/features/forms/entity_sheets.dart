import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app/router.dart';
import '../../data/db/database.dart';
import '../../data/enums.dart';
import '../../data/providers.dart';
import '../../theme/kraft_colors.dart';
import '../../theme/kraft_tokens.dart';
import '../../theme/kraft_typography.dart';
import '../../utils/dates.dart';
import '../../widgets/entrance.dart';
import '../../widgets/kraft_toast.dart';
import '../../widgets/neo_box.dart';
import '../reminders/reminder_field.dart';
import '../planning/kraft_deadline_picker.dart';
import '../projects/project_cover_store.dart';
import '../../widgets/neo_sheet.dart';
import '../../widgets/tech_badge.dart';
import 'entity_styles.dart';

// ---------------------------------------------------------------------------
// Menú "Crear"
// ---------------------------------------------------------------------------

Future<void> showCreateMenu(BuildContext context, WidgetRef ref) {
  return showNeoSheet(
    context,
    eyebrow: 'NUEVO ELEMENTO',
    title: '¿Qué quieres crear?',
    builder: (sheetContext) {
      final options = [
        (
          'Proyecto',
          'Agrupa lienzos y notas',
          Symbols.folder_open,
          KraftColors.primaryContainer,
          () => showProjectSheet(context, ref),
        ),
        (
          'Nota',
          'Ideas, reuniones y bocetos',
          Symbols.edit_note,
          KraftColors.surfaceContainerLowest,
          () => createNoteAndOpen(context, ref),
        ),
        (
          'Tarea',
          'Algo rápido por hacer',
          Symbols.task_alt,
          KraftColors.secondaryContainer,
          () => showTaskSheet(context, ref),
        ),
        (
          'Evento',
          'Hito en el cronograma',
          Symbols.calendar_today,
          KraftColors.tertiaryContainer,
          () => showEventSheet(context, ref),
        ),
      ];
      return Wrap(
        spacing: KraftSpace.md,
        runSpacing: KraftSpace.md,
        children: [
          for (final (i, (title, subtitle, icon, color, action))
              in options.indexed)
            Entrance(
              index: i,
              child: SizedBox(
                width: 244,
                child: NeoBox(
                  onTap: () {
                    Navigator.pop(sheetContext);
                    action();
                  },
                  color: color,
                  borderWidth: KraftBorder.width,
                  shadow: 3,
                  radius: KraftRadius.lg,
                  padding: const EdgeInsets.all(KraftSpace.md),
                  child: Row(
                    children: [
                      Icon(icon, size: 26),
                      const SizedBox(width: KraftSpace.sm + 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: KraftText.headlineSm.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              subtitle,
                              style: KraftText.bodySm.copyWith(
                                color: KraftColors.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

/// Destino de la acción del widget: abre la app y deja elegir la captura.
Future<void> showCaptureMenu(BuildContext context, WidgetRef ref) =>
    showNeoSheet<void>(
      context,
      eyebrow: 'CAPTURA RÁPIDA',
      title: '¿Qué quieres guardar?',
      builder: (sheetContext) => Wrap(
        spacing: KraftSpace.md,
        children: [
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(sheetContext);
              createNoteAndOpen(context, ref);
            },
            icon: const Icon(Symbols.edit_note),
            label: const Text('Idea / nota'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(sheetContext);
              showTaskSheet(context, ref);
            },
            icon: const Icon(Symbols.task_alt),
            label: const Text('Tarea'),
          ),
        ],
      ),
    );

/// Crea una nota vacía, la selecciona y abre la pestaña Notas.
Future<void> createNoteAndOpen(
  BuildContext context,
  WidgetRef ref, {
  NoteCategory category = NoteCategory.idea,
}) async {
  final id = await ref.read(notesRepositoryProvider).create(category: category);
  ref.read(noteCategoryFilterProvider.notifier).state = null;
  ref.read(noteQueryProvider.notifier).state = '';
  if (context.mounted) context.push(Routes.noteEditor(id));
}

// ---------------------------------------------------------------------------
// Proyecto
// ---------------------------------------------------------------------------

enum ProjectSheetResult { saved, deleted }

Future<ProjectSheetResult?> showProjectSheet(
  BuildContext context,
  WidgetRef ref, {
  Project? project,
}) {
  return showNeoSheet<ProjectSheetResult>(
    context,
    eyebrow: project == null ? 'NUEVO PROYECTO' : 'EDITAR PROYECTO',
    title: project?.title ?? 'Proyecto',
    builder: (_) => _ProjectForm(project: project, toastContext: context),
  );
}

class _ProjectForm extends ConsumerStatefulWidget {
  const _ProjectForm({required this.project, required this.toastContext});

  final Project? project;
  final BuildContext toastContext;

  @override
  ConsumerState<_ProjectForm> createState() => _ProjectFormState();
}

class _ProjectFormState extends ConsumerState<_ProjectForm> {
  late final _title = TextEditingController(text: widget.project?.title);
  late final _description = TextEditingController(
    text: widget.project?.description,
  );
  late final _tags = TextEditingController(
    text: widget.project?.tags.join(' '),
  );
  late ProjectKind _kind = widget.project?.kind ?? ProjectKind.lienzo;
  late String? _cover;

  @override
  void initState() {
    super.initState();
    _cover = widget.project?.imageAsset;
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _tags.dispose();
    super.dispose();
  }

  List<String> get _parsedTags => _tags.text
      .split(RegExp(r'[\s,]+'))
      .where((t) => t.isNotEmpty)
      .map((t) => (t.startsWith('#') ? t : '#$t').toUpperCase())
      .toList();

  Future<void> _save() async {
    final repo = ref.read(projectsRepositoryProvider);
    final title = _title.text.trim();
    if (widget.project == null) {
      await repo.create(
        title: title,
        kind: _kind,
        description: _description.text.trim(),
        tags: _parsedTags,
        imageAsset: _cover,
      );
    } else {
      final previous = widget.project!;
      await repo.update(
        previous.copyWith(
          title: title,
          kind: _kind,
          description: _description.text.trim(),
          tags: _parsedTags,
          imageAsset: Value(_cover),
        ),
      );
      if (previous.imageAsset != _cover) {
        await ProjectCoverStore.discard(previous.imageAsset);
      }
    }
    if (!mounted) return;
    Navigator.pop(context, ProjectSheetResult.saved);
    if (widget.toastContext.mounted) {
      KraftToast.show(
        widget.toastContext,
        widget.project == null ? 'Proyecto creado' : 'Proyecto guardado',
      );
    }
  }

  Future<void> _chooseCover() async {
    final cover = await ProjectCoverStore.choose();
    if (cover == null || !mounted) return;
    final previous = _cover;
    setState(() => _cover = cover);
    if (previous != null && previous != widget.project?.imageAsset) {
      await ProjectCoverStore.discard(previous);
    }
  }

  Future<void> _removeCover() async {
    final previous = _cover;
    setState(() => _cover = null);
    if (previous != null && previous != widget.project?.imageAsset) {
      await ProjectCoverStore.discard(previous);
    }
  }

  Future<void> _delete() async {
    final project = widget.project!;
    await ref.read(projectsRepositoryProvider).delete(project.id);
    if (!mounted) return;
    Navigator.pop(context, ProjectSheetResult.deleted);
    if (widget.toastContext.mounted) {
      KraftToast.show(
        widget.toastContext,
        '"${project.title}" borrado',
        icon: Symbols.delete,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NeoTextField(
          label: 'Nombre',
          controller: _title,
          autofocus: widget.project == null,
          hint: 'Arquitectura de App v3',
        ),
        const SizedBox(height: KraftSpace.md),
        NeoTextField(
          label: 'Descripción',
          controller: _description,
          maxLines: 3,
          hint: 'De qué trata este proyecto',
        ),
        const SizedBox(height: KraftSpace.md),
        _ProjectCoverPicker(
          cover: _cover,
          kind: _kind,
          onChoose: _chooseCover,
          onRemove: _cover == null ? null : _removeCover,
        ),
        const SizedBox(height: KraftSpace.md),
        NeoChoice<ProjectKind>(
          label: 'Tipo',
          value: _kind,
          onChanged: (k) => setState(() => _kind = k),
          options: [for (final k in ProjectKind.values) (k, k.label, k.color)],
        ),
        const SizedBox(height: KraftSpace.md),
        NeoTextField(
          label: 'Etiquetas',
          controller: _tags,
          hint: '#diseño #ui_ux',
        ),
        const SizedBox(height: KraftSpace.lg),
        NeoSheetActions(
          onSave: _title.text.trim().isEmpty ? null : _save,
          saveLabel: widget.project == null ? 'Crear' : 'Guardar',
          onDelete: widget.project == null ? null : _delete,
        ),
      ],
    );
  }
}

class _ProjectCoverPicker extends StatelessWidget {
  const _ProjectCoverPicker({
    required this.cover,
    required this.kind,
    required this.onChoose,
    required this.onRemove,
  });

  final String? cover;
  final ProjectKind kind;
  final Future<void> Function() onChoose;
  final Future<void> Function()? onRemove;

  @override
  Widget build(BuildContext context) {
    final hasCover = cover != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Portada', style: KraftText.labelCode),
            const Spacer(),
            Text(
              hasCover ? '16:9 Personalizada' : 'Automática',
              style: KraftText.labelCode.copyWith(
                fontSize: 10,
                color: KraftColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: KraftSpace.xs),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onChoose,
            borderRadius: BorderRadius.circular(KraftRadius.lg),
            child: Container(
              height: 140,
              width: double.infinity,
              decoration: BoxDecoration(
                color: KraftColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(KraftRadius.lg),
                border: Border.all(
                  color: hasCover
                      ? KraftColors.primary.withValues(alpha: 0.6)
                      : KraftColors.outlineVariant.withValues(alpha: 0.7),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: KraftColors.shadow.withValues(alpha: 0.25),
                    offset: const Offset(0, 2),
                    blurRadius: 6,
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasCover)
                    _CoverImage(path: cover!)
                  else
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            kind.color.withValues(alpha: 0.25),
                            KraftColors.surfaceContainerLowest,
                          ],
                        ),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: KraftColors.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(KraftRadius.md),
                                border: Border.all(color: KraftColors.outlineVariant),
                              ),
                              child: Icon(
                                Symbols.add_photo_alternate,
                                size: 24,
                                color: kind.color,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Toca para elegir una imagen de portada',
                              style: KraftText.bodySm.copyWith(
                                color: KraftColors.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (hasCover) ...[
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.4, 1.0],
                            colors: [
                              Colors.transparent,
                              KraftColors.surfaceContainerLowest.withValues(alpha: 0.85),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: TechBadge(
                        '16:9 PORTADA',
                        background: KraftColors.glass,
                        foreground: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: KraftSpace.sm),
        Wrap(
          spacing: KraftSpace.sm,
          children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: KraftColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(KraftRadius.md),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onPressed: onChoose,
              icon: Icon(
                hasCover ? Symbols.photo_library : Symbols.upload,
                size: 18,
              ),
              label: Text(hasCover ? 'Cambiar imagen' : 'Elegir imagen'),
            ),
            if (onRemove case final remove?)
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: KraftColors.error,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(KraftRadius.md),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: remove,
                icon: const Icon(Symbols.delete_outline, size: 18),
                label: const Text('Quitar imagen'),
              ),
          ],
        ),
      ],
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    if (path.startsWith('assets/')) {
      return Image.asset(path, fit: BoxFit.cover);
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => ColoredBox(
        color: KraftColors.surfaceContainerHigh,
        child: const Center(
          child: Icon(Symbols.broken_image, size: 32),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tarea
// ---------------------------------------------------------------------------

Future<void> showTaskSheet(
  BuildContext context,
  WidgetRef ref, {
  QuickTask? task,
  int? projectId,
  int? requirementId,
}) {
  return showNeoSheet(
    context,
    eyebrow: task == null ? 'NUEVA TAREA' : 'EDITAR TAREA',
    title: task == null ? 'Nota rápida' : 'Tarea',
    builder: (_) => _TaskForm(
      task: task,
      toastContext: context,
      projectId: projectId,
      requirementId: requirementId,
    ),
  );
}

class _TaskForm extends ConsumerStatefulWidget {
  const _TaskForm({
    required this.task,
    required this.toastContext,
    this.projectId,
    this.requirementId,
  });

  final QuickTask? task;
  final BuildContext toastContext;

  /// Proyecto en el que nace la tarea cuando se crea desde su carpeta.
  final int? projectId;
  final int? requirementId;

  @override
  ConsumerState<_TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends ConsumerState<_TaskForm> {
  late final _title = TextEditingController(text: widget.task?.title);
  late final _detail = TextEditingController(text: widget.task?.detail);
  late final _label = TextEditingController(text: widget.task?.label);
  late bool _high = widget.task?.highPriority ?? false;
  late DateTime? _remindAt = widget.task?.remindAt;
  late bool _done = widget.task?.done ?? false;

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _detail.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final repo = ref.read(tasksRepositoryProvider);
    final label = _label.text.trim().isEmpty ? null : _label.text.trim();
    if (widget.task == null) {
      await repo.create(
        title: _title.text.trim(),
        detail: _detail.text.trim(),
        label: label,
        highPriority: _high,
        remindAt: _remindAt,
        projectId: widget.projectId,
        requirementId: widget.requirementId,
      );
    } else {
      final task = widget.task!;
      await repo.update(
        task.copyWith(
          title: _title.text.trim(),
          detail: _detail.text.trim(),
          label: Value(label),
          highPriority: _high,
          remindAt: Value(_remindAt),
          done: _done,
          // Se conserva la fecha original si ya estaba hecha, para no falsear el "Completado hace…".
          completedAt: Value(
            _done ? (task.completedAt ?? DateTime.now()) : null,
          ),
          requirementId: Value(widget.requirementId ?? task.requirementId),
        ),
      );
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final task = widget.task!;
    await deleteTaskWithUndo(widget.toastContext, ref, task);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NeoTextField(
          label: 'Tarea',
          controller: _title,
          autofocus: widget.task == null,
          hint: 'Revisar paleta con cliente',
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _title.text.trim().isEmpty ? null : _save(),
        ),
        const SizedBox(height: KraftSpace.md),
        NeoTextField(
          label: 'Detalle',
          controller: _detail,
          hint: 'Pendiente para la tarde',
        ),
        const SizedBox(height: KraftSpace.md),
        // Sólo al editar: una tarea recién creada nace pendiente.
        if (widget.task != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: NeoChoice<bool>(
              label: 'Estado',
              value: _done,
              onChanged: (v) => setState(() => _done = v),
              options: [
                (false, 'Pendiente', KraftColors.surfaceContainerHigh),
                (true, 'Hecho', KraftColors.secondaryContainer),
              ],
            ),
          ),
          const SizedBox(height: KraftSpace.md),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: NeoTextField(
                label: 'Etiqueta',
                controller: _label,
                hint: 'Lápiz',
              ),
            ),
            SizedBox(width: KraftSpace.md),
            NeoChoice<bool>(
              label: 'Prioridad',
              value: _high,
              onChanged: (v) => setState(() => _high = v),
              options: [
                (false, 'Normal', KraftColors.surfaceContainerHigh),
                (true, 'Alta', KraftColors.primaryContainer),
              ],
            ),
          ],
        ),
        const SizedBox(height: KraftSpace.md),
        ReminderField(
          value: _remindAt,
          onChanged: (at) => setState(() => _remindAt = at),
        ),
        const SizedBox(height: KraftSpace.lg),
        NeoSheetActions(
          onSave: _title.text.trim().isEmpty ? null : _save,
          saveLabel: widget.task == null ? 'Añadir' : 'Guardar',
          onDelete: widget.task == null ? null : _delete,
        ),
      ],
    );
  }
}

Future<void> deleteTaskWithUndo(
  BuildContext context,
  WidgetRef ref,
  QuickTask task,
) async {
  final repo = ref.read(tasksRepositoryProvider);
  final overlay = Overlay.of(context, rootOverlay: true);
  await repo.delete(task.id);
  KraftToast.showOn(
    overlay,
    'Tarea borrada',
    icon: Symbols.delete,
    actionLabel: 'Deshacer',
    onAction: () => repo.restore(task),
  );
}

// ---------------------------------------------------------------------------
// Evento
// ---------------------------------------------------------------------------

Future<void> showEventSheet(
  BuildContext context,
  WidgetRef ref, {
  CalendarEvent? event,
  DateTime? day,
}) {
  return showNeoSheet(
    context,
    eyebrow: event == null ? 'NUEVO HITO' : 'EDITAR HITO',
    title: event == null ? 'Evento' : event.title,
    builder: (_) =>
        _EventForm(event: event, initialDay: day, toastContext: context),
  );
}

class _EventForm extends ConsumerStatefulWidget {
  const _EventForm({
    required this.event,
    required this.initialDay,
    required this.toastContext,
  });

  final CalendarEvent? event;
  final DateTime? initialDay;
  final BuildContext toastContext;

  @override
  ConsumerState<_EventForm> createState() => _EventFormState();
}

class _EventFormState extends ConsumerState<_EventForm> {
  late final _title = TextEditingController(text: widget.event?.title);
  late final _detail = TextEditingController(text: widget.event?.detail);
  late EventTag _tag = widget.event?.tag ?? EventTag.lienzo;
  late DateTime _startsAt = widget.event?.startsAt ?? _defaultStart();

  DateTime _defaultStart() {
    final day = dateOnly(widget.initialDay ?? DateTime.now());
    final now = DateTime.now();
    final hour = isSameDay(day, now) ? (now.hour + 1).clamp(8, 23) : 10;
    return day.add(Duration(hours: hour));
  }

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _detail.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showKraftDeadlinePicker(
      context,
      initial: KraftDeadline(
        day: _startsAt,
        time: TimeOfDay.fromDateTime(_startsAt),
      ),
      timeRequired: true,
      title: 'Fecha y hora',
    );
    if (picked?.dateTime != null) {
      setState(() => _startsAt = picked!.dateTime!);
    }
  }

  Future<void> _pickTime() async {
    await _pickDate();
  }

  Future<void> _save() async {
    final repo = ref.read(eventsRepositoryProvider);
    if (widget.event == null) {
      await repo.create(
        title: _title.text.trim(),
        detail: _detail.text.trim(),
        startsAt: _startsAt,
        tag: _tag,
      );
    } else {
      await repo.update(
        widget.event!.copyWith(
          title: _title.text.trim(),
          detail: _detail.text.trim(),
          startsAt: _startsAt,
          tag: _tag,
        ),
      );
    }
    // Lleva el cronograma al día del evento.
    ref.read(selectedDayProvider.notifier).state = dateOnly(_startsAt);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final event = widget.event!;
    final repo = ref.read(eventsRepositoryProvider);
    await repo.delete(event.id);
    if (!mounted) return;
    Navigator.pop(context);
    if (!widget.toastContext.mounted) return;
    KraftToast.show(
      widget.toastContext,
      'Hito borrado',
      icon: Symbols.delete,
      actionLabel: 'Deshacer',
      onAction: () => repo.restore(event),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    Widget pickerButton(IconData icon, String text, VoidCallback onTap) =>
        Expanded(
          child: NeoBox(
            onTap: onTap,
            borderWidth: 1.5,
            shadow: 2,
            radius: KraftRadius.sm,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    text,
                    overflow: TextOverflow.ellipsis,
                    style: KraftText.labelCode.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NeoTextField(
          label: 'Título',
          controller: _title,
          autofocus: widget.event == null,
          hint: 'Entrega de wireframes',
        ),
        const SizedBox(height: KraftSpace.md),
        NeoTextField(
          label: 'Detalle',
          controller: _detail,
          hint: 'Exportación SVG y checklist',
        ),
        const SizedBox(height: KraftSpace.md),
        Text(
          'CUÁNDO',
          style: KraftText.techBadge.copyWith(
            color: KraftColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            pickerButton(Symbols.calendar_today, longDay(_startsAt), _pickDate),
            const SizedBox(width: KraftSpace.sm),
            SizedBox(
              width: 120,
              child: Row(
                children: [
                  pickerButton(Symbols.schedule, hhmm(_startsAt), _pickTime),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: KraftSpace.md),
        NeoChoice<EventTag>(
          label: 'Tipo',
          value: _tag,
          onChanged: (t) => setState(() => _tag = t),
          options: [
            for (final t in EventTag.values) (t, t.label, t.style.badge),
          ],
        ),
        const SizedBox(height: KraftSpace.lg),
        NeoSheetActions(
          onSave: _title.text.trim().isEmpty ? null : _save,
          saveLabel: widget.event == null ? 'Crear' : 'Guardar',
          onDelete: widget.event == null ? null : _delete,
        ),
      ],
    );
  }
}

/// Elige el proyecto al que pertenece algo (o lo saca). Lo comparten notas, lienzos y tareas.
Future<void> showProjectPicker(
  BuildContext context,
  WidgetRef ref, {
  required int? current,
  required void Function(int?) onPick,
}) {
  final projects = ref.read(projectsProvider(null)).valueOrNull ?? const [];
  return showNeoSheet(
    context,
    eyebrow: 'ORGANIZAR',
    title: 'Mover a un proyecto',
    builder: (sheetContext) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (projects.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: KraftSpace.lg),
            child: Text(
              'No hay proyectos todavía. Crea uno desde Inicio › Proyectos.',
              textAlign: TextAlign.center,
              style: KraftText.bodyMd.copyWith(
                color: KraftColors.onSurfaceVariant,
              ),
            ),
          ),
        for (final project in projects) ...[
          NeoBox(
            onTap: () {
              onPick(project.id);
              Navigator.pop(sheetContext);
            },
            color: project.id == current
                ? KraftColors.primaryContainer
                : KraftColors.surfaceContainerLowest,
            borderWidth: 1.5,
            shadow: project.id == current ? 2 : 0,
            radius: KraftRadius.sm,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(project.kind.icon, size: 18),
                const SizedBox(width: KraftSpace.sm),
                Expanded(
                  child: Text(
                    project.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KraftText.bodyMd.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (project.id == current) const Icon(Symbols.check, size: 18),
              ],
            ),
          ),
          const SizedBox(height: KraftSpace.xs + 2),
        ],
        if (current != null) ...[
          const SizedBox(height: KraftSpace.sm),
          NeoBox(
            onTap: () {
              onPick(null);
              Navigator.pop(sheetContext);
            },
            color: KraftColors.surfaceContainerLowest,
            borderWidth: 1.5,
            radius: KraftRadius.sm,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Symbols.link_off, size: 18),
                const SizedBox(width: KraftSpace.sm),
                Text('Sacar del proyecto', style: KraftText.bodyMd),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}
