import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app/router.dart';
import '../../data/db/database.dart';
import '../../data/providers.dart';
import '../../theme/kraft_colors.dart';
import '../../theme/kraft_tokens.dart';
import '../../theme/kraft_typography.dart';
import '../../utils/dates.dart';
import '../../widgets/entrance.dart';
import '../../widgets/kraft_toast.dart';
import '../forms/entity_sheets.dart';
import '../../widgets/kraft_top_bar.dart';
import '../../widgets/neo_box.dart';
import '../ai/ai_connection_sheet.dart';
import 'canvas_codec.dart';
import 'canvas_items.dart';
import 'canvas_models.dart';

/// Crea un lienzo vacío y entra en modo lienzo.
Future<void> createCanvasAndOpen(BuildContext context, WidgetRef ref) async {
  final id = await ref.read(canvasesRepositoryProvider).create();
  if (context.mounted) context.push(Routes.canvasEditor(id));
}

/// Pestaña Lienzo: galería de lienzos guardados.
class CanvasesScreen extends ConsumerWidget {
  const CanvasesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Theme.of(context); // Rebuild when the active palette changes.
    final canvases = ref.watch(canvasesProvider).valueOrNull;

    return Column(
      children: [
        KraftTopBar(
          leading: const KraftBrand(breadcrumb: 'Lienzos'),
          actions: [
            const AiConnectButton(),
            NeoBox(
              onTap: () => createCanvasAndOpen(context, ref),
              color: KraftColors.primaryContainer,
              borderWidth: 1.5,
              shadow: 2,
              radius: KraftRadius.lg,
              padding: const EdgeInsets.symmetric(horizontal: KraftSpace.md, vertical: 10),
              child: Row(
                children: [
                  const Icon(Symbols.add, size: 20),
                  const SizedBox(width: 4),
                  Text('NUEVO LIENZO', style: KraftText.labelCode.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const KraftAvatar(),
          ],
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const gap = KraftSpace.md;
              final contentWidth = constraints.maxWidth - KraftSpace.xl * 2;
              final columns = (contentWidth / 300).floor().clamp(1, 4);
              final cardWidth = (contentWidth - gap * (columns - 1)) / columns;

              return ListView(
                padding: const EdgeInsets.all(KraftSpace.xl),
                children: [
                  Text('Lienzos', style: KraftText.headlineLg.copyWith(fontSize: 28)),
                  Text(
                    'Toca uno para entrar en modo lienzo. Se guarda al salir.',
                    style: KraftText.bodyMd.copyWith(color: KraftColors.onSurfaceVariant),
                  ),
                  const SizedBox(height: KraftSpace.lg),
                  if (canvases != null)
                    Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        Entrance(child: _NewCanvasCard(width: cardWidth, onTap: () => createCanvasAndOpen(context, ref))),
                        for (final (i, record) in canvases.indexed)
                          Entrance(
                            key: ValueKey(record.id),
                            index: i + 1,
                            child: _CanvasCard(record: record, width: cardWidth),
                          ),
                      ],
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NewCanvasCard extends StatelessWidget {
  const _NewCanvasCard({required this.width, required this.onTap});

  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return SizedBox(
      width: width,
      height: _CanvasCard.height,
      child: NeoBox(
        onTap: onTap,
        color: KraftColors.primaryContainer,
        borderWidth: KraftBorder.width,
        shadow: 3,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Symbols.draw, size: 40),
              const SizedBox(height: KraftSpace.sm),
              Text('NUEVO LIENZO', style: KraftText.labelCode.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CanvasCard extends ConsumerWidget {
  const _CanvasCard({required this.record, required this.width});

  final CanvasRecord record;
  final double width;

  static const height = 260.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Theme.of(context); // Rebuild when the active palette changes.
    return SizedBox(
      width: width,
      height: height,
      child: NeoBox(
        onTap: () => context.push(Routes.canvasEditor(record.id)),
        shadow: 3,
        clip: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: KraftColors.surfaceContainerLow,
                  border: Border(bottom: BorderSide(color: KraftColors.ink, width: 2)),
                ),
                child: _Thumbnail(key: ValueKey(record.updatedAt), data: record.data),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(KraftSpace.md, 8, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: KraftText.headlineSm.copyWith(fontSize: 17, fontWeight: FontWeight.w700),
                        ),
                        Text(relativeTime(record.updatedAt), style: KraftText.labelCode.copyWith(color: KraftColors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Opciones del lienzo',
                    icon: const Icon(Symbols.more_vert, size: 20),
                    color: KraftColors.surfaceContainerLowest,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(KraftRadius.lg),
                      side: BorderSide(color: KraftColors.ink, width: 2),
                    ),
                    onSelected: (value) async {
                      final repo = ref.read(canvasesRepositoryProvider);
                      if (value == 'project') {
                        await showProjectPicker(
                          context,
                          ref,
                          current: record.projectId,
                          onPick: (id) => repo.setProject(record.id, id),
                        );
                        return;
                      }
                      if (value == 'delete') {
                        final overlay = Overlay.of(context, rootOverlay: true);
                        await repo.delete(record.id);
                        KraftToast.showOn(
                          overlay,
                          'Lienzo borrado',
                          icon: Symbols.delete,
                          actionLabel: 'Deshacer',
                          onAction: () => repo.restore(record),
                        );
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'project',
                        child: Text('Mover a proyecto'),
                      ),
                      PopupMenuItem(value: 'delete', child: Text('Borrar')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Miniatura del contenido: elementos como bloques de color y trazos simplificados.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({super.key, required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    final decoded = CanvasCodec.decode(data);
    if (decoded.isEmpty) {
      return Center(
        child: Text('VACÍO', style: KraftText.techBadge.copyWith(color: KraftColors.outline)),
      );
    }
    return CustomPaint(painter: _ThumbnailPainter(decoded));
  }
}

class _ThumbnailPainter extends CustomPainter {
  const _ThumbnailPainter(this.data);

  final CanvasData data;

  @override
  void paint(Canvas canvas, Size size) {
    Rect? bounds;
    final rects = <(Rect, CanvasItem)>[];
    for (final item in data.items) {
      final r = item.position & canvasItemSize(item);
      rects.add((r, item));
      bounds = bounds?.expandToInclude(r) ?? r;
    }
    for (final s in data.strokes) {
      bounds = bounds?.expandToInclude(s.bounds) ?? s.bounds;
    }
    if (bounds == null) return;
    bounds = bounds.inflate(40);
    final scale = math.min(size.width / bounds.width, size.height / bounds.height);
    final origin = Offset(
      (size.width - bounds.width * scale) / 2 - bounds.left * scale,
      (size.height - bounds.height * scale) / 2 - bounds.top * scale,
    );
    Offset map(Offset p) => p * scale + origin;

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..color = KraftColors.ink
      ..strokeWidth = 1.5;
    for (final (r, item) in rects) {
      final mapped = Rect.fromPoints(map(r.topLeft), map(r.bottomRight));
      canvas
        ..drawRect(mapped.shift(const Offset(2, 2)), Paint()..color = KraftColors.ink)
        ..drawRect(mapped, Paint()..color = canvasItemColor(item))
        ..drawRect(mapped, border);
    }
    for (final s in data.strokes) {
      if (s.points.isEmpty) continue;
      final path = Path()..moveTo(map(s.points.first).dx, map(s.points.first).dy);
      final step = math.max(1, s.points.length ~/ 40);
      for (var i = step; i < s.points.length; i += step) {
        final p = map(s.points[i]);
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = s.color
          ..strokeWidth = math.max(1, s.paintedWidth * scale)
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_ThumbnailPainter old) => false;
}
