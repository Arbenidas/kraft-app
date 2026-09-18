import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../theme/kraft_colors.dart';
import '../../theme/kraft_tokens.dart';
import '../../theme/kraft_typography.dart';
import '../../utils/dates.dart';

/// Un vencimiento conserva si la hora fue elegida, incluso cuando es 00:00.
class KraftDeadline {
  const KraftDeadline({required this.day, this.time});
  final DateTime day;
  final TimeOfDay? time;
  DateTime? get dateTime => time == null
      ? null
      : DateTime(day.year, day.month, day.day, time!.hour, time!.minute);
  String get dayKey => '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
  String label(BuildContext context) => time == null
      ? '${day.day} ${monthName(day)} · Todo el día'
      : '${day.day} ${monthName(day)} · ${time!.format(context)}';
}

Future<KraftDeadline?> showKraftDeadlinePicker(
  BuildContext context, {
  KraftDeadline? initial,
  bool timeRequired = false,
  String title = 'Fecha límite',
}) => showDialog<KraftDeadline>(
  context: context,
  builder: (_) => _KraftDeadlineDialog(
    initial: initial,
    timeRequired: timeRequired,
    title: title,
  ),
);

class KraftDeadlineButton extends StatelessWidget {
  const KraftDeadlineButton({
    super.key,
    required this.value,
    required this.onPick,
    this.onClear,
    this.label = 'Fecha límite',
  });
  final KraftDeadline? value;
  final VoidCallback onPick;
  final VoidCallback? onClear;
  final String label;

  @override
  Widget build(BuildContext context) {
    final date = value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: KraftText.labelCode),
        const SizedBox(height: KraftSpace.xs),
        OutlinedButton.icon(
          onPressed: onPick,
          icon: const Icon(Symbols.calendar_month, size: 18),
          label: Text(date == null ? 'Asignar fecha' : date.label(context)),
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            side: BorderSide(color: KraftColors.outlineVariant),
            foregroundColor: KraftColors.onSurface,
          ),
        ),
        if (onClear != null)
          TextButton.icon(
            onPressed: onClear,
            icon: const Icon(Symbols.close, size: 15),
            label: const Text('Quitar fecha'),
          ),
      ],
    );
  }
}

class _KraftDeadlineDialog extends StatefulWidget {
  const _KraftDeadlineDialog({required this.initial, required this.timeRequired, required this.title});
  final KraftDeadline? initial;
  final bool timeRequired;
  final String title;
  @override
  State<_KraftDeadlineDialog> createState() => _KraftDeadlineDialogState();
}

class _KraftDeadlineDialogState extends State<_KraftDeadlineDialog> {
  late DateTime _month = DateTime((widget.initial?.day ?? DateTime.now()).year, (widget.initial?.day ?? DateTime.now()).month);
  late DateTime _selected = dateOnly(widget.initial?.day ?? DateTime.now());
  late TimeOfDay? _time = widget.initial?.time ?? (widget.timeRequired ? TimeOfDay.now() : null);

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: KraftColors.surfaceContainerLow,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KraftRadius.lg), side: BorderSide(color: KraftColors.border, width: 1.5)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 410),
      child: Padding(
        padding: const EdgeInsets.all(KraftSpace.lg),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: Text(widget.title, style: KraftText.headlineSm)),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Symbols.close)),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            IconButton(onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)), icon: const Icon(Symbols.chevron_left)),
            Text('${monthName(_month)} ${_month.year}', style: KraftText.bodyMd.copyWith(fontWeight: FontWeight.w700)),
            IconButton(onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)), icon: const Icon(Symbols.chevron_right)),
          ]),
          const SizedBox(height: KraftSpace.xs),
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 7,
            childAspectRatio: 1.1,
            children: [
              for (final day in const ['L', 'M', 'X', 'J', 'V', 'S', 'D']) Center(child: Text(day, style: KraftText.labelCode)),
              for (var i = 0; i < DateTime(_month.year, _month.month, 1).weekday - 1; i++) const SizedBox(),
              for (var day = 1; day <= DateTime(_month.year, _month.month + 1, 0).day; day++)
                _DayButton(
                  day: DateTime(_month.year, _month.month, day),
                  selected: isSameDay(_selected, DateTime(_month.year, _month.month, day)),
                  onTap: () => setState(() => _selected = DateTime(_month.year, _month.month, day)),
                ),
            ],
          ),
          const SizedBox(height: KraftSpace.sm),
          SwitchListTile.adaptive(
            value: _time != null,
            onChanged: widget.timeRequired ? null : (enabled) => setState(() => _time = enabled ? (_time ?? TimeOfDay.now()) : null),
            title: Text('Hora', style: KraftText.bodyMd),
            subtitle: Text(_time == null ? 'Todo el día' : _time!.format(context), style: KraftText.bodySm),
            secondary: const Icon(Symbols.schedule),
          ),
          if (_time != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final time = await showTimePicker(context: context, initialTime: _time!);
                  if (time != null && mounted) setState(() => _time = time);
                },
                icon: const Icon(Symbols.schedule),
                label: Text('Cambiar hora · ${_time!.format(context)}'),
              ),
            ),
          const SizedBox(height: KraftSpace.sm),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            const SizedBox(width: KraftSpace.sm),
            FilledButton(onPressed: () => Navigator.pop(context, KraftDeadline(day: _selected, time: _time)), child: const Text('Guardar')),
          ]),
        ]),
      ),
    ),
  );
}

class _DayButton extends StatelessWidget {
  const _DayButton({required this.day, required this.selected, required this.onTap});
  final DateTime day;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(KraftRadius.sm),
    child: Container(
      alignment: Alignment.center,
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: selected ? KraftColors.primary : null, borderRadius: BorderRadius.circular(KraftRadius.sm)),
      child: Text('${day.day}', style: KraftText.bodySm.copyWith(color: selected ? KraftColors.onPrimary : KraftColors.onSurface, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
    ),
  );
}
