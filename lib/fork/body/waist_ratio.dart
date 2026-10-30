import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/calendar_day_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/fork/body/side_compare.dart' show SideUnits;
import 'package:opennutritracker/fork/report/chart_touch.dart';
import 'package:opennutritracker/fork/trends/detail_widgets.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';

/// What the ratios are taken against: the profile's height, and its
/// gender for the waist-to-hip cut-off.
typedef BodyFrame = ({double heightCm, UserGenderEntity gender});

/// The profile's frame; null with no profile (widget tests). Tests swap it.
Future<BodyFrame?> Function() loadBodyFrame = () async {
  try {
    final user = await locator<GetUserUsecase>().getUserData();
    return (heightCm: user.heightCM, gender: user.gender);
  } catch (_) {
    return null;
  }
};

/// One day the waist was measured: its ratio to the height, and to the
/// hips when they were measured that day.
typedef WaistPoint = ({
  DateTime date,
  double waistCm,
  double ratio,
  double? hipRatio,
});

/// Each day the waist was measured, oldest first; none without a height.
List<WaistPoint> waistPoints(List<Measurement> all, double heightCm) {
  if (heightCm <= 0) return const [];
  DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
  final hips = {
    for (final m in all)
      if (m.metric == BodyMetric.hips) day(m.date): m.value,
  };
  return [
    for (final m in all)
      if (m.metric == BodyMetric.waist)
        (
          date: day(m.date),
          waistCm: m.value,
          ratio: m.value / heightCm,
          hipRatio: switch (hips[day(m.date)]) {
            final h? when h > 0 => m.value / h,
            _ => null,
          },
        ),
  ];
}

/// NICE's bands for adults (2022): under 0.5 no increased health risk,
/// to 0.6 increased, beyond it high.
String waistBand(double ratio) => ratio < 0.5
    ? 'no increased risk'
    : ratio < 0.6
    ? 'increased risk'
    : 'high risk';

/// WHO's waist-to-hip ratio above which the risk is substantially raised
/// (2008): 0.90 for men, 0.85 for women; null for anyone else.
double? hipCutOff(UserGenderEntity gender) => switch (gender) {
  UserGenderEntity.male => 0.90,
  UserGenderEntity.female => 0.85,
  UserGenderEntity.nonBinary => null,
};

/// The Trends tile's figures: the latest ratio and its band; null with no
/// waist measured or no height.
({String value, String suffix})? waistTileText(List<WaistPoint> points) {
  final last = points.lastOrNull;
  if (last == null) return null;
  return (value: last.ratio.toStringAsFixed(2), suffix: waistBand(last.ratio));
}

const _explainer =
    'Your waist divided by your height. NICE advises adults to keep their '
    'waist to less than half their height (2022): 0.4 to 0.49 carries no '
    'increased health risk, 0.5 to 0.59 an increased one, 0.6 or more a '
    'high one. It reads fat around the middle, which BMI misses.\n\n'
    'Measure halfway between the bottom of your ribs and the top of your '
    'hips, after breathing out. Every day is divided by your profile '
    'height.\n\n'
    'Waist to hips, on a day both were measured: WHO counts the risk as '
    'substantially raised above 0.90 for men and 0.85 for women (2008).';

/// Waist to height (S120's tiles): the latest ratio and its band, waist to
/// hips beside it, the ratio over the range against the 0.5 line, and each
/// day the waist was measured.
class WaistRatioPage extends StatefulWidget {
  final bool imperial;
  final int rangeDays;
  final Future<List<Measurement>> Function() load;
  final Future<BodyFrame?> Function()? frame;

  const WaistRatioPage({
    super.key,
    required this.imperial,
    required this.rangeDays,
    this.load = _all,
    this.frame,
  });

  static Future<List<Measurement>> _all() async => MeasurementStore().all();

  @override
  State<WaistRatioPage> createState() => _WaistRatioPageState();
}

class _WaistRatioPageState extends State<WaistRatioPage> {
  late var _data = _read();

  Future<(List<Measurement>, BodyFrame?)> _read() => (
    widget.load().catchError((Object _) => <Measurement>[]),
    (widget.frame ?? loadBodyFrame)(),
  ).wait;

  void _reload() => setState(() {
    _data = _read();
  });

  @override
  void initState() {
    super.initState();
    MeasurementStore.changes.addListener(_reload);
  }

