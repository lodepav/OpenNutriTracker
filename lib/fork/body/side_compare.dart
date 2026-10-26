import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/utils/calc/calendar_day_calc.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/fork/report/chart_touch.dart';
import 'package:opennutritracker/fork/trends/detail_widgets.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';

const _cmPerInch = 2.54;

/// The pair compared: the arms or the thighs.
enum SidePart {
  arms('Arms', BodyMetric.leftArm, BodyMetric.rightArm),
  thighs('Thighs', BodyMetric.leftThigh, BodyMetric.rightThigh);

  final String label;
  final BodyMetric left;
  final BodyMetric right;

  const SidePart(this.label, this.left, this.right);
}

/// Which pair the tile and its page compare, per profile in the fork's
/// box; arms until set.
class SidePartPref {
  static const _key = 'sidePart';
  static final current = ValueNotifier(SidePart.arms);
  static var _loaded = false;

  /// Read the first time, and again on a profile switch.
  static void ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    _load();
    try {
      locator<HiveDBProvider>().addListener(_load);
    } catch (_) {
      // No locator in widget tests.
    }
  }

  static Future<void> _load() async {
    try {
      final name = (await AdaptiveStore.openActiveBox()).get(_key);
      current.value = name is String
          ? SidePart.values.byName(name)
          : SidePart.arms;
    } catch (_) {
      // No box (widget tests): arms.
    }
  }

  static Future<void> save(SidePart part) async {
    current.value = part;
    try {
      await (await AdaptiveStore.openActiveBox()).put(_key, part.name);
    } catch (_) {
      // No box (widget tests): kept for the session.
    }
  }
}

/// One day both sides were measured, in cm.
typedef SidePair = ({DateTime date, double left, double right});

/// Each day with both sides of [part] measured, oldest first.
List<SidePair> sidePairs(List<Measurement> all, SidePart part) {
  final left = <DateTime, double>{};
  final right = <DateTime, double>{};
  for (final m in all) {
    final day = DateTime(m.date.year, m.date.month, m.date.day);
    if (m.metric == part.left) left[day] = m.value;
    if (m.metric == part.right) right[day] = m.value;
  }
  return [
    for (final day in left.keys.toList()..sort())
      if (right[day] case final r?) (date: day, left: left[day]!, right: r),
  ];
}

/// Sizes and differences in the user's unit: inches for imperial.
class SideUnits {
  final bool imperial;

  const SideUnits(this.imperial);

  String get unit => imperial ? 'in' : 'cm';

  double shown(double cm) => imperial ? cm / _cmPerInch : cm;

  String text(double cm) => '${shown(cm).toStringAsFixed(1)} $unit';

  /// The way [pair] differs: "Right bigger by 0.8 cm", or equal when it
  /// rounds to nothing.
  String difference(SidePair pair) {
    final diff = pair.right - pair.left;
    if (shown(diff.abs()) < 0.05) return 'Both equal';
    return '${diff > 0 ? 'Right' : 'Left'} bigger by ${text(diff.abs())}';
  }
}

/// The Trends tile's figures: the latest difference and which side is
/// bigger; null with no day of both sides measured.
({String value, String? suffix})? sideTileText(
  List<SidePair> pairs,
  SideUnits units,
) {
  if (pairs.isEmpty) return null;
  final last = pairs.last;
  final diff = last.right - last.left;
  if (units.shown(diff.abs()) < 0.05) return (value: 'Equal', suffix: null);
  return (
    value: units.shown(diff.abs()).toStringAsFixed(1),
    suffix: '${units.unit} · ${diff > 0 ? 'right' : 'left'} bigger',
  );
}

/// Left against right (S120's tiles): the pair picked, both sides as
/// lines over the range, their latest sizes and difference, and each day
/// both were measured.
class SideComparePage extends StatefulWidget {
  final bool imperial;
  final int rangeDays;
  final Future<List<Measurement>> Function() load;

  const SideComparePage({
    super.key,
    required this.imperial,
    required this.rangeDays,
    this.load = _all,
  });

  static Future<List<Measurement>> _all() async => MeasurementStore().all();

  @override
  State<SideComparePage> createState() => _SideComparePageState();
}

class _SideComparePageState extends State<SideComparePage> {
  late Future<List<Measurement>> _all = _read();

  Future<List<Measurement>> _read() =>
      widget.load().catchError((Object _) => <Measurement>[]);

  void _reload() => setState(() {
    _all = _read();
  });

  @override
  void initState() {
    super.initState();
    SidePartPref.ensureLoaded();
    MeasurementStore.changes.addListener(_reload);
  }

