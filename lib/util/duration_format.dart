/// Live session format: `0:05:09`, `1:42:15`, `27:00:00`.
String formatClock(Duration d) {
  final s = d.isNegative ? 0 : d.inSeconds;
  final h = s ~/ 3600;
  final m = (s ~/ 60) % 60;
  final sec = s % 60;
  return '$h:${_two(m)}:${_two(sec)}';
}

/// Total format: `0m`, `42m`, `2h 42m`, `5h`, `1w 3d 4h 10m`, `1y 2mo 5d`.
///
/// Units are years, months, weeks, days, hours and minutes, with fixed
/// lengths (1y = 365d, 1mo = 30d, 1w = 7d) since a total is not tied to a
/// calendar. Months use `mo` so they are not confused with minutes. Units that
/// are zero are left out; seconds are dropped.
String formatTotal(Duration d) {
  var minutes = d.isNegative ? 0 : d.inMinutes;
  if (minutes == 0) return '0m';
  final parts = <String>[];
  for (final (unit, size) in _totalUnits) {
    final n = minutes ~/ size;
    if (n > 0) parts.add('$n$unit');
    minutes %= size;
  }
  return parts.join(' ');
}

const _minutesPerDay = 24 * 60;
const _totalUnits = [
  ('y', 365 * _minutesPerDay),
  ('mo', 30 * _minutesPerDay),
  ('w', 7 * _minutesPerDay),
  ('d', _minutesPerDay),
  ('h', 60),
  ('m', 1),
];

String _two(int n) => n.toString().padLeft(2, '0');

/// Like [formatTotal], but shows seconds for entries under a minute (`45s`),
/// so very short entries do not read as `0m`.
String formatEntryDuration(Duration d) {
  if (d.isNegative) return '0s';
  return d.inMinutes == 0 ? '${d.inSeconds}s' : formatTotal(d);
}

/// Precise format for comparing durations in dialogs, where two values can
/// fall in the same minute: `40s`, `1m 37s`, `2h 5m`.
String formatDurationPrecise(Duration d) {
  if (d.isNegative) return '0s';
  final s = d.inSeconds;
  if (s < 60) return '${s}s';
  if (s < 3600) return '${s ~/ 60}m ${s % 60}s';
  return formatTotal(d);
}
