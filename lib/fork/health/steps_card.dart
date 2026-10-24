import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/health/steps.dart';

typedef _Read = ({bool on, int goal, Map<DateTime, int>? days, bool failed});

/// Seam S40: daily steps from Health Connect on Trends, over the picked
/// range: today's, the average, the days at the goal, and a bar a day
/// against the goal line. Off until connected here.
class StepsCard extends StatefulWidget {
  final int rangeDays;
  final AppPalette palette;
  final StepCounts? steps;

  /// The day the range ends on; now in the app.
  final DateTime Function() clock;

  const StepsCard({
    super.key,
    required this.rangeDays,
    required this.palette,
    this.steps,
    this.clock = DateTime.now,
  });

  @override
  State<StepsCard> createState() => _StepsCardState();
}

class _StepsCardState extends State<StepsCard> {
  late final _steps = widget.steps ?? StepCounts();
  late Future<_Read?> _read = _load();

  @override
  void initState() {
    super.initState();
    StepCounts.changes.addListener(_reload);
  }

  @override
  void didUpdateWidget(StepsCard old) {
    super.didUpdateWidget(old);
    if (old.rangeDays != widget.rangeDays) _reload();
  }

  @override
  void dispose() {
    StepCounts.changes.removeListener(_reload);
    super.dispose();
  }

  /// Null hides the card (no store, as in tests without one); a refused
  /// read shows as such rather than as days without steps.
  Future<_Read?> _load() async {
    final bool on;
    final int goal;
    try {
      on = await _steps.isOn();
      goal = await _steps.goal();
    } catch (_) {
      return null;
    }
    if (!on) return (on: false, goal: goal, days: null, failed: false);
    try {
      final days = await _steps.daily(widget.clock(), widget.rangeDays);
      return (on: true, goal: goal, days: days, failed: false);
    } catch (_) {
      return (on: true, goal: goal, days: null, failed: true);
    }
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _read = _load();
    });
  }

  Future<void> _turnOn() async {
    final granted = await _steps.turnOn().catchError((Object _) => false);
    if (!granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Steps need the Health Connect permission.'),
        ),
      );
    }
  }

  Future<void> _editGoal(int goal) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (_) => _GoalDialog(goal: goal),
    );
    if (picked != null) await _steps.setGoal(picked);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_Read?>(
    future: _read,
    builder: (context, snapshot) {
      final read = snapshot.data;
      if (read == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: Dimens.spacing16),
        child: _card(context, read),
      );
    },
  );

  Widget _card(BuildContext context, _Read read) {
    final theme = Theme.of(context);
    final days = read.days;
    final settings = AdaptiveStore.settings.value;
    final counted =
        settings.activityMode != ActivityMode.off && settings.countSteps;
    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('Steps', style: theme.textTheme.titleMedium),
                ),
              ),
              if (read.on)
                TextButton(
                  key: const ValueKey('steps-goal'),
                  onPressed: () => _editGoal(read.goal),
                  child: Text('Goal ${_count(read.goal)}'),
                ),
            ],
          ),
          if (!read.on) ...[
            Text(
              counted
                  ? 'Daily steps from Health Connect, read only. Expenditure '
                        'counts them as activity once they are read.'
                  : 'Daily steps from Health Connect, read only. They change '
                        'no target: the expenditure estimate already counts '
                        'what you walk.',
              style: theme.textTheme.bodySmall,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const ValueKey('steps-on'),
                onPressed: _turnOn,
                child: const Text('Read steps'),
              ),
            ),
          ] else if (read.failed || days == null) ...[
            Text(
              'Health Connect refused the read. Allow steps for the app '
              'there, or connect again.',
              style: theme.textTheme.bodySmall,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _turnOn,
                child: const Text('Connect again'),
              ),
            ),
          ] else
            ..._summary(context, days, read.goal),
          if (read.on && counted)
            Padding(
              padding: const EdgeInsets.only(top: Dimens.spacing8),
              child: Text(
                'Expenditure counts these steps as activity. Stopping also '
                'stops counting them.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (read.on)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const ValueKey('steps-off'),
                onPressed: _steps.turnOff,
                child: const Text('Stop reading steps'),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _summary(
    BuildContext context,
    Map<DateTime, int> days,
    int goal,
  ) {
    final now = widget.clock();
    final today = DateTime(now.year, now.month, now.day);
    // Today is still going, so it stays out of the average.
    final past = [
      for (final MapEntry(:key, :value) in days.entries)
        if (key != today) value,
    ];
    return [
      _row('Today', _count(days[today] ?? 0)),
      if (past.isNotEmpty) ...[
        _row(
          'Daily average, past days',
          _count((past.reduce((a, b) => a + b) / past.length).round()),
        ),
        _row(
          'Past days at the goal',
          '${past.where((s) => s >= goal).length} of ${past.length}',
        ),
      ],
      const SizedBox(height: Dimens.spacing16),
      _chart(context, days, goal, today),
    ];
  }

  Widget _chart(
    BuildContext context,
    Map<DateTime, int> days,
    int goal,
    DateTime today,
  ) {
    final accent = Theme.of(context).colorScheme.primary;
    final first = DateTime(
      today.year,
      today.month,
      today.day - widget.rangeDays + 1,
    );
    final most = [goal, ...days.values].reduce((a, b) => a > b ? a : b);
    return Semantics(
      label: 'Daily steps',
      child: SizedBox(
        height: 120,
        child: BarChart(
          BarChartData(
            maxY: most * 1.1,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: const FlTitlesData(show: false),
            barTouchData: BarTouchData(enabled: false),
            extraLinesData: ExtraLinesData(
              horizontalLines: [
                HorizontalLine(
                  y: goal.toDouble(),
                  color: widget.palette.textMuted,
                  strokeWidth: 1,
                  dashArray: const [6, 4],
                ),
              ],
            ),
            barGroups: [
              for (final MapEntry(key: day, value: steps) in days.entries)
                BarChartGroupData(
                  x: DateTime.utc(day.year, day.month, day.day)
                      .difference(
                        DateTime.utc(first.year, first.month, first.day),
                      )
                      .inDays,
                  barRods: [
                    BarChartRodData(
                      toY: steps.toDouble(),
                      // Muted, not a faded accent: that fell under 3:1
                      // on the light card.
                      color: steps >= goal ? accent : widget.palette.textMuted,
                      width: widget.rangeDays > 31 ? 2 : 6,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _count(int steps) =>
      NumberFormat.decimalPattern().format(steps);

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

class _GoalDialog extends StatefulWidget {
  final int goal;

  const _GoalDialog({required this.goal});

  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  late final _field = TextEditingController(text: '${widget.goal}');

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Daily step goal'),
    content: TextField(
      key: const ValueKey('steps-goal-field'),
      controller: _field,
      autofocus: true,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: const InputDecoration(suffixText: 'steps'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () {
          final steps = int.tryParse(_field.text);
          if (steps != null && steps > 0 && steps <= 100000) {
            Navigator.pop(context, steps);
          }
        },
        child: const Text('Save'),
      ),
    ],
  );
}
