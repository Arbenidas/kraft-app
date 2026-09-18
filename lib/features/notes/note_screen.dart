import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app/router.dart';
import '../../data/providers.dart';
import '../../data/repositories.dart';
import '../../platform/apple_pencil.dart';
import '../../theme/kraft_colors.dart';
import '../../theme/kraft_motion.dart';
import '../../theme/kraft_tokens.dart';
import '../../theme/kraft_typography.dart';
import '../ai/ai_providers.dart';
import '../canvas/canvas_models.dart';
import '../canvas/canvas_painters.dart';
import '../canvas/link_picker.dart';
import '../canvas/stroke_geometry.dart';
import 'note_bridge.dart';
import 'note_document.dart';
import 'note_sketch_model.dart';
import 'note_sketch.dart';
import '../canvas/canvas_codec.dart';
import '../forms/entity_sheets.dart';
import 'note_text.dart';
import 'notes_list.dart';
import 'note_ai_sheet.dart';
import '../voice/assistant_markdown.dart';

enum NoteMode { text, pen, eraser }

/// Una nota como documento, al estilo de Notas de Apple: se escribe de corrido con el teclado
/// (o a mano con Scribble), el lápiz dibuja encima de la página y se enlazan lienzos y notas.
/// Se guarda sola mientras se escribe y al salir.
class NoteScreen extends ConsumerStatefulWidget {
  const NoteScreen({super.key, required this.noteId});

  final int noteId;

  static const saveDelay = Duration(milliseconds: 600);
  static const pageWidth = NotePage.width;

  @override
  ConsumerState<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends ConsumerState<NoteScreen>
    implements LiveNote, LiveSketchNote {
  late final NotesRepository _repo;
  late final NoteBridge _bridge;
  final _text = NoteTextController();
  final _textUndo = UndoHistoryController();
  final _focus = FocusNode(debugLabel: 'nota');
  final _scroll = ScrollController();
  final _live = LiveStroke();
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<PencilEvent>? _pencil;

  bool _loaded = false;
  bool _missing = false;
  bool _exiting = false;
  String _saved = '';
  String _lastText = '';
  Timer? _saveTimer;

  List<Stroke> _strokes = const [];
  List<NoteLink> _links = const [];
  List<NoteSketch> _sketches = const [];
  int _nextStrokeId = 1;

  /// Historial común: qué se deshace primero, el texto o la tinta.
  final _edits = <_Edit>[];
  final _redoEdits = <_Edit>[];
  final _inkUndo = <List<Stroke>>[];
  final _inkRedo = <List<Stroke>>[];

  NoteMode _mode = NoteMode.text;
  NoteMode _lastInkMode = NoteMode.pen;
  Color _inkColor = KraftColors.ink;
  bool _fingerDraws = false;
  bool _markdownPreview = false;
  int? _drawingPointer;
  bool _erasing = false;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(notesRepositoryProvider);
    _bridge = ref.read(noteBridgeProvider)..attach(this);
    _lifecycle = AppLifecycleListener(onHide: _save, onInactive: _save);
    _pencil = ApplePencil.events.listen((_) {
      // Doble toque del lápiz: alterna lápiz y borrador.
      if (_mode != NoteMode.text)
        _setMode(_mode == NoteMode.eraser ? NoteMode.pen : NoteMode.eraser);
    });
    _text.addListener(_onTextChanged);
    _load();
  }