  @override
  void dispose() {
    MeasurementStore.changes.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Waist to height')),
    body: FutureBuilder(
      future: _data,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return _body(context, data.$1, data.$2);
      },
    ),
  );

  Widget _body(BuildContext context, List<Measurement> all, BodyFrame? frame) {
    final units = SideUnits(widget.imperial);
    final points = waistPoints(all, frame?.heightCm ?? 0);
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day - widget.rangeDays + 1);
    final inRange = [
      for (final p in points)
        if (!p.date.isBefore(from)) p,
    ];
    // None in the range: all of them, said under the chart, as the left
    // and right page does.
    final charted = inRange.isEmpty ? points : inRange;
    final last = points.lastOrNull;
    final cutOff = frame == null ? null : hipCutOff(frame.gender);
    final hipNote = cutOff == null
        ? 'WHO: over 0.90 for men, 0.85 for women'
        : 'WHO: over ${cutOff.toStringAsFixed(2)} raises the risk';
    return ListView(
      padding: EdgeInsets.fromLTRB(
        Dimens.spacing16,
        Dimens.spacing8,
        Dimens.spacing16,
        Dimens.spacing32 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        if (last == null)
          Text(
            frame == null || frame.heightCm <= 0
                ? 'Set your height in your profile, and measure your waist '
                      'under Body measurements, to see it against your '
                      'height.'
                : 'Measure your waist under Body measurements to see it '
                      'against your height.',
          )
        else ...[
          StatHeader(
            stats: [
              (
                label: 'Waist to height',
                value: last.ratio.toStringAsFixed(2),
                unit: null,
              ),
              (
                label: 'Waist',
                value: units.shown(last.waistCm).toStringAsFixed(1),
                unit: units.unit,
              ),
              if (last.hipRatio case final hip?)
                (
                  label: 'Waist to hips',
                  value: hip.toStringAsFixed(2),
                  unit: null,
                ),
            ],
          ),
          const SizedBox(height: Dimens.spacing8),
          Text(
            '${toBeginningOfSentenceCase(waistBand(last.ratio))}, '
            '${DateFormat.yMMMd().format(last.date)}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (last.hipRatio != null)
            Text(hipNote, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: Dimens.spacing16),
        _RatioChart(
          points: charted,
          caption: inRange.isEmpty && points.isNotEmpty
              ? 'None in the last ${widget.rangeDays} days; all since '
                    '${DateFormat.yMMM().format(points.first.date)}.'
              : null,
        ),
        const SizedBox(height: Dimens.spacing12),
        const ExplainerLink(
          title: 'What is waist to height?',
          body: _explainer,
        ),
        if (points.isNotEmpty) ...[
          trendSection(context, 'Waist measured'),
          TrendRows(
            rows: [
              for (final p in points.reversed)
                (
                  label: DateFormat.yMMMd().format(p.date),
                  value:
                      '${p.ratio.toStringAsFixed(2)} · waist '
                      '${units.text(p.waistCm)}'
                      '${p.hipRatio == null ? '' : '\nWaist to hips ${p.hipRatio!.toStringAsFixed(2)}'}',
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The ratio over the range, against NICE's 0.5.
class _RatioChart extends StatelessWidget {
  final List<WaistPoint> points;

  /// Why the chart shows other days than the range's, under the legend.
  final String? caption;

  const _RatioChart({required this.points, this.caption});

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final theme = Theme.of(context);
    if (points.isEmpty) return noData(context, 'No waist measured yet.');
    final first = points.first.date;
    double x(DateTime d) => CalendarDayCalc.daysBetween(first, d).toDouble();
    final spots = [for (final p in points) FlSpot(x(p.date), p.ratio)];
    final ys = [0.5, for (final s in spots) s.y];
    final low = ys.reduce(math.min);
    final high = ys.reduce(math.max);
    final pad = math.max((high - low) * 0.15, 0.02);
    final color = theme.colorScheme.primary;
    final small = theme.textTheme.labelSmall?.copyWith(
      color: palette.textMuted,
    );
    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: 'Waist to height chart, with the 0.5 line',
            child: SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: math.max(x(points.last.date), 1),
                  minY: low - pad,
                  maxY: high + pad,
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: palette.border, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      HorizontalLine(
                        y: 0.5,
                        color: palette.textMuted,
                        strokeWidth: 1.5,
                        dashArray: [6, 4],
                      ),
                    ],
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(),
                    topTitles: const AxisTitles(),
                    bottomTitles: const AxisTitles(),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 44,
                        // Not the padded ends: they crowd the line's.
                        getTitlesWidget: (y, meta) =>
                            y == meta.min || y == meta.max
                            ? const SizedBox()
                            : SideTitleWidget(
                                meta: meta,
                                child: Text(y.toStringAsFixed(2), style: small),
                              ),
                      ),
                    ),
                  ),
                  lineTouchData: labelledTouch(
                    context,
                    (s) => s.y.toStringAsFixed(2),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      color: color,
                      barWidth: 3,
                      dotData: FlDotData(
                        getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                          radius: 3,
                          color: color,
                          strokeWidth: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: Dimens.spacing8),
          ChartLegend(
            entries: [
              (label: 'Waist to height', color: color, line: true),
              (label: '0.5', color: palette.textMuted, line: true),
            ],
          ),
          if (caption != null) ...[
            const SizedBox(height: Dimens.spacing8),
            Text(caption!, style: small),
          ],
        ],
      ),
    );
  }
}

/// Opens the ratio over the last [rangeDays].
void openWaistRatio(
  BuildContext context, {
  required bool imperial,
  required int rangeDays,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => WaistRatioPage(imperial: imperial, rangeDays: rangeDays),
  ),
);