  @override
  void dispose() {
    MeasurementStore.changes.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: SidePartPref.current,
    builder: (context, part, _) => Scaffold(
      appBar: AppBar(title: Text('${part.label}: left and right')),
      body: FutureBuilder(
        future: _all,
        builder: (context, snapshot) {
          final all = snapshot.data;
          if (all == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return _body(context, part, all);
        },
      ),
    ),
  );

  Widget _body(BuildContext context, SidePart part, List<Measurement> all) {
    final units = SideUnits(widget.imperial);
    final pairs = sidePairs(all, part);
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day - widget.rangeDays + 1);
    final inRange = [
      for (final m in all)
        if ((m.metric == part.left || m.metric == part.right) &&
            !m.date.isBefore(from))
          m,
    ];
    final last = pairs.lastOrNull;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        Dimens.spacing16,
        Dimens.spacing8,
        Dimens.spacing16,
        Dimens.spacing32 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        SegmentedButton<SidePart>(
          segments: [
            for (final p in SidePart.values)
              ButtonSegment(value: p, label: Text(p.label)),
          ],
          selected: {part},
          showSelectedIcon: false,
          onSelectionChanged: (s) => SidePartPref.save(s.single),
        ),
        const SizedBox(height: Dimens.spacing16),
        if (last == null)
          Text(
            'Measure your left and right ${part.label.toLowerCase()} on the '
            'same day, under Body measurements, to compare them.',
          )
        else ...[
          StatHeader(
            stats: [
              (
                label: 'Left',
                value: units.shown(last.left).toStringAsFixed(1),
                unit: units.unit,
              ),
              (
                label: 'Right',
                value: units.shown(last.right).toStringAsFixed(1),
                unit: units.unit,
              ),
              (
                label: 'Difference',
                value: units
                    .shown((last.right - last.left).abs())
                    .toStringAsFixed(1),
                unit: units.unit,
              ),
            ],
          ),
          const SizedBox(height: Dimens.spacing8),
          Text(
            '${units.difference(last)}, '
            '${DateFormat.yMMMd().format(last.date)}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ],
        const SizedBox(height: Dimens.spacing16),
        _SidesChart(part: part, measurements: inRange, units: units),
        if (pairs.isNotEmpty) ...[
          trendSection(context, 'Both sides measured'),
          TrendRows(
            rows: [
              for (final p in pairs.reversed)
                (
                  label: DateFormat.yMMMd().format(p.date),
                  value:
                      'L ${units.text(p.left)} · R ${units.text(p.right)}'
                      '\n${units.difference(p)}',
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Each side's sizes over the range, a line apiece.
class _SidesChart extends StatelessWidget {
  final SidePart part;
  final List<Measurement> measurements;
  final SideUnits units;

  const _SidesChart({
    required this.part,
    required this.measurements,
    required this.units,
  });

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final theme = Theme.of(context);
    if (measurements.isEmpty) {
      return noData(
        context,
        'No ${part.label.toLowerCase()} measured in '
        'this range.',
      );
    }
    final first = measurements.first.date;
    double x(DateTime d) => CalendarDayCalc.daysBetween(first, d).toDouble();
    List<FlSpot> spots(BodyMetric metric) => [
      for (final m in measurements)
        if (m.metric == metric) FlSpot(x(m.date), units.shown(m.value)),
    ];
    final left = spots(part.left);
    final right = spots(part.right);
    final ys = [
      for (final s in [...left, ...right]) s.y,
    ];
    final low = ys.reduce(math.min);
    final high = ys.reduce(math.max);
    final pad = math.max((high - low) * 0.15, 0.5);
    final leftColor = theme.colorScheme.primary;
    final rightColor = palette.fat;
    final small = theme.textTheme.labelSmall?.copyWith(
      color: palette.textMuted,
    );
    LineChartBarData line(List<FlSpot> s, Color color) => LineChartBarData(
      spots: s,
      color: color,
      barWidth: 3,
      dotData: FlDotData(
        getDotPainter: (_, _, _, _) =>
            FlDotCirclePainter(radius: 3, color: color, strokeWidth: 0),
      ),
    );
    final lastX = x(measurements.last.date);
    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: '${part.label} chart, left and right',
            child: SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: math.max(lastX, 1),
                  minY: low - pad,
                  maxY: high + pad,
                  gridData: FlGridData(
                    drawVerticalLine: false,
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
                        reservedSize: 44,
                        // Not the padded ends: they crowd the lines'.
                        getTitlesWidget: (y, meta) =>
                            y == meta.min || y == meta.max
                            ? const SizedBox()
                            : SideTitleWidget(
                                meta: meta,
                                child: Text(y.toStringAsFixed(1), style: small),
                              ),
                      ),
                    ),
                  ),
                  lineTouchData: labelledTouch(
                    context,
                    (s) =>
                        '${s.barIndex == 0 ? 'Left' : 'Right'} '
                        '${s.y.toStringAsFixed(1)} ${units.unit}',
                  ),
                  lineBarsData: [
                    line(left, leftColor),
                    line(right, rightColor),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: Dimens.spacing8),
          ChartLegend(
            entries: [
              (label: 'Left', color: leftColor, line: true),
              (label: 'Right', color: rightColor, line: true),
            ],
          ),
        ],
      ),
    );
  }
}

/// Opens the comparison over the last [rangeDays].
void openSideCompare(
  BuildContext context, {
  required bool imperial,
  required int rangeDays,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => SideComparePage(imperial: imperial, rangeDays: rangeDays),
  ),
);
