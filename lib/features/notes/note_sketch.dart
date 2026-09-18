import 'note_sketch_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../canvas/canvas_codec.dart';
import '../canvas/canvas_document.dart';
import '../canvas/canvas_input.dart';
import '../canvas/canvas_items.dart';
import '../canvas/canvas_models.dart';
import '../canvas/canvas_painters.dart';
import '../canvas/connector_geometry.dart';
import '../canvas/canvas_selection.dart';

class NoteSketchPreview extends StatelessWidget {
  const NoteSketchPreview({
    super.key,
    required this.sketch,
    required this.onEdit,
    required this.onDelete,
  });
  final NoteSketch sketch;
  final VoidCallback onEdit, onDelete;
  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 12),
              const Expanded(child: Text('Boceto de esta nota')),
              IconButton(
                tooltip: 'Editar boceto',
                onPressed: onEdit,
                icon: const Icon(Icons.edit),
              ),
              IconButton(
                tooltip: 'Copiar boceto',
                onPressed: () => Clipboard.setData(
                  ClipboardData(
                    text: 'kraft-sketch:${CanvasCodec.encode(sketch.data)}',
                  ),
                ),
                icon: const Icon(Icons.copy),
              ),
              IconButton(
                tooltip: 'Eliminar boceto',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          AspectRatio(
            aspectRatio: 2,
            child: GestureDetector(
              onTap: onEdit,
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: 640,
                  height: 320,
                  child: _SketchBoard(data: sketch.data),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SketchBoard extends StatelessWidget {
  const _SketchBoard({required this.data});
  final CanvasData data;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.white,
    child: ClipRect(
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _SketchGrid())),
          Positioned.fill(child: CustomPaint(painter: _SketchLinks(data))),
          for (final item in data.items)
            Positioned(
              left: item.position.dx,
              top: item.position.dy,
              child: CanvasItemView(
                item:
                    item.color == null &&
                        (item.type == CanvasItemType.text ||
                            item.type == CanvasItemType.paragraph ||
                            item.type == CanvasItemType.checklist)
                    ? item.copyWith(color: Colors.black)
                    : item,
              ),
            ),
          Positioned.fill(
            child: CustomPaint(painter: StrokesPainter(strokes: data.strokes)),
          ),
        ],
      ),
    ),
  );
}

Future<CanvasData?> editNoteSketch(BuildContext context, CanvasData data) =>
    showDialog<CanvasData>(
      context: context,
      builder: (_) => _SketchEditor(data: data),
    );

class _SketchEditor extends StatefulWidget {
  const _SketchEditor({required this.data});
  final CanvasData data;
  @override
  State<_SketchEditor> createState() => _SketchEditorState();
}

