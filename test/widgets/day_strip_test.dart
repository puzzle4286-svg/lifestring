import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/services/tracking/time_range.dart';
import 'package:time_tracker/widgets/charts/day_strip.dart';

import '../support/day_entries.dart';

void main() {
  final day = DateTime(2026, 11, 9);
  DateTime at(int h, [int m = 0]) => DateTime(2026, 11, 9, h, m);

  test('entries map to fractions of the day, left = midnight', () {
    final s = dayStripSegments(day, [
      dayEntry(1, 'A', at(0), at(6)),
      dayEntry(2, 'B', at(12), at(18)),
    ], at(23));
    expect(s.map((e) => (e.from, e.to)), [(0.0, 0.25), (0.5, 0.75)]);
  });

  test('a running entry ends at now', () {
    final s = dayStripSegments(day, [dayEntry(1, 'A', at(9), null)], at(12));
    expect(s.single.from, closeTo(9 / 24, 1e-9));
    expect(s.single.to, 0.5);
  });

  test('entries shorter than the minimum width are left out', () {
    final s = dayStripSegments(
      day,
      [
        dayEntry(1, 'short', at(9), at(9, 3)),
        dayEntry(2, 'long', at(10), at(11)),
      ],
      at(23),
      minFraction: 5 / (24 * 60), // 5 minutes
    );
    expect(s.length, 1);
    expect(s.single.from, closeTo(10 / 24, 1e-9));
  });

  group('days the clocks change (uses this process\'s local timezone)', () {
    final dstDays = [
      for (
        var d = DateTime(2026);
        d.year == 2026;
        d = DateTime(d.year, d.month, d.day + 1)
      )
        if (localDay(d).duration != const Duration(hours: 24)) d,
    ];
    final skip = dstDays.isEmpty
        ? 'Local timezone has no DST in 2026; run with e.g. TZ=Europe/Berlin'
        : null;

    test('wall-clock hours sit where the 24-hour axis shows them', () {
      for (final d in dstDays) {
        DateTime t(int h) => DateTime(d.year, d.month, d.day, h);
        final s = dayStripSegments(d, [
          dayEntry(1, 'A', t(6), t(12)),
          dayEntry(2, 'B', t(18), DateTime(d.year, d.month, d.day + 1)),
        ], t(23));
        expect(s.map((e) => (e.from, e.to)), [
          (0.25, 0.5),
          (0.75, 1.0),
        ], reason: '$d');
      }
    }, skip: skip);
  });
}
