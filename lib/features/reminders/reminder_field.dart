import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/providers.dart';
import '../../theme/kraft_colors.dart';
import '../../theme/kraft_tokens.dart';
import '../../theme/kraft_typography.dart';
import '../../utils/dates.dart';
import '../../widgets/kraft_toast.dart';
import '../../widgets/neo_box.dart';
import '../planning/kraft_deadline_picker.dart';

/// "Mañana · 09:00", "Hoy · 18:00", "Jueves, 18 Septiembre · 10:30".
String reminderLabel(DateTime at, {DateTime? now}) {
  final today = dateOnly(now ?? DateTime.now());
  final day = dateOnly(at);
  final name = switch (day.difference(today).inDays) {
    0 => 'Hoy',
    1 => 'Mañana',
    _ => longDay(at),
  };
  return '$name · ${hhmm(at)}';
}

/// Elegir cuándo avisar: accesos rápidos o fecha y hora exactas, y copia en Recordatorios de Apple.
class ReminderField extends ConsumerWidget {
  const ReminderField({super.key, required this.value, required this.onChanged});

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  Future<void> _set(WidgetRef ref, DateTime? at) async {
    onChanged(at);
    if (at != null) await ref.read(reminderServiceProvider).ensureNotificationPermission();
  }

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final initial = value ?? now.add(const Duration(hours: 1));
    final picked = await showKraftDeadlinePicker(
      context,
      initial: KraftDeadline(day: initial.isBefore(now) ? now : initial, time: TimeOfDay.fromDateTime(initial)),
      timeRequired: true,
      title: 'Recordatorio',
    );
    if (picked?.dateTime == null || !context.mounted) return;
    await _set(ref, picked!.dateTime!);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Theme.of(context); // Rebuild when the active palette changes.
    final now = DateTime.now();
    final today = dateOnly(now);
    final presets = <(String, DateTime)>[
      ('En 1 hora', DateTime(now.year, now.month, now.day, now.hour + 1, now.minute)),
      if (now.hour < 18) ('Hoy 18:00', today.add(const Duration(hours: 18))),
      ('Mañana 9:00', addDays(today, 1).add(const Duration(hours: 9))),
    ];
    final service = ref.watch(reminderServiceProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('RECORDATORIO', style: KraftText.techBadge.copyWith(color: KraftColors.onSurfaceVariant)),
        const SizedBox(height: 6),
        Wrap(
          spacing: KraftSpace.sm,
          runSpacing: KraftSpace.sm,
          children: [
            _Chip(label: 'Sin aviso', icon: Symbols.notifications_off, selected: value == null, onTap: () => _set(ref, null)),
            for (final (label, at) in presets)
              _Chip(label: label, icon: Symbols.alarm, selected: value == at, onTap: () => _set(ref, at)),
            _Chip(
              label: value != null && !presets.any((p) => p.$2 == value) ? reminderLabel(value!) : 'Elegir fecha y hora',
              icon: Symbols.calendar_month,
              selected: value != null && !presets.any((p) => p.$2 == value),
              onTap: () => _pick(context, ref),
            ),
          ],
        ),
        if (value != null) ...[
          const SizedBox(height: KraftSpace.sm),
          Row(
            children: [
              Icon(Symbols.notifications_active, size: 18, color: KraftColors.secondary),
              const SizedBox(width: 6),
              Expanded(child: Text('Te avisaré ${reminderLabel(value!).toLowerCase()}', style: KraftText.bodySm)),
            ],
          ),
          Row(
            children: [
              Expanded(child: Text('También en Recordatorios de Apple', style: KraftText.bodyMd)),
              Switch(
                value: service.appleSync,
                activeTrackColor: KraftColors.inkFill,
                activeThumbColor: KraftColors.primaryContainer,
                onChanged: (enabled) async {
                  final ok = await service.setAppleSync(enabled);
                  if (!ok && context.mounted) {
                    KraftToast.show(context, 'Permite el acceso en Ajustes › Privacidad › Recordatorios', icon: Symbols.lock);
                  }
                },
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.icon, required this.selected, required this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active palette changes.
    return NeoBox(
      onTap: onTap,
      color: selected ? KraftColors.primaryContainer : KraftColors.surfaceContainerLowest,
      borderWidth: 1.5,
      shadow: selected ? 2 : 0,
      radius: KraftRadius.sm,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label, style: KraftText.labelCode.copyWith(fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
        ],
      ),
    );
  }
}