  Future<void> _load() async {
    final note = await _repo.get(widget.noteId);
    final checklist = note == null || note.content.trim().isNotEmpty
        ? const <Never>[]
        : await _repo.checklist(widget.noteId);
    final fingerDraws =
        await ref.read(settingsRepositoryProvider).get('canvas.fingerDraws') ==
        'true';
    if (!mounted) return;
    if (note == null) {
      setState(() => _missing = true);
      return;
    }
    final doc = NoteDocument.decode(
      note.content,
      legacy: note,
      checklist: checklist,
    );
    _lastText = doc.text;
    _text.value = TextEditingValue(
      text: doc.text,
      selection: TextSelection.collapsed(offset: doc.text.length),
    );
    _textUndo.value = UndoHistoryValue.empty;
    setState(() {
      _strokes = doc.strokes;
      _links = doc.links;
      _sketches = doc.sketches;
      _nextStrokeId = doc.strokes.fold(0, (m, s) => math.max(m, s.id)) + 1;
      _saved = doc.encode();
      _fingerDraws = fingerDraws;
      _loaded = true;
    });
    // Nota nueva: directamente a escribir.
    if (doc.text.trim().isEmpty && doc.strokes.isEmpty) _focus.requestFocus();
  }

  NoteDocument get _document => NoteDocument(
    text: _text.text,
    strokes: _strokes,
    links: _links,
    sketches: _sketches,
  );

  void _onTextChanged() {
    if (_text.text == _lastText) return;
    _lastText = _text.text;
    if (_edits.isEmpty || _edits.last != _Edit.text) _edits.add(_Edit.text);
    _redoEdits.clear();
    _scheduleSave();
    setState(() {});
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(NoteScreen.saveDelay, _save);
  }

  Future<void> _save() async {
    _saveTimer?.cancel();
    if (!_loaded) return;
    final doc = _document;
    final encoded = doc.encode();
    if (encoded == _saved) return;
    _saved = encoded;
    final title = doc.title;
    await _repo.saveContent(
      widget.noteId,
      title: title.length > 200 ? title.substring(0, 200) : title,
      content: encoded,
      body: doc.body,
    );
  }

  /// Mueve la nota a un proyecto desde su propio menú.
  Future<void> _moveToProject() async {
    final note = await _repo.get(widget.noteId);
    if (note == null || !mounted) return;
    await showProjectPicker(
      context,
      ref,
      current: note.projectId,
      onPick: (id) => _repo.setProject(widget.noteId, id),
    );
  }

