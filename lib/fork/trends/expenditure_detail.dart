import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/expenditure.dart'
    show minLoggedKcal;
import 'package:opennutritracker/fork/report/chart_touch.dart';
import 'package:opennutritracker/fork/report/nutrient_explorer.dart'
    show IntakeLoader, intakesBetween, dayStartMinutes;
import 'package:opennutritracker/fork/trends/detail_stats.dart';
import 'package:opennutritracker/fork/trends/detail_widgets.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';

/// The Expenditure page, after the canvas's TdExpB with TdExpA's table of
/// changes: now, the change and the average over the range, the pills, the
/// estimate drawn with what was logged, how it moved over set spans, how
/// the last 30 days add up, and the formula beside it.
List<Widget> expenditureBody(
  BuildContext context,
  TrendsLoaded state,
  List<ExpenditureDay> history, {
  required List<DateTime> dates,
  required Widget pills,
  AdaptiveService? service,
  IntakeLoader loadIntakes = intakesBetween,
}) {
  final unit = energyUnit(context);
  final series = expenditureSeries(history, dates);
  final present = series.whereType<double>();
  final change = present.length < 2 ? null : present.last - present.first;
  final mean = meanOf(series);
  const gap = SizedBox(height: Dimens.spacing16);
  return [
    StatHeader(
      stats: [
        (
          label: 'Now',
          value: present.isEmpty
              ? '–'
              : '${energyValue(context, present.last)}',
          unit: unit,
        ),
        (
          label: 'Change',
          value: change == null
              ? '–'
              : signedText(energyValue(context, change).toDouble()),
          unit: unit,
        ),
        (
          label: 'Average',
          value: mean == null ? '–' : '${energyValue(context, mean)}',
          unit: unit,
        ),
      ],
    ),
    gap,
    pills,
    if (history.isEmpty) ...[
      gap,
      noData(context, 'Expenditure is estimated from your first weigh-in.'),
    ] else ...[
      gap,
      ExpenditureChart(history: history, dates: dates),
      trendSection(context, 'Changes in expenditure'),
      ExpenditureChanges(history: history),
      if (expenditureBreakdown(history) case final b?) ...[
        trendSection(context, 'Last ${b.of} days'),
        _Breakdown(breakdown: b),
        const SizedBox(height: Dimens.spacing8),
        _Tiles(
          history: history,
          breakdown: b,
          service: service ?? _locatorService(),
        ),
      ],
      trendSection(context, 'How much was logged'),
      _Logging(
        key: ValueKey(dates.first),
        state: state,
        history: history,
        dates: dates,
        load: loadIntakes,
      ),
      gap,
      const ExplainerLink(
        title: 'What is expenditure?',
        body:
            'The energy you burn in a day: resting, moving and digesting. '
            'It is worked out from what you log and how your trend weight '
            'moves, so it gets steadier the more days you log and weigh in.',
      ),
    ],
  ];
}

AdaptiveService? _locatorService() {
  try {
    return AdaptiveService.fromLocator();
  } catch (_) {
    // No locator, in widget tests.
    return null;
  }
}

String _day(BuildContext context, DateTime date) => intl.DateFormat.MMMd(
  Localizations.localeOf(context).toLanguageTag(),
).format(date);

/// The estimate a day over the window as a line, fitted to its own
/// values, the energy on the right and three dates under it; a touched day
/// names its logged intake too.
class ExpenditureChart extends StatelessWidget {
  final List<ExpenditureDay> history;
  final List<DateTime> dates;

