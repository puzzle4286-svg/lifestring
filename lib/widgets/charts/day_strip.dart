import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/history/history_service.dart';
import '../../services/tracking/time_range.dart';

/// One coloured piece of a day line, as fractions of the day (0–1).
class DayStripSegment {
  const DayStripSegment(this.from, this.to, this.color);

  final double from;
  final double to;
  final Color color;
}

/// Position of [t] on the 24-hour line of the local day [range], by wall
/// clock: 06:00 is always 0.25, whatever the day's real length. On a day the
/// clocks change (23 or 25 hours) the line therefore matches the hour axis;
/// the skipped hour is simply passed over and the repeated one drawn twice.
/// Before the day is 0, from its end (the next midnight) on is 1.
double dayLineFraction(DateTime t, TimeRange range) {
  if (!t.isAfter(range.start)) return 0;
  if (!t.isBefore(range.end)) return 1;
  final l = t.toLocal();
  final micros =
      ((l.hour * 60 + l.minute) * 60 + l.second) * 1000000 +
      l.millisecond * 1000 +
      l.microsecond;
  return micros / Duration.microsecondsPerDay;
}

/// Segments of [entries] on the local [day], left = midnight, right = the next
/// midnight, placed with [dayLineFraction]. A running entry ends at [now].
/// Entries narrower than [minFraction] are left out (too short to see at this
/// scale).
List<DayStripSegment> dayStripSegments(
  DateTime day,
  List<DayEntry> entries,
  DateTime now, {
  double minFraction = 0,
}) {
  final range = localDay(day);
  final segments = <DayStripSegment>[];
  for (final e in entries) {
    var from = dayLineFraction(e.start, range);
    var to = dayLineFraction(e.end ?? now, range);
    // Only possible inside the repeated hour when clocks go back.
    if (to < from) (from, to) = (to, from);
    final w = to - from;
    if (w > 0 && w >= minFraction) {
      segments.add(DayStripSegment(from, to, Color(e.activity.color)));
    }
  }
  return segments;
}

/// One row of [DayStripsChart].
class DayStripRow {
  const DayStripRow(this.day, this.entries);

  /// Local midnight.
  final DateTime day;
  final List<DayEntry> entries;
}

/// Days as horizontal 24-hour lines, one under another in the order given,
/// each coloured by what was tracked when. Faint marks show 06:00, 12:00 and
/// 18:00. Row height and gap come from the caller, so a whole period can be
/// fitted on screen (a year gives very thin lines). Flat in every style, Neon
/// included: glows blur thin, tightly packed lines.
class DayStripsChart extends StatelessWidget {
  const DayStripsChart({
    super.key,
    required this.rows,
    required this.now,
    required this.rowHeight,
    required this.gap,
  });

  /// Pieces narrower than this (in logical pixels) are not drawn: about
  /// 4–5 minutes on a phone in portrait.
  static const double minSegmentWidth = 1;

  final List<DayStripRow> rows;
  final DateTime now;
  final double rowHeight;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final lines = [
          for (final r in rows)
            width <= 0
                ? const <DayStripSegment>[]
                : dayStripSegments(
                    r.day,
                    r.entries,
                    now,
                    minFraction: minSegmentWidth / width,
                  ),
        ];
        return CustomPaint(
          size: Size(width, rows.length * (rowHeight + gap)),
          painter: _DayStripsPainter(
            lines: lines,
            rowHeight: rowHeight,
            gap: gap,
            track: scheme.surfaceContainerHighest,
            mark: scheme.onSurface.withValues(alpha: 0.25),
          ),
        );
      },
    );
  }
}

class _DayStripsPainter extends CustomPainter {
  _DayStripsPainter({
    required this.lines,
    required this.rowHeight,
    required this.gap,
    required this.track,
    required this.mark,
  });

  /// Segments per row.
  final List<List<DayStripSegment>> lines;
  final double rowHeight;
  final double gap;
  final Color track;
  final Color mark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final step = rowHeight + gap;
    final radius = Radius.circular(math.min(3, rowHeight / 2));
    final paint = Paint();

    // Tracks first, then the pieces on top.
    paint.color = track;
    for (var i = 0; i < lines.length; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, i * step, w, rowHeight),
          radius,
        ),
        paint,
      );
    }
    for (var i = 0; i < lines.length; i++) {
      final row = Rect.fromLTWH(0, i * step, w, rowHeight);
      canvas.save();
      canvas.clipRRect(RRect.fromRectAndRadius(row, radius));
      for (final s in lines[i]) {
        paint.color = s.color;
        canvas.drawRect(_piece(s, i, w, step), paint);
      }
      canvas.restore();
    }
    paint
      ..color = mark
      ..strokeWidth = 1;
    // The same hours on every line (wall clock, see [dayLineFraction]).
    for (final h in const [6, 12, 18]) {
      final x = w * h / 24;
      if (rowHeight < 4) {
        // Lines too thin for per-row marks: one guide down the whole chart.
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      } else {
        for (var i = 0; i < lines.length; i++) {
          canvas.drawLine(
            Offset(x, i * step),
            Offset(x, i * step + rowHeight),
            paint,
          );
        }
      }
    }
  }

  Rect _piece(DayStripSegment s, int i, double w, double step) =>
      Rect.fromLTRB(s.from * w, i * step, s.to * w, i * step + rowHeight);

  @override
  bool shouldRepaint(_DayStripsPainter old) => true;
}