class _SketchEditorState extends State<_SketchEditor> {
  late final doc = CanvasDocument(
    items: widget.data.items,
    strokes: widget.data.strokes,
    links: widget.data.links,
  );
  final viewer = TransformationController();
  final live = LiveStroke();
  final lasso = LassoPath();
  CanvasTool tool = CanvasTool.pen;
  @override
  void dispose() {
    doc.dispose();
    viewer.dispose();
    live.dispose();
    lasso.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SketchEditorHeader(
              tool: tool,
              onTool: (next) => setState(() => tool = next),
              onUndo: doc.undo,
              document: doc,
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) => SizedBox(
                height: (constraints.maxWidth / 2)
                    .clamp(220.0, 320.0)
                    .toDouble(),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: SizedBox(
                          width: 640,
                          height: 320,
                          child: _buildCanvas(context),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(
                    context,
                    CanvasData(
                      items: doc.items,
                      strokes: doc.strokes,
                      links: doc.links,
                    ),
                  ),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Guardar boceto'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildCanvas(BuildContext context) => ClipRect(
    key: const ValueKey('note-sketch-surface'),
    child: CanvasInputLayer(
      enableNavigation: false,
      document: doc,
      viewer: viewer,
      live: live,
      lasso: lasso,
      tool: tool,
      color: const Color(0xFF1C1B1B),
      strokeWidth: 3,
      pressureEnabled: true,
      fingerDraws: true,
      onPencilDetected: () {},
      onPlaced: () => setState(() => tool = CanvasTool.select),
      onEditItem: (item) => _editItem(context, item),
      child: ListenableBuilder(
        listenable: doc,
        builder: (_, _) => Stack(
          children: [
            Positioned.fill(
              child: _SketchBoard(
                data: CanvasData(
                  items: [
                    for (final item in doc.items)
                      item.copyWith(position: doc.itemRect(item).topLeft),
                  ],
                  strokes: doc.strokes,
                  links: doc.links,
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: LiveStrokePainter(live),
                  foregroundPainter: SelectionPainter(doc, scale: 1),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _editItem(BuildContext context, CanvasItem item) async {
    final controller = TextEditingController(text: item.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Texto del boceto'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (title != null && mounted) doc.editItemTitle(item.id, title);
  }
}

class _SketchEditorHeader extends StatelessWidget {
  const _SketchEditorHeader({
    required this.tool,
    required this.onTool,
    required this.onUndo,
    required this.document,
  });

  final CanvasTool tool;
  final ValueChanged<CanvasTool> onTool;
  final VoidCallback onUndo;
  final CanvasDocument document;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.draw_outlined, size: 20),
      const SizedBox(width: 8),
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Boceto', style: TextStyle(fontWeight: FontWeight.w700)),
            Text('Mesa breve · 640 × 320', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
      _SketchToolButton(
        tooltip: 'Dibujar',
        icon: Icons.edit,
        selected: tool == CanvasTool.pen,
        onTap: () => onTool(CanvasTool.pen),
      ),
      _SketchToolButton(
        tooltip: 'Seleccionar',
        icon: Icons.near_me_outlined,
        selected: tool == CanvasTool.select,
        onTap: () => onTool(CanvasTool.select),
      ),
      _SketchToolButton(
        tooltip: 'Añadir texto',
        icon: Icons.title,
        selected: tool == CanvasTool.text,
        onTap: () => onTool(CanvasTool.text),
      ),
      _SketchToolButton(
        tooltip: 'Añadir bloque',
        icon: Icons.crop_square,
        selected: tool == CanvasTool.shapes,
        onTap: () => onTool(CanvasTool.shapes),
      ),
      _SketchToolButton(
        tooltip: 'Borrar',
        icon: Icons.auto_fix_off,
        selected: tool == CanvasTool.eraser,
        onTap: () => onTool(CanvasTool.eraser),
      ),
      ListenableBuilder(
        listenable: document,
        builder: (_, _) => Row(
          children: [
            IconButton(
              tooltip: 'Deshacer',
              onPressed: onUndo,
              icon: const Icon(Icons.undo, size: 20),
            ),
            if (document.hasSelection)
              IconButton(
                tooltip: 'Eliminar selección',
                onPressed: document.deleteSelection,
                icon: const Icon(Icons.delete_outline, size: 20),
              ),
          ],
        ),
      ),
    ],
  );
}

class _SketchToolButton extends StatelessWidget {
  const _SketchToolButton({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onTap,
    style: IconButton.styleFrom(
      backgroundColor: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : Colors.transparent,
      foregroundColor: selected
          ? Theme.of(context).colorScheme.onPrimaryContainer
          : null,
    ),
    icon: Icon(icon, size: 20),
  );
}

class _SketchGrid extends CustomPainter {
  const _SketchGrid();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x142D2925);
    for (var x = 16.0; x < size.width; x += 16) {
      for (var y = 16.0; y < size.height; y += 16) {
        canvas.drawCircle(Offset(x, y), 0.8, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SketchGrid oldDelegate) => false;
}

class _SketchLinks extends CustomPainter {
  _SketchLinks(this.data);
  final CanvasData data;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF555555)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final link in data.links) {
      final from = data.items.where((i) => i.id == link.from).firstOrNull;
      final to = data.items.where((i) => i.id == link.to).firstOrNull;
      if (from == null || to == null) continue;
      final geometry = linkBetween(
        from: from,
        fromRect: from.position & (canvasItemSize(from) * from.zoom),
        to: to,
        toRect: to.position & (canvasItemSize(to) * to.zoom),
        style: link.style,
        arrow: link.arrow,
      );
      if (geometry != null) {
        canvas.drawPath(geometry.line, paint);
        for (final head in geometry.heads()) {
          canvas.drawPath(head, Paint()..color = paint.color);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_SketchLinks old) => old.data != data;
}