  const ExpenditureChart({
    super.key,
    required this.history,
    required this.dates,
  });

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final kj = usesKj(context);
    double shown(double kcal) => kj ? UnitCalc.kcalToKj(kcal) : kcal;
    final unit = energyUnit(context);
    final byDate = {
      for (final d in history)
        DateTime(d.date.year, d.date.month, d.date.day): d,
    };
    final spent = [
      for (final (i, date) in dates.indexed)
        if (byDate[date] case final d?)
          FlSpot(i.toDouble(), shown(d.expenditureKcal))
        else
          FlSpot.nullSpot,
    ];
    final values = [
      for (final s in spent)
        if (s != FlSpot.nullSpot) s.y,
    ];
    if (values.isEmpty) {
      return noData(context, 'No estimate in this range.');
    }
    final step = _niceStep(
      (values.reduce(math.max) - values.reduce(math.min)) / 3,
    );
    final minY = (values.reduce(math.min) / step).floor() * step;
    final maxY = (values.reduce(math.max) / step).ceil() * step;
    final muted = palette.textMuted;
    final small = theme.textTheme.labelSmall?.copyWith(color: muted);
    // The axis as wide as its widest number at the user's font, so the
    // numbers stay on one line (Android scales large text less than
    // small, so a scaled constant falls short).
    final widest = TextPainter(
      text: TextSpan(text: '${(maxY + step).round()}', style: small),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final axis = widest.width + 8;
    widest.dispose();
    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: 'Expenditure chart',
            child: SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: math.max(dates.length - 1, 1).toDouble(),
                  minY: minY,
                  maxY: maxY == minY ? maxY + step : maxY,
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval: step,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: palette.border, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(),
                    topTitles: const AxisTitles(),
                    bottomTitles: const AxisTitles(),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: step,
                        reservedSize: axis,
                        getTitlesWidget: (y, meta) => SideTitleWidget(
                          meta: meta,
                          child: Text('${y.round()}', style: small),
                        ),
                      ),
                    ),
                  ),
                  lineTouchData: labelledTouch(
                    context,
                    (s) => 'Expenditure ${s.y.round()} $unit',
                    after: (s) =>
                        switch (byDate[dates[s.x.toInt()]]?.intakeKcal) {
                          final kcal? =>
                            '\nLogged ${shown(kcal).round()} $unit',
                          null => '',
                        },
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spent,
                      isCurved: true,
                      preventCurveOverShooting: true,
                      color: accent,
                      barWidth: 3,
                      dotData: FlDotData(
                        checkToShowDot: (spot, bar) => spot == bar.spots.last,
                        getDotPainter: (_, _, _, _) =>
                            FlDotCirclePainter(radius: 5, color: accent),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (dates.length >= 2)
            DefaultTextStyle.merge(
              style: small,
              child: Padding(
                padding: EdgeInsets.only(right: axis),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_day(context, dates.first)),
                    if (dates.length >= 3)
                      Text(_day(context, dates[dates.length ~/ 2])),
                    Text(_day(context, dates.last)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: Dimens.spacing8),
          ChartLegend(
            entries: [(label: 'Expenditure', color: accent, line: true)],
          ),
        ],
      ),
    );
  }

  /// A round step near [raw]: 1, 2 or 5 times a power of ten.
  static double _niceStep(double raw) {
    if (raw <= 0) return 100;
    final p = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    for (final m in [1, 2, 5, 10]) {
      if (m * p >= raw) return m * p;
    }
    return 10 * p;
  }
}

/// The estimate now against 3, 7, 14, 30 and 90 days before: the change,
/// and what it was then.
class ExpenditureChanges extends StatelessWidget {
  final List<ExpenditureDay> history;

  const ExpenditureChanges({super.key, required this.history});

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final text = Theme.of(context).textTheme;
    final unit = energyUnit(context);
    final head = text.labelSmall?.copyWith(color: palette.textMuted);
    // TalkBack reads a row as one sentence, on its first cell; the other
    // cells are left out.
    Widget cell(
      String s, {
      TextStyle? style,
      bool first = false,
      String? spoken,
    }) {
      final shown = Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
          s,
          textAlign: first ? TextAlign.start : TextAlign.end,
          style: style,
        ),
      );
      return spoken == null
          ? ExcludeSemantics(child: shown)
          : Semantics(label: spoken, excludeSemantics: true, child: shown);
    }

    String said(({int days, double? change, double? then}) c) {
      final over = 'Over ${c.days} days';
      if (c.change == null || c.then == null) {
        return '$over: not enough history yet';
      }
      final change = energyValue(context, c.change!);
      final then = '${energyValue(context, c.then!)} $unit';
      if (change == 0) return '$over: no change, at $then';
      return '$over: ${change > 0 ? 'up' : 'down'} ${change.abs()} $unit, '
          'from $then';
    }

    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: Dimens.spacing16,
        vertical: Dimens.spacing4,
      ),
      child: Table(
        key: const ValueKey('expenditure-changes'),
        children: [
          TableRow(
            children: [
              cell('Over', style: head, first: true),
              cell('Change', style: head),
              cell('Was', style: head),
            ],
          ),
          for (final c in expenditureChanges(history))
            TableRow(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: palette.border)),
              ),
              children: [
                cell('${c.days} days', first: true, spoken: said(c)),
                cell(
                  c.change == null
                      ? '–'
                      : '${signedText(energyValue(context, c.change!).toDouble())} $unit',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                cell(
                  c.then == null
                      ? '–'
                      : '${energyValue(context, c.then!)} $unit',
                  style: TextStyle(color: palette.textMuted),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

typedef _Sum = ({
  double eaten,
  double fromWeight,
  double burnt,
  int logged,
  int of,
});

/// Eaten, plus what the weight change made up, is burnt.
class _Breakdown extends StatelessWidget {
  final _Sum breakdown;

  const _Breakdown({required this.breakdown});

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final text = Theme.of(context).textTheme;
    final accent = Theme.of(context).colorScheme.primary;
    final b = breakdown;
    final lost = b.fromWeight >= 0;
    Widget figure(String value, String label, {Color? color}) => Expanded(
      child: MergeSemantics(
        child: Column(
          children: [
            Text(
              value,
              style: text.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: palette.textMuted),
            ),
          ],
        ),
      ),
    );
    Widget sign(String s) => ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing4),
        child: Text(s, style: text.titleMedium),
      ),
    );
    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          figure('${energyValue(context, b.eaten)}', 'eaten a day'),
          sign(lost ? '+' : '−'),
          figure(
            '${energyValue(context, b.fromWeight.abs())}',
            lost ? 'from weight lost' : 'stored as weight',
          ),
          sign('='),
          figure(
            '${energyValue(context, b.burnt)}',
            'burnt a day',
            color: accent,
          ),
        ],
      ),
    );
  }
}

