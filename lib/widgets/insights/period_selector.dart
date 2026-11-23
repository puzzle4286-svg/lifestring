import 'package:flutter/material.dart';

import '../../services/analytics/insight_period.dart';

/// The period before [period], or null for "all time".
InsightPeriod? previousPeriod(InsightPeriod period) =>
    period.unit == InsightUnit.all ? null : period.previous;

/// The period after [period], or null when that would be in the future
/// (nothing has been tracked there yet) or for "all time".
InsightPeriod? nextPeriod(InsightPeriod period, DateTime now) {
  if (period.unit == InsightUnit.all ||
      period.isInProgress(now) ||
      period.next.isFuture(now)) {
    return null;
  }
  return period.next;
}

/// Day / Week / Month / Year / All, with ‹ label › below. Tapping the label
/// returns to the current period.
class PeriodSelector extends StatelessWidget {
  const PeriodSelector({
    super.key,
    required this.period,
    required this.now,
    required this.onChanged,
    this.labelKey,
  });

  final InsightPeriod period;
  final DateTime now;
  final ValueChanged<InsightPeriod> onChanged;

  /// Key for the period label, for tests.
  final Key? labelKey;

  @override
  Widget build(BuildContext context) {
    final isCurrent = period.isInProgress(now);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        children: [
          SegmentedButton<InsightUnit>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: InsightUnit.day, label: Text('Day')),
              ButtonSegment(value: InsightUnit.week, label: Text('Week')),
              ButtonSegment(value: InsightUnit.month, label: Text('Month')),
              ButtonSegment(value: InsightUnit.year, label: Text('Year')),
              ButtonSegment(value: InsightUnit.all, label: Text('All')),
            ],
            selected: {period.unit},
            onSelectionChanged: (s) => onChanged(InsightPeriod(s.single, now)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                tooltip: 'Previous',
                icon: const Icon(Icons.chevron_left),
                onPressed: switch (previousPeriod(period)) {
                  final p? => () => onChanged(p),
                  null => null,
                },
              ),
              Expanded(
                child: TextButton(
                  onPressed: isCurrent
                      ? null
                      : () => onChanged(InsightPeriod(period.unit, now)),
                  child: Text(
                    period.label(now),
                    key: labelKey,
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next',
                icon: const Icon(Icons.chevron_right),
                onPressed: switch (nextPeriod(period, now)) {
                  final p? => () => onChanged(p),
                  null => null,
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Swiping left or right anywhere on [child] moves to the next or previous
/// period, like turning pages. Vertical drags still reach scrollables inside.
class PeriodSwipe extends StatefulWidget {
  const PeriodSwipe({
    super.key,
    required this.period,
    required this.now,
    required this.onChanged,
    required this.child,
  });

  final InsightPeriod period;
  final DateTime Function() now;
  final ValueChanged<InsightPeriod> onChanged;
  final Widget child;

  @override
  State<PeriodSwipe> createState() => _PeriodSwipeState();
}

class _PeriodSwipeState extends State<PeriodSwipe> {
  /// Horizontal distance of the drag in progress.
  double _drag = 0;

  /// A swipe this long, or this fast, changes the period.
  static const double _swipeDistance = 64;
  static const double _swipeVelocity = 600;

  void _onDragEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    final distance = _drag;
    _drag = 0;
    final swipedLeft =
        distance <= -_swipeDistance || velocity <= -_swipeVelocity;
    final swipedRight =
        distance >= _swipeDistance || velocity >= _swipeVelocity;
    final target = swipedLeft
        ? nextPeriod(widget.period, widget.now())
        : swipedRight
        ? previousPeriod(widget.period)
        : null;
    if (target != null) widget.onChanged(target);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onHorizontalDragStart: (_) => _drag = 0,
    onHorizontalDragUpdate: (d) => _drag += d.primaryDelta ?? 0,
    onHorizontalDragEnd: _onDragEnd,
    child: widget.child,
  );
}
