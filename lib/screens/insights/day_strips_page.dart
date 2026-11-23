import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/analytics/insight_period.dart';
import '../../services/history/history_service.dart';
import '../../util/clock.dart';
import '../../widgets/charts/day_strip.dart';
import '../../widgets/insights/period_selector.dart';

/// Every day of the selected period as a 24-hour line, most recent at the
/// top, coloured by what was tracked when. Lines shrink so the whole period
/// fits on screen (a year gives very thin lines); swiping left or right moves
/// to the next or previous period.
class DayStripsPage extends StatefulWidget {
  const DayStripsPage({
    super.key,
    required this.history,
    required this.period,
    required this.changes,
    required this.clock,
  });

  final HistoryService history;

  /// The selected period, shared with Insights: a change in either shows in
  /// both.
  final ValueNotifier<InsightPeriod> period;

  /// Anything that can change the entries (tracking, edits, activities).
  final Listenable changes;
  final Clock clock;

  @override
  State<DayStripsPage> createState() => _DayStripsPageState();
}

class _DayStripsPageState extends State<DayStripsPage> {
  /// Largest line height and gap.
  static const double _maxRowHeight = 16;
  static const double _maxGap = 4;

  /// Rows that Day, Week and Month are sized for: the longest month. All three
  /// get the same lines; shorter periods just end higher up.
  static const int _shortPeriodSlots = 31;

  /// Thinnest line before the chart scrolls instead (long "All" histories).
  static const double _minRowHeight = 1;

  InsightPeriod get _period => widget.period.value;

  /// Days of [_shown], newest first; null before the first load.
  List<DayStripRow>? _rows;
  InsightPeriod? _shown;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    widget.changes.addListener(_load);
    widget.period.addListener(_onPeriod);
    // Today's line grows while an activity runs.
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    widget.changes.removeListener(_load);
    widget.period.removeListener(_onPeriod);
    _ticker?.cancel();
    super.dispose();
  }

  void _select(InsightPeriod p) => widget.period.value = p;

  /// Shows the new selection right away (old lines dimmed), then loads.
  void _onPeriod() {
    setState(() {});
    _load();
  }

  Future<void> _load() async {
    final period = _period;
    final now = widget.clock.now();
    final first = await widget.history.firstDay();
    final range = period.range(now: now, firstEntry: first ?? now);
    final days = await widget.history.entriesForDays(
      range.start,
      // The range end is exclusive: the last day starts just before it.
      range.end.subtract(const Duration(microseconds: 1)),
    );
    if (!mounted || !identical(period, _period)) return;
    final rows = [
      for (final MapEntry(key: day, value: entries) in days.entries)
        DayStripRow(day, entries),
    ]..sort((a, b) => b.day.compareTo(a.day));
    setState(() {
      _rows = rows;
      _shown = period;
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.clock.now();
    final rows = _rows;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Daily timeline')),
      // Keeps the fitted chart clear of the system navigation bar.
      body: SafeArea(
        top: false,
        child: PeriodSwipe(
          key: const Key('day-strips-swipe'),
          period: _period,
          now: widget.clock.now,
          onChanged: _select,
          child: Column(
            children: [
              PeriodSelector(
                period: _period,
                now: now,
                onChanged: _select,
                labelKey: const Key('day-strips-period'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: _HourAxis(style: text.labelSmall),
              ),
              Expanded(
                child: rows == null
                    ? const Center(child: CircularProgressIndicator())
                    : AnimatedOpacity(
                        opacity: _shown == _period ? 1 : 0.5,
                        duration: const Duration(milliseconds: 150),
                        child: LayoutBuilder(
                          builder: (context, box) =>
                              _chart(rows, _shown!, now, box.maxHeight),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Fits all [rows] into [height] where possible: full-size lines for short
  /// periods, thinner ones (and no gaps once they get thin) for long ones.
  /// Day, Week and Month are all sized as 31 days, so their lines are the
  /// same size; shorter periods just end higher up.
  Widget _chart(
    List<DayStripRow> rows,
    InsightPeriod period,
    DateTime now,
    double height,
  ) {
    const padding = EdgeInsets.fromLTRB(16, 4, 16, 16);
    final available = math.max(0.0, height - padding.vertical);
    final slots = switch (period.unit) {
      InsightUnit.day ||
      InsightUnit.week ||
      InsightUnit.month => _shortPeriodSlots,
      InsightUnit.year || InsightUnit.all => rows.length,
    };
    final perRow = slots == 0
        ? _maxRowHeight + _maxGap
        : math.min(_maxRowHeight + _maxGap, available / slots);
    // Gaps keep the same proportion as at full size until lines get thin.
    final gap = perRow >= 6
        ? perRow * _maxGap / (_maxRowHeight + _maxGap)
        : 0.0;
    final rowHeight = math.max(_minRowHeight, perRow - gap);
    return SingleChildScrollView(
      key: const Key('day-strips-list'),
      padding: padding,
      child: DayStripsChart(
        key: const Key('day-strips-chart'),
        rows: rows,
        now: now,
        rowHeight: rowHeight,
        gap: gap,
      ),
    );
  }
}

/// Hour labels above the lines: 0, 6, 12, 18, 24.
class _HourAxis extends StatelessWidget {
  const _HourAxis({required this.style});

  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 16,
      child: LayoutBuilder(
        builder: (context, box) => Stack(
          clipBehavior: Clip.none,
          children: [
            for (final h in const [0, 6, 12, 18, 24])
              Positioned(
                left: switch (h) {
                  0 => 0,
                  24 => box.maxWidth - 24,
                  _ => box.maxWidth * h / 24 - 12,
                },
                width: 24,
                child: Text(
                  '$h',
                  textAlign: h == 0
                      ? TextAlign.left
                      : h == 24
                      ? TextAlign.right
                      : TextAlign.center,
                  style: style,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
