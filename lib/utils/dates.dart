/// Utilidades de fecha en español sin depender de `intl`.
library;

const _weekdaysShort = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
const _weekdays = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];
const _months = [
  'Enero',
  'Febrero',
  'Marzo',
  'Abril',
  'Mayo',
  'Junio',
  'Julio',
  'Agosto',
  'Septiembre',
  'Octubre',
  'Noviembre',
  'Diciembre',
];

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Lunes de la semana de [d].
DateTime startOfWeek(DateTime d) =>
    dateOnly(d).subtract(Duration(days: d.weekday - 1));

DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month);

/// Suma días respetando cambios de horario (siempre medianoche local).
DateTime addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

String weekdayShort(DateTime d) => _weekdaysShort[d.weekday - 1];

String monthName(DateTime d) => _months[d.month - 1];

/// "Jueves, 15 Mayo".
String longDay(DateTime d) =>
    '${_weekdays[d.weekday - 1]}, ${d.day} ${monthName(d)}';

String hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// "Hace 15 min", "Hace 1 hora", "Ayer", "Hace 3 días", "12 Mayo".
String relativeTime(DateTime when, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final diff = ref.difference(when);
  if (diff.inMinutes < 1) return 'Ahora';
  if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
  if (diff.inHours < 24 && isSameDay(when, ref)) {
    return diff.inHours == 1 ? 'Hace 1 hora' : 'Hace ${diff.inHours} horas';
  }
  final days = dateOnly(ref).difference(dateOnly(when)).inDays;
  if (days == 1) return 'Ayer';
  if (days < 7) return 'Hace $days días';
  return '${when.day} ${monthName(when)}';
}