/// How many days the estimate stands on, and the formula beside it.
class _Tiles extends StatefulWidget {
  final List<ExpenditureDay> history;
  final _Sum breakdown;
  final AdaptiveService? service;

  const _Tiles({
    required this.history,
    required this.breakdown,
    required this.service,
  });

  @override
  State<_Tiles> createState() => _TilesState();
}

class _TilesState extends State<_Tiles> {
  late final Future<double?> _formula = _read();

  Future<double?> _read() async {
    try {
      return await widget.service?.formulaKcal();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.breakdown;
    final settled = widget.history.last.settled;
    final now = widget.history.last.expenditureKcal;
    return FutureBuilder(
      future: _formula,
      builder: (context, snapshot) {
        final formula = snapshot.data;
        final days = FigureTile(
          label: 'Days logged',
          value: '${b.logged}',
          unit: 'of ${b.of}',
          note: settled
              ? 'enough for a steady estimate'
              : 'the formula until two weeks are logged',
        );
        if (formula == null || formula <= 0) return days;
        final off = ((now - formula) / formula * 100).round();
        return FigureGrid(
          tiles: [
            days,
            FigureTile(
              label: 'Formula estimate',
              value: '${energyValue(context, formula)}',
              unit: energyUnit(context),
              note: off == 0
                  ? 'yours is about the same'
                  : 'yours runs ${off.abs()}% '
                        '${off > 0 ? 'higher' : 'lower'}',
            ),
          ],
        );
      },
    );
  }
}

/// How fully the range was logged, which says how far to trust the
/// estimate: the days logged, the entries a day, and the days the estimate
/// leaves out.
class _Logging extends StatefulWidget {
  final TrendsLoaded state;
  final List<ExpenditureDay> history;
  final List<DateTime> dates;
  final IntakeLoader load;

  const _Logging({
    super.key,
    required this.state,
    required this.history,
    required this.dates,
    required this.load,
  });

  @override
  State<_Logging> createState() => _LoggingState();
}

class _LoggingState extends State<_Logging> {
  late final Future<double?> _entries = _count();

  Future<double?> _count() async {
    try {
      return entriesPerDay(
        await widget.load(widget.dates.first, widget.dates.last),
        dayStartMinutes: await dayStartMinutes(),
      );
    } catch (_) {
      // No database, in widget tests.
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = loggingCompleteness(
      widget.state.days,
      widget.history,
      widget.dates,
      AdaptiveStore.skipped.value,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FutureBuilder(
          future: _entries,
          builder: (context, snapshot) => TrendRows(
            rows: [
              (label: 'Logged', value: '${c.logged} of ${days(c.of)}'),
              (
                label: 'Entries a day',
                value: snapshot.data?.toStringAsFixed(1) ?? '–',
              ),
              (label: 'Counted in the estimate', value: days(c.counted)),
              if (c.skipped > 0)
                (label: 'Left out by you', value: days(c.skipped)),
              if (c.partial > 0)
                (label: 'Too little logged to count', value: days(c.partial)),
            ],
          ),
        ),
        const SizedBox(height: Dimens.spacing8),
        Text(
          'The estimate counts a day once it has '
          '${energyText(context, minLoggedKcal)} or more logged, unless you '
          'leave it out. The more of the range it counts, the more it can be '
          'trusted.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: paletteOf(context).textMuted),
        ),
      ],
    );
  }
}
