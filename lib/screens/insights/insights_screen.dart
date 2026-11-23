import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/analytics/insight_period.dart';
import '../../services/analytics/insights_service.dart';
import '../../services/history/history_service.dart';
import '../../util/clock.dart';
import '../../util/duration_format.dart';
import '../../widgets/charts/comparison_bars.dart';
import '../../widgets/charts/donut_chart.dart';
import '../../widgets/common/activity_dot.dart';
import '../../widgets/insights/period_selector.dart';
import 'day_strips_page.dart';

/// Activity distribution and period comparison for one selected period.
/// The period selector at the top drives both charts; swiping left or right
/// anywhere on the screen moves to the next or previous period, like ‹ ›.
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({
    super.key,
    required this.insights,
    required this.history,
    required this.period,
    required this.changes,
    required this.clock,
  });

  final InsightsService insights;

  /// For the daily timeline opened from its card.
  final HistoryService history;

  /// The selected period, shared with the Daily timeline: a change in either
  /// shows in both.
  final ValueNotifier<InsightPeriod> period;

  /// Anything that can change the numbers (tracking, edits, activities).
  final Listenable changes;
  final Clock clock;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  InsightsData? _data;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    widget.changes.addListener(_load);
    widget.period.addListener(_onPeriod);
    // A period in progress grows while an activity runs.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_period.isInProgress(widget.clock.now())) _load();
    });
    _load();
  }

  @override
  void didUpdateWidget(InsightsScreen old) {
    super.didUpdateWidget(old);
    if (old.changes != widget.changes) {
      old.changes.removeListener(_load);
      widget.changes.addListener(_load);
    }
    if (old.period != widget.period) {
      old.period.removeListener(_onPeriod);
      widget.period.addListener(_onPeriod);
      _load();
    }
  }

  @override
  void dispose() {
    widget.changes.removeListener(_load);
    widget.period.removeListener(_onPeriod);
    _ticker?.cancel();
    super.dispose();
  }

  InsightPeriod get _period => widget.period.value;

  /// Shows the new selection right away (old results dimmed), then loads.
  void _onPeriod() {
    setState(() {});
    _load();
  }

  Future<void> _load() async {
    final period = _period;
    final data = await widget.insights.load(period);
    if (mounted && identical(period, _period)) {
      setState(() => _data = data);
    }
  }

  void _select(InsightPeriod p) => widget.period.value = p;

  @override
  Widget build(BuildContext context) {
    final now = widget.clock.now();
    final period = _period;
    // While a newly selected period loads, the previous results stay (dimmed)
    // so the list keeps its height and scroll position.
    final data = _data;
    final loading = data?.period != period;
    final selector = PeriodSelector(
      period: period,
      now: now,
      onChanged: _select,
      labelKey: const Key('insights-period'),
    );

    final shown = data?.period;
    return PeriodSwipe(
      key: const Key('insights-swipe'),
      period: period,
      now: widget.clock.now,
      onChanged: _select,
      child: Column(
        children: [
          selector,
          // Thin progress line while a period loads (keeps the layout still).
          SizedBox(
            height: 2,
            child: loading && data != null
                ? const LinearProgressIndicator()
                : null,
          ),
          Expanded(
            child: ListView(
              key: const Key('insights-list'),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                if (data == null || shown == null)
                  const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  AnimatedOpacity(
                    opacity: loading ? 0.5 : 1,
                    duration: const Duration(milliseconds: 150),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Section(
                          title: 'Distribution',
                          child: _Distribution(data: data, now: now),
                        ),
                        if (data.comparison != null) ...[
                          const SizedBox(height: 16),
                          _Section(
                            title:
                                '${shown.relativeName(now)} vs '
                                '${shown.previous.relativeName(now)}',
                            child: _Comparison(data: data, now: now),
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                // Not tied to the selected period: it shows every day.
                Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    key: const Key('open-day-strips'),
                    leading: const Icon(Icons.view_timeline_outlined),
                    title: const Text('Daily timeline'),
                    subtitle: const Text('Every day from midnight to midnight'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DayStripsPage(
                          history: widget.history,
                          period: widget.period,
                          changes: widget.changes,
                          clock: widget.clock,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _Distribution extends StatelessWidget {
  const _Distribution({required this.data, required this.now});

  final InsightsData data;
  final DateTime now;

  static String _percent(double f) {
    final p = f * 100;
    if (p > 0 && p < 1) return '<1%';
    return '${p.round()}%';
  }

  @override
  Widget build(BuildContext context) {
    final shares = data.distribution;
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        DonutChart(
          values: [for (final s in shares) s.duration.inSeconds.toDouble()],
          colors: [for (final s in shares) Color(s.activity.color)],
        ),
        const SizedBox(height: 16),
        for (final s in shares)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                ActivityDot(color: Color(s.activity.color)),
                const SizedBox(width: 10),
                Expanded(child: Text(s.activity.name)),
                Text(formatTotal(s.duration)),
                SizedBox(
                  width: 52,
                  child: Text(
                    _percent(s.fraction),
                    key: ValueKey('share-${s.activity.id}'),
                    textAlign: TextAlign.right,
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Comparison extends StatelessWidget {
  const _Comparison({required this.data, required this.now});

  final InsightsData data;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = data.comparison!;
    final period = data.period;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('Nothing tracked in either period.')),
          )
        else
          ComparisonBars(
            rows: c.rows,
            currentLabel: period.relativeName(now),
            previousLabel: period.previous.relativeName(now),
          ),
      ],
    );
  }
}
