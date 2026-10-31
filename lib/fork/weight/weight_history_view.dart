import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:flutter/semantics.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/calendar_day_calc.dart';
import 'package:opennutritracker/fork/adaptive/trend_points.dart';
import 'package:opennutritracker/fork/report/chart_touch.dart';
import 'package:opennutritracker/fork/trends/trend_detail.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';
import 'package:opennutritracker/fork/units/weight_text.dart'
    show bodyWeightText;
import 'package:opennutritracker/generated/l10n.dart';

/// The ranges, in days; 0 is everything since the first weigh-in.
const weightRanges = [(30, '30 d'), (90, '90 d'), (365, '1 y'), (0, 'All')];

/// The window [rangeDays] covers, ending today: All starts at the oldest
/// weigh-in, and never covers less than 30 days.
int weightWindowDays(
  int rangeDays,
  List<WeightLogEntity> entries,
  DateTime today,
) {
  if (rangeDays > 0) return rangeDays;
  final past = entries.where((e) => !e.date.isAfter(today));
  if (past.isEmpty) return 30;
  final oldest = past
      .map((e) => e.date)
      .reduce((a, b) => a.isBefore(b) ? a : b);
  // Calendar days (#1207).
  final days = CalendarDayCalc.daysBetween(oldest, today) + 1;
  return days < 30 ? 30 : days;
}

/// Seam S122: Weight history as MacroFactor's (WeightB): range chips, the
/// trend over the weigh-ins, the trend now with its change over the range
/// and per week, then each weigh-in with its change from the one before.
/// A weigh-in is swiped away to delete it, or deleted from its TalkBack
/// actions. The screen keeps the loading, the adding and the deleting.
class WeightHistoryView extends StatefulWidget {
  /// Newest first, as the screen sorts them.
  final List<WeightLogEntity> entries;
  final BodyWeightUnit unit;
  final double? targetWeightKg;
  final VoidCallback onAdd;

  /// A tapped weigh-in, to edit; Delete is beside it.
  final ValueChanged<WeightLogEntity>? onEdit;
  final ValueChanged<WeightLogEntity> onDelete;

  /// For tests.
  final DateTime? today;

  const WeightHistoryView({
    super.key,
    required this.entries,
    required this.unit,
    required this.targetWeightKg,
    required this.onAdd,
    this.onEdit,
    required this.onDelete,
    this.today,
  });

  @override
  State<WeightHistoryView> createState() => _WeightHistoryViewState();
}

class _WeightHistoryViewState extends State<WeightHistoryView> {
  var _rangeDays = 30;

  /// Swiped away and on their way out: a dismissed row must leave the tree
  /// before the screen has reloaded.
  final _gone = <WeightLogEntity>{};

  /// Each reload's rows are new ones: a weigh-in back after a reload (an
  /// undo, a delete that did not take) is not the dismissed row.
  var _generation = 0;

  @override
  void didUpdateWidget(WeightHistoryView old) {
    super.didUpdateWidget(old);
    if (old.entries != widget.entries) {
      _gone.clear();
      _generation++;
    }
  }

  DateTime get _today {
    final now = widget.today ?? DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  Widget build(BuildContext context) {
    final entries = [
      for (final e in widget.entries)
        if (!_gone.contains(e)) e,
    ];
    final today = _today;
    final windowDays = weightWindowDays(_rangeDays, entries, today);
    final dates = windowDates(today, windowDays);
    final stats = WeightTrendStats.of(entries, dates);
    final unit = widget.unit;
    final label = weightUnitLabel(context, unit);
    String? w(double? kg, {bool signed = false, int digits = 1}) => kg == null
        ? null
        : signed
        ? signedText(weightIn(unit, kg), digits)
        : weightIn(unit, kg).toStringAsFixed(digits);
    final rangeLabel = switch (_rangeDays) {
      30 => '30 days',
      90 => '90 days',
      365 => '1 year',
      _ => 'All time',
    };

    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).profileWeightHistoryTitle)),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Dimens.spacing12,
            Dimens.spacing8,
            Dimens.spacing12,
            Dimens.spacing12,
          ),
          child: Semantics(
            identifier: 'weight-history-add',
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: widget.onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Weigh in'),
            ),
          ),
        ),
      ),
      body: widget.entries.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  S.of(context).weightHistoryNoEntries,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                Dimens.spacing12,
                0,
                Dimens.spacing12,
                Dimens.spacing16,
              ),
              children: [
                _RangeChips(
                  rangeDays: _rangeDays,
                  onChanged: (d) => setState(() => _rangeDays = d),
                ),
                const SizedBox(height: Dimens.spacing8),
                AppCard(
                  padding: const EdgeInsets.fromLTRB(
                    Dimens.spacing8,
                    Dimens.spacing12,
                    Dimens.spacing12,
                    Dimens.spacing8,
                  ),
                  child: WeightHistoryChart(
                    entries: entries,
                    unit: unit,
                    targetWeightKg: widget.targetWeightKg,
                    dates: dates,
                  ),
                ),
                const SizedBox(height: Dimens.spacing8),
                Row(
                  children: [
                    for (final (i, (title, value)) in [
                      ('Trend', w(stats.nowKg).map((v) => '$v $label')),
                      (rangeLabel, w(stats.changeKg, signed: true)),
                      ('Per week', w(stats.perWeekKg, signed: true, digits: 2)),
                    ].indexed) ...[
                      if (i > 0) const SizedBox(width: Dimens.spacing8),
                      Expanded(
                        child: _StatTile(label: title, value: value ?? '–'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: Dimens.spacing8),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final (i, entry) in entries.indexed) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            color: paletteOf(context).surfaceMuted,
                          ),
                        _WeighInRow(
                          dismissKey: ValueKey((entry, _generation)),
                          entry: entry,
                          previous: i + 1 < entries.length
                              ? entries[i + 1]
                              : null,
                          unit: unit,
                          today: today,
                          onEdit: switch (widget.onEdit) {
                            final edit? => () => edit(entry),
                            null => null,
                          },
                          onDelete: () {
                            setState(() => _gone.add(entry));
                            widget.onDelete(entry);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: Dimens.spacing8),
                Text(
                  'Tap a weigh-in to edit or delete it',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: paletteOf(context).textMuted,
                  ),
                ),
              ],
            ),
    );
  }
}