  Future<void> _saveAndExit() async {
    if (_exiting) return;
    _exiting = true;
    _live.cancel();
    await _save();
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.notes);
    }
  }

  @override
  void dispose() {
    if (_loaded && !_exiting && _document.encode() != _saved) {
      final doc = _document;
      _repo.saveContent(
        widget.noteId,
        title: doc.title,
        content: doc.encode(),
        body: doc.body,
      );
    }
    _saveTimer?.cancel();
    _bridge.detach(this);
    _lifecycle.dispose();
    _pencil?.cancel();
    _text.dispose();
    _textUndo.dispose();
    _focus.dispose();
    _scroll.dispose();
    _live.dispose();
    super.dispose();
  }

  // ---- LiveNote (asistente de voz) ----

  @override
  int get noteId => widget.noteId;

  @override
  String get noteText => _text.text;

  @override
  void appendText(String text) {
    if (!_loaded) return;
    _text.appendText(text);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: KraftMotion.slow,
          curve: KraftMotion.settle,
        );
      }
    });
  }

  @override
  bool replaceTextIfUnchanged(String expected, String replacement) {
    if (!_loaded || _text.text != expected) return false;
    _text.value = TextEditingValue(
      text: replacement,
      selection: TextSelection.collapsed(offset: replacement.length),
    );
    _scheduleSave();
    return true;
  }

  @override
  List<Stroke> get noteStrokes => _strokes;

  @override
  void addStrokes(List<Stroke> strokes) {
    if (!_loaded || strokes.isEmpty) return;
    setState(() {
      // Un boceto entero es un solo paso de deshacer, como un trazo del lápiz.
      _pushInkUndo();
      _strokes = [..._strokes, ...strokes];
      _nextStrokeId = math.max(
        _nextStrokeId,
        strokes.fold(0, (m, s) => math.max(m, s.id)) + 1,
      );
    });
    _scheduleSave();
    // Que se vea lo que acaba de dibujar aunque estuviera fuera de la pantalla.
    final bottom = strokes.fold(0.0, (m, s) => math.max(m, s.bounds.bottom));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        math.min(bottom, _scroll.position.maxScrollExtent),
        duration: KraftMotion.slow,
        curve: KraftMotion.settle,
      );
    });
  }

  @override
  void focusText(String phrase) {
    if (!_loaded) return;
    final wanted = phrase.trim();
    if (wanted.isEmpty) return;
    final start = _text.text.toLowerCase().indexOf(wanted.toLowerCase());
    if (start < 0) return;
    _text.selection = TextSelection(
      baseOffset: start,
      extentOffset: start + wanted.length,
    );
    _focus.requestFocus();
    HapticFeedback.selectionClick();
  }

  @override
  Future<void> persist() => _save();

  // ---- Modos y formato ----

  void _setMode(NoteMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      if (mode != NoteMode.text) _markdownPreview = false;
      if (mode != NoteMode.text) _lastInkMode = mode;
    });
    if (mode == NoteMode.text) {
      _focus.requestFocus();
    } else {
      _focus.unfocus();
    }
    HapticFeedback.selectionClick();
  }

  void _format(void Function() apply) {
    if (_mode != NoteMode.text) _setMode(NoteMode.text);
    _focus.requestFocus();
    apply();
  }

  void _onTextTap() {
    if (_text.toggleCheckboxAtSelection()) HapticFeedback.selectionClick();
  }

  // ---- Tinta ----

  bool _acceptsPointer(PointerDownEvent e) =>
      e.kind == PointerDeviceKind.stylus ||
      e.kind == PointerDeviceKind.invertedStylus ||
      e.kind == PointerDeviceKind.mouse ||
      _fingerDraws;

  void _pushInkUndo() {
    _inkUndo.add(_strokes);
    _inkRedo.clear();
    _edits.add(_Edit.ink);
    _redoEdits.clear();
  }

  void _onInkDown(PointerDownEvent e) {
    if (_drawingPointer != null || !_acceptsPointer(e)) return;
    final eraser =
        _mode == NoteMode.eraser || e.kind == PointerDeviceKind.invertedStylus;
    setState(() => _drawingPointer = e.pointer);
    if (eraser) {
      _erasing = false;
      _eraseAt(e.localPosition);
    } else {
      _live.start(
        e.localPosition,
        color: _inkColor,
        width: 3,
        highlighter: false,
        pressure: StrokePressure.normalized(e),
      );
    }
  }

  void _onInkMove(PointerMoveEvent e) {
    if (e.pointer != _drawingPointer) return;
    if (_live.isActive) {
      _live.add(e.localPosition, pressure: StrokePressure.normalized(e));
    } else {
      _eraseAt(e.localPosition);
    }
  }

  void _onInkUp(PointerEvent e) {
    if (e.pointer != _drawingPointer) return;
    final stroke = _live.finish(_nextStrokeId++);
    setState(() {
      _drawingPointer = null;
      if (stroke != null && e is PointerUpEvent) {
        _pushInkUndo();
        _strokes = [..._strokes, stroke];
      }
    });
    if (stroke != null || _erasing) _scheduleSave();
  }

  void _eraseAt(Offset point) {
    var changed = false;
    final next = <Stroke>[];
    for (final s in _strokes) {
      final pieces = s.erasedAround(point, 12, () => _nextStrokeId++);
      if (pieces == null) {
        next.add(s);
      } else {
        changed = true;
        next.addAll(pieces);
      }
    }
    if (!changed) return;
    setState(() {
      if (!_erasing) {
        _pushInkUndo();
        _erasing = true;
      }
      _strokes = next;
    });
  }

  // ---- Deshacer ----

  bool get _canUndo => _edits.isNotEmpty || _textUndo.value.canUndo;
  bool get _canRedo => _redoEdits.isNotEmpty || _textUndo.value.canRedo;

  void _undo() {
    final kind = _edits.isNotEmpty ? _edits.removeLast() : _Edit.text;
    if (kind == _Edit.ink && _inkUndo.isNotEmpty) {
      _inkRedo.add(_strokes);
      setState(() => _strokes = _inkUndo.removeLast());
    } else {
      _textUndo.undo();
      // Si aún queda texto por deshacer, el siguiente paso sigue siendo de texto.
      if (_textUndo.value.canUndo) _edits.add(_Edit.text);
    }
    _redoEdits.add(kind);
    _scheduleSave();
  }

  void _redo() {
    final kind = _redoEdits.isNotEmpty ? _redoEdits.removeLast() : _Edit.text;
    if (kind == _Edit.ink && _inkRedo.isNotEmpty) {
      _inkUndo.add(_strokes);
      setState(() => _strokes = _inkRedo.removeLast());
    } else {
      _textUndo.redo();
    }
    _edits.add(kind);
    _scheduleSave();
  }

  // ---- Enlaces ----

  Future<void> _addLink() async {
    final picked = await showLinkPicker(
      context,
      exclude: 'note:${widget.noteId}',
    );
    if (picked == null || !mounted) return;
    final link = NoteLink(target: picked.target, title: picked.title);
    if (_links.contains(link)) return;
    setState(() => _links = [..._links, link]);
    _scheduleSave();
    HapticFeedback.lightImpact();
  }

  void _removeLink(NoteLink link) {
    setState(
      () => _links = [
        for (final l in _links)
          if (l != link) l,
      ],
    );
    _scheduleSave();
  }

  Future<void> _openLink(NoteLink link) async {
    final id = link.id;
    if (id == null) return;
    await _save();
    if (mounted)
      context.push(
        link.isNote ? Routes.noteEditor(id) : Routes.canvasEditor(id),
      );
  }

  Future<void> _delete() async {
    _saveTimer?.cancel();
    _exiting = true;
    await deleteNoteWithUndo(context, ref, widget.noteId);
    if (!mounted) return;
    context.canPop() ? context.pop() : context.go(Routes.notes);
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Scaffold(
      backgroundColor: KraftColors.surface,
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _saveAndExit();
        },
        child: Column(
          children: [
            ListenableBuilder(
              listenable: _textUndo,
              builder: (context, _) => _NoteTopBar(
                title: _document.title,
                canUndo: _canUndo,
                canRedo: _canRedo,
                onBack: _saveAndExit,
                onUndo: _undo,
                onRedo: _redo,
                onLink: _addLink,
                onProject: _moveToProject,
                onDelete: _delete,
                onAi: () {
                  final selection = _text.selection;
                  final selected = selection.isValid && !selection.isCollapsed
                      ? selection.textInside(_text.text)
                      : '';
                  showNoteAiSheet(
                    context,
                    ref,
                    text: _text.text,
                    selectedText: selected,
                    onApply: (replacement) {
                      if (selection.isValid && !selection.isCollapsed) {
                        _text.value = _text.value.copyWith(
                          text: _text.text.replaceRange(
                            selection.start,
                            selection.end,
                            replacement,
                          ),
                          selection: TextSelection.collapsed(
                            offset: selection.start + replacement.length,
                          ),
                        );
                      } else {
                        _text.value = TextEditingValue(
                          text: replacement,
                          selection: TextSelection.collapsed(
                            offset: replacement.length,
                          ),
                        );
                      }
                      _scheduleSave();
                    },
                  );
                },
              ),
            ),
            Expanded(
              child: _missing
                  ? Center(
                      child: Text(
                        'Esta nota ya no existe',
                        style: KraftText.headlineSm,
                      ),
                    )
                  : !_loaded
                  ? Center(
                      child: CircularProgressIndicator(color: KraftColors.ink),
                    )
                  : Stack(
                      children: [
                        Positioned.fill(child: _buildPage()),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: KraftSpace.lg,
                          child: Center(
                            child: _NoteToolbar(
                              mode: _mode,
                              inkColor: _inkColor,
                              onMode: _setMode,
                              onInkColor: (c) => setState(() {
                                _inkColor = c;
                                if (_mode == NoteMode.text)
                                  _setMode(_lastInkMode);
                              }),
                              onTask: () => _format(_text.toggleTaskLine),
                              onHeading: () => _format(_text.toggleHeadingLine),
                              onLink: _addLink,
                              preview: _markdownPreview,
                              onPreview: () => setState(() {
                                _markdownPreview = !_markdownPreview;
                                if (_markdownPreview) _focus.unfocus();
                              }),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void addSketch(NoteSketch sketch) {
    setState(() => _sketches = [..._sketches, sketch]);
    _scheduleSave();
  }

  Future<void> _editSketch([NoteSketch? sketch]) async {
    final data = await editNoteSketch(
      context,
      sketch?.data ?? const CanvasData(),
    );
    if (data == null || !mounted) return;
    final result = NoteSketch(
      id: sketch?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      data: data,
    );
    setState(
      () => _sketches = sketch == null
          ? [..._sketches, result]
          : [for (final s in _sketches) s.id == sketch.id ? result : s],
    );
    await _save();
  }

  Future<void> _pasteSketch() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (!mounted || text == null || !text.startsWith('kraft-sketch:')) return;
    setState(
      () => _sketches = [
        ..._sketches,
        NoteSketch(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          data: CanvasCodec.decode(text.substring('kraft-sketch:'.length)),
        ),
      ],
    );
    await _save();
  }

  Widget _buildPage() {
    final inkBottom = _strokes.fold(
      0.0,
      (m, s) => math.max(m, s.bounds.bottom),
    );
    return LayoutBuilder(
      builder: (context, constraints) => ScrollConfiguration(
        // El lápiz no desplaza la página: escribe (Scribble) o dibuja. Los dedos sí.
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.trackpad,
            PointerDeviceKind.mouse,
          },
        ),
        child: SingleChildScrollView(
          controller: _scroll,
          physics: _drawingPointer != null
              ? const NeverScrollableScrollPhysics()
              : null,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: NoteScreen.pageWidth,
                minHeight: math.max(constraints.maxHeight, inkBottom + 320),
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: NotePage.padding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_markdownPreview)
                          GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: () =>
                                setState(() => _markdownPreview = false),
                            child: _NoteMarkdownPreview(text: _text.text),
                          )
                        else
                          TextField(
                            controller: _text,
                            undoController: _textUndo,
                            focusNode: _focus,
                            readOnly: _mode != NoteMode.text,
                            showCursor: _mode == NoteMode.text,
                            textInputAction: TextInputAction.newline,
                            maxLines: null,
                            keyboardType: TextInputType.multiline,
                            textCapitalization: TextCapitalization.sentences,
                            inputFormatters: const [
                              TaskContinuationFormatter(),
                            ],
                            cursorColor: KraftColors.ink,
                            style: NoteStyles.body,
                            onTap: _onTextTap,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              isCollapsed: true,
                              hintText:
                                  'Título\nEscribe tu idea con el teclado o a mano con el lápiz…',
                              hintStyle: NoteStyles.body.copyWith(
                                color: KraftColors.outline,
                              ),
                              hintMaxLines: 3,
                            ),
                          ),
                        Wrap(
                          children: [
                            TextButton.icon(
                              onPressed: () => _editSketch(),
                              icon: const Icon(Icons.draw),
                              label: const Text('Insertar boceto'),
                            ),
                            TextButton.icon(
                              onPressed: _pasteSketch,
                              icon: const Icon(Icons.paste),
                              label: const Text('Pegar boceto'),
                            ),
                          ],
                        ),
                        for (final sketch in _sketches)
                          NoteSketchPreview(
                            sketch: sketch,
                            onEdit: () => _editSketch(sketch),
                            onDelete: () {
                              setState(
                                () =>
                                    _sketches = [..._sketches]..remove(sketch),
                              );
                              _save();
                            },
                          ),
                        if (_links.isNotEmpty) ...[
                          const SizedBox(height: KraftSpace.lg),
                          Wrap(
                            spacing: KraftSpace.sm,
                            runSpacing: KraftSpace.sm,
                            children: [
                              for (final link in _links)
                                _LinkChip(
                                  link: link,
                                  onOpen: () => _openLink(link),
                                  onRemove: () => _removeLink(link),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Tinta: siempre visible; sólo recibe el lápiz en los modos Lápiz y Borrador.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: StrokesPainter(strokes: _strokes),
                          foregroundPainter: LiveStrokePainter(_live),
                        ),
                      ),
                    ),
                  ),
                  if (_mode != NoteMode.text)
                    Positioned.fill(
                      child: Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: _onInkDown,
                        onPointerMove: _onInkMove,
                        onPointerUp: _onInkUp,
                        onPointerCancel: _onInkUp,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _Edit { text, ink }

/// Vista de lectura para contenido generado con Markdown. Se apoya en el mismo
/// renderer que el chat para que el código, listas y encabezados no se vean
/// como texto sin formato dentro de una nota.
class _NoteMarkdownPreview extends StatelessWidget {
  const _NoteMarkdownPreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) {
      return Text(
        'La vista Markdown aparecerá aquí cuando escribas contenido.',
        style: NoteStyles.body.copyWith(color: KraftColors.outline),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Symbols.visibility, size: 16),
            const SizedBox(width: KraftSpace.xs),
            Text(
              'VISTA MARKDOWN · toca para editar',
              style: KraftText.techBadge,
            ),
          ],
        ),
        const SizedBox(height: KraftSpace.md),
        AssistantMarkdown(text: text),
      ],
    );
  }
}

class _NoteTopBar extends StatelessWidget {
  const _NoteTopBar({
    required this.title,
    required this.canUndo,
    required this.canRedo,
    required this.onBack,
    required this.onUndo,
    required this.onRedo,
    required this.onLink,
    required this.onProject,
    required this.onDelete,
    required this.onAi,
  });

  final String title;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onBack;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onLink;
  final VoidCallback onProject;
  final VoidCallback onDelete;
  final VoidCallback onAi;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Container(
      color: KraftColors.surface,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 60,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: KraftSpace.sm),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: onBack,
                  style: TextButton.styleFrom(foregroundColor: KraftColors.ink),
                  icon: const Icon(Symbols.arrow_back_ios_new, size: 20),
                  label: Text(
                    'Notas',
                    style: KraftText.bodyLg.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KraftText.labelCode.copyWith(
                      color: KraftColors.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Deshacer',
                  onPressed: canUndo ? onUndo : null,
                  icon: const Icon(Symbols.undo),
                ),
                IconButton(
                  tooltip: 'Rehacer',
                  onPressed: canRedo ? onRedo : null,
                  icon: const Icon(Symbols.redo),
                ),
                IconButton(
                  tooltip: 'IA para la nota',
                  onPressed: onAi,
                  icon: const Icon(Symbols.auto_awesome),
                ),
                PopupMenuButton<VoidCallback>(
                  tooltip: 'Más opciones',
                  icon: const Icon(Symbols.more_horiz),
                  color: KraftColors.surfaceContainerLowest,
                  onSelected: (action) => action(),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: onLink,
                      child: const ListTile(
                        leading: Icon(Symbols.add_link),
                        title: Text('Enlazar lienzo o nota'),
                      ),
                    ),
                    PopupMenuItem(
                      value: onProject,
                      child: const ListTile(
                        leading: Icon(Symbols.folder),
                        title: Text('Mover a proyecto'),
                      ),
                    ),
                    PopupMenuItem(
                      value: onDelete,
                      child: ListTile(
                        leading: Icon(Symbols.delete, color: KraftColors.error),
                        title: Text(
                          'Borrar nota',
                          style: TextStyle(color: KraftColors.error),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Barra mínima: modo (texto, lápiz, borrador), formato de la línea y enlace.
class _NoteToolbar extends StatelessWidget {
  const _NoteToolbar({
    required this.mode,
    required this.inkColor,
    required this.onMode,
    required this.onInkColor,
    required this.onTask,
    required this.onHeading,
    required this.onLink,
    required this.preview,
    required this.onPreview,
  });

  final NoteMode mode;
  final Color inkColor;
  final ValueChanged<NoteMode> onMode;
  final ValueChanged<Color> onInkColor;
  final VoidCallback onTask;
  final VoidCallback onHeading;
  final VoidCallback onLink;
  final bool preview;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: KraftColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(999),
        border: KraftBorder.ink(),
        boxShadow: KraftShadow.hard(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeButton(
            icon: Symbols.text_fields,
            label: 'Texto',
            selected: mode == NoteMode.text && !preview,
            onTap: () {
              if (preview) onPreview();
              onMode(NoteMode.text);
            },
          ),
          _ModeButton(
            icon: Symbols.visibility,
            label: 'Vista',
            selected: preview,
            onTap: onPreview,
          ),
          _ModeButton(
            icon: Symbols.draw,
            label: 'Lápiz',
            selected: mode == NoteMode.pen,
            onTap: () => onMode(NoteMode.pen),
          ),
          _ModeButton(
            icon: Symbols.ink_eraser,
            label: 'Borrador',
            selected: mode == NoteMode.eraser,
            onTap: () => onMode(NoteMode.eraser),
          ),
          AnimatedSize(
            duration: KraftMotion.of(context, KraftMotion.base),
            curve: KraftMotion.settle,
            child: mode == NoteMode.text
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _Divider(),
                      _IconAction(
                        icon: Symbols.check_box,
                        tooltip: 'Tarea',
                        onTap: onTask,
                      ),
                      _IconAction(
                        icon: Symbols.format_h2,
                        tooltip: 'Encabezado',
                        onTap: onHeading,
                      ),
                      _IconAction(
                        icon: Symbols.add_link,
                        tooltip: 'Enlazar lienzo o nota',
                        onTap: onLink,
                      ),
                    ],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _Divider(),
                      for (final (color, name) in canvasColors)
                        Tooltip(
                          message: name,
                          child: GestureDetector(
                            onTap: () => onInkColor(color),
                            child: Container(
                              width: 34,
                              height: 34,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: color == inkColor
                                      ? KraftColors.ink
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: KraftMotion.of(context, KraftMotion.fast),
          curve: KraftMotion.settle,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? KraftColors.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected
                    ? KraftColors.primaryContainer
                    : KraftColors.onSurface,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: KraftText.labelCode.copyWith(
                  fontWeight: FontWeight.w700,
                  color: selected ? KraftColors.surface : KraftColors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, size: 22, color: KraftColors.onSurface),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Container(
      width: 1,
      height: 26,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: KraftColors.outlineVariant,
    );
  }
}

class _LinkChip extends StatelessWidget {
  const _LinkChip({
    required this.link,
    required this.onOpen,
    required this.onRemove,
  });

  final NoteLink link;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return Material(
      color: link.isNote
          ? KraftColors.secondaryContainer
          : KraftColors.tertiaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KraftRadius.md),
        side: BorderSide(color: KraftColors.ink, width: 1.5),
      ),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(KraftRadius.md),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                link.isNote ? Symbols.sticky_note_2 : Symbols.gesture,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                link.title.isEmpty ? 'Sin título' : link.title,
                style: KraftText.bodyMd.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 2),
              const Icon(Symbols.north_east, size: 16),
              IconButton(
                tooltip: 'Quitar enlace',
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
                icon: const Icon(Symbols.close, size: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