extension<T extends Object> on T? {
  R? map<R>(R Function(T) f) => this == null ? null : f(this as T);
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;

  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: Dimens.spacing12,
        vertical: Dimens.spacing8,
      ),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: text.labelMedium?.copyWith(
                color: paletteOf(context).textMuted,
              ),
            ),
            Text(
              value,
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _RangeChips extends StatelessWidget {
  final int rangeDays;
  final ValueChanged<int> onChanged;

  const _RangeChips({required this.rangeDays, required this.onChanged});

  @override
  Widget build(BuildContext context) => Semantics(
    identifier: 'weight-history-range-selector',
    child: Wrap(
      spacing: Dimens.spacing8,
      children: [
        for (final (days, label) in weightRanges)
          Semantics(
            identifier: 'weight-history-range-$days',
            child: ChoiceChip(
              key: ValueKey('weight-history-range-$days'),
              label: Text(label),
              selected: days == rangeDays,
              showCheckmark: false,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              onSelected: (_) {
                if (days != rangeDays) onChanged(days);
              },
            ),
          ),
      ],
    ),
  );
}

/// The trend, thick, over the weigh-ins, thin; the goal weight dashed when
/// it is near enough to show.
class WeightHistoryChart extends StatelessWidget {
  final List<WeightLogEntity> entries;
  final BodyWeightUnit unit;
  final double? targetWeightKg;
  final List<DateTime> dates;

  const WeightHistoryChart({
    super.key,
    required this.entries,
    required this.unit,
    required this.targetWeightKg,
    required this.dates,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = paletteOf(context);
    final first = dates.first;
    final today = dates.last;
    double x(DateTime d) => CalendarDayCalc.daysBetween(first, d).toDouble();
    bool inWindow(DateTime d) => !d.isBefore(first) && !d.isAfter(today);

    final weighIns = entries.where((e) => inWindow(e.date)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    if (weighIns.length < 2) {
      return SizedBox(
        key: const Key('weightHistoryChartEmptyState'),
        height: 176,
        child: Center(
          child: Text(
            S.of(context).weightHistoryChartEmptyState,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: palette.textMuted,
            ),
          ),
        ),
      );
    }
    final scale = [
      for (final e in weighIns) FlSpot(x(e.date), weightIn(unit, e.weightKg)),
    ];
    // On the whole log, so the window's first days are not a fresh start.
    final trend = [
      for (final p in trendPoints(entries, until: today))
        if (inWindow(p.date)) FlSpot(x(p.date), weightIn(unit, p.weightKg)),
    ];
    final ys = [...scale, ...trend].map((s) => s.y);
    final minY = ys.reduce((a, b) => a < b ? a : b);
    final maxY = ys.reduce((a, b) => a > b ? a : b);
    final pad = ((maxY - minY) * 0.15).clamp(0.5, 5.0);
    final target = targetWeightKg == null
        ? null
        : weightIn(unit, targetWeightKg!);
    final showTarget =
        target != null && target >= minY - pad && target <= maxY + pad;
    final line = theme.colorScheme.primary;
    final label = weightUnitLabel(context, unit);
    final dateFormat = DateFormat.MMMd(
      Localizations.localeOf(context).toLanguageTag(),
    );
    final n = dates.length;
    // Large text needs room for "87.5" and a date under the plot.
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return SizedBox(
      key: const Key('weightHistoryChart'),
      height: 176,
      child: Semantics(
        label:
            'Weight over ${n == 1 ? 'a day' : '$n days'}, '
            'trend and weigh-ins',
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: (n - 1).toDouble(),
            minY: minY - pad,
            maxY: maxY + pad,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            lineTouchData: labelledTouch(
              context,
              (s) =>
                  '${s.barIndex == 0 ? 'Weighed' : 'Trend'} '
                  '${s.y.toStringAsFixed(1)} $label',
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 36 * textScale,
                  getTitlesWidget: (value, meta) =>
                      value == meta.min || value == meta.max
                      ? const SizedBox.shrink()
                      : Text(
                          value.toStringAsFixed(
                            value == value.roundToDouble() ? 0 : 1,
                          ),
                          style: theme.textTheme.labelSmall,
                        ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24 * textScale,
                  interval: ((n - 1) / 2).clamp(1, double.infinity),
                  getTitlesWidget: (value, meta) => Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      dateFormat.format(
                        DateUtils.addDaysToDate(first, value.round()),
                      ),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            extraLinesData: ExtraLinesData(
              horizontalLines: [
                if (showTarget)
                  HorizontalLine(
                    y: target,
                    color: theme.colorScheme.outline,
                    strokeWidth: 1.2,
                    dashArray: const [6, 4],
                  ),
              ],
            ),
            lineBarsData: [
              LineChartBarData(
                spots: scale,
                color: palette.textMuted,
                barWidth: 1.5,
                dotData: FlDotData(
                  getDotPainter: (spot, percent, bar, index) =>
                      FlDotCirclePainter(
                        radius: 2,
                        color: palette.textMuted,
                        strokeWidth: 0,
                      ),
                ),
              ),
              LineChartBarData(
                spots: trend,
                isCurved: true,
                preventCurveOverShooting: true,
                color: line,
                barWidth: 3,
                isStrokeCapRound: true,
                belowBarData: BarAreaData(
                  show: true,
                  color: line.withValues(alpha: 0.08),
                ),
                dotData: FlDotData(
                  checkToShowDot: (spot, bar) => spot == bar.spots.last,
                  getDotPainter: (spot, percent, bar, index) =>
                      FlDotCirclePainter(
                        radius: 5,
                        color: line,
                        strokeWidth: 0,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A weigh-in: its day, its change from the one before and its weight.
/// Swiped left, or from its TalkBack actions, it is deleted.
class _WeighInRow extends StatelessWidget {
  final Key dismissKey;
  final WeightLogEntity entry;
  final WeightLogEntity? previous;
  final BodyWeightUnit unit;
  final DateTime today;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;

  const _WeighInRow({
    required this.dismissKey,
    required this.entry,
    required this.previous,
    required this.unit,
    required this.today,
    this.onEdit,
    required this.onDelete,
  });

  /// Edit and Delete for a tap: a swipe was the only way to delete.
  Future<void> _actions(BuildContext context, String title) async {
    final edit = onEdit;
    final chosen = await showModalBottomSheet<VoidCallback>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: Dimens.spacing8),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (edit != null)
              Semantics(
                identifier: 'weigh-in-edit',
                child: ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit'),
                  onTap: () => Navigator.of(context).pop(edit),
                ),
              ),
            Semantics(
              identifier: 'weigh-in-delete',
              child: ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete'),
                onTap: () => Navigator.of(context).pop(onDelete),
              ),
            ),
          ],
        ),
      ),
    );
    chosen?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = paletteOf(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final date = DateTime(entry.date.year, entry.date.month, entry.date.day);
    final ago = CalendarDayCalc.daysBetween(date, today);
    final title = switch (ago) {
      0 => 'Today',
      1 => 'Yesterday',
      > 1 && < 7 => DateFormat.EEEE(locale).format(date),
      _ => DateFormat.yMMMd(locale).format(date),
    };
    final day = ago >= 0 && ago < 7
        ? (ago < 2 ? DateFormat.MMMEd(locale) : DateFormat.MMMd(locale)).format(
            date,
          )
        : null;
    final sub = [?day, if (entry.note?.isNotEmpty ?? false) entry.note!];
    final change = previous == null
        ? null
        : signedText(
            weightIn(unit, entry.weightKg) - weightIn(unit, previous!.weightKg),
            1,
          );
    final weight = bodyWeightText(context, entry.weightKg, unit);

    return Semantics(
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Delete'): onDelete,
      },
      child: Dismissible(
        key: dismissKey,
        direction: DismissDirection.endToStart,
        onDismissed: (_) => onDelete(),
        background: Container(
          color: theme.colorScheme.error,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing16),
          child: Icon(Icons.delete_outline, color: theme.colorScheme.onError),
        ),
        child: MergeSemantics(
          child: InkWell(
            onTap: () => _actions(context, '$title · $weight'),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Dimens.spacing12,
                  vertical: Dimens.spacing8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: theme.textTheme.bodyLarge),
                          if (sub.isNotEmpty)
                            Text(
                              sub.join(' · '),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: palette.textMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (change != null)
                      Container(
                        constraints: const BoxConstraints(minWidth: 44),
                        padding: const EdgeInsets.symmetric(
                          horizontal: Dimens.spacing8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: palette.surfaceMuted,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          change,
                          textAlign: TextAlign.center,
                          semanticsLabel: '$change since the one before',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                      ),
                    const SizedBox(width: Dimens.spacing12),
                    Text(
                      weight,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
