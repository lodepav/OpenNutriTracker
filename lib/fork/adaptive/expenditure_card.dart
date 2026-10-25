import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';

/// Seam S40: on Trends, the estimated expenditure over the picked range
/// with what was logged, and the mean energy balance of the logged days.
/// Nothing until the first weigh-in.
class ExpenditureTrendCard extends StatefulWidget {
  final int rangeDays;
  final AppPalette palette;
  final AdaptiveService? service;

  const ExpenditureTrendCard({
    super.key,
    required this.rangeDays,
    required this.palette,
    this.service,
  });

  @override
  State<ExpenditureTrendCard> createState() => _ExpenditureTrendCardState();
}

class _ExpenditureTrendCardState extends State<ExpenditureTrendCard> {
  late final _service = widget.service ?? AdaptiveService.fromLocator();
  late Future<List<ExpenditureDay>> _history = _service.expenditureHistory();

  /// The estimate moves with the expenditure settings and the days left
  /// out (D17).
  late final _changes = Listenable.merge([
    AdaptiveStore.settings,
    AdaptiveStore.skipped,
  ]);

  @override
  void initState() {
    super.initState();
    _changes.addListener(_reload);
  }

  @override
  void dispose() {
    _changes.removeListener(_reload);
    super.dispose();
  }

  void _reload() => setState(() => _history = _service.expenditureHistory());

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ExpenditureDay>>(
    future: _history,
    builder: (context, snapshot) {
      final all = snapshot.data;
      if (all == null || all.isEmpty) return const SizedBox.shrink();
      final days = all.length > widget.rangeDays
          ? all.sublist(all.length - widget.rangeDays)
          : all;
      return Padding(
        padding: const EdgeInsets.only(top: Dimens.spacing16),
        child: _chart(context, days),
      );
    },
  );

  Widget _chart(BuildContext context, List<ExpenditureDay> days) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final kj = usesKj(context);
    double shown(double kcal) => kj ? UnitCalc.kcalToKj(kcal) : kcal;

    final spent = [
      for (final (i, d) in days.indexed)
        FlSpot(i.toDouble(), shown(d.expenditureKcal)),
    ];
    final eaten = [
      for (final (i, d) in days.indexed)
        d.intakeKcal == null
            ? FlSpot.nullSpot
            : FlSpot(i.toDouble(), shown(d.intakeKcal!)),
    ];
    final values = [
      for (final s in [...spent, ...eaten])
        if (s != FlSpot.nullSpot) s.y,
    ];
    final minY = values.reduce((a, b) => a < b ? a : b) * 0.85;
    final maxY = values.reduce((a, b) => a > b ? a : b) * 1.1;

    final logged = days.where((d) => d.intakeKcal != null).toList();
    final balance = logged.isEmpty
        ? null
        : logged
                  .map((d) => d.intakeKcal! - d.expenditureKcal)
                  .reduce((a, b) => a + b) /
              logged.length;

    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Its own node, so the heading is the title, not the card.
          Semantics(
            container: true,
            header: true,
            child: Text('Expenditure', style: theme.textTheme.titleMedium),
          ),
          Text(
            'Energy you burn a day, estimated from your weigh-ins and logs.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: widget.palette.textMuted,
            ),
          ),
          const SizedBox(height: Dimens.spacing8),
          _row(context, 'Now', energyText(context, days.last.expenditureKcal)),
          if (balance != null)
            _row(
              context,
              'Balance, logged days',
              '${energyText(context, balance, signed: true)} a day',
            ),
          const SizedBox(height: Dimens.spacing16),
          Semantics(
            label: 'Expenditure chart',
            child: SizedBox(
              height: 140,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: (days.length - 1).clamp(1, 1 << 30).toDouble(),
                  minY: minY,
                  maxY: maxY,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => [
                        for (final s in spots)
                          LineTooltipItem(
                            '${s.barIndex == 0 ? 'Spent' : 'Logged'} '
                            '${s.y.round()}',
                            theme.textTheme.labelMedium ?? const TextStyle(),
                          ),
                      ],
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spent,
                      isCurved: true,
                      preventCurveOverShooting: true,
                      color: accent,
                      barWidth: 3,
                      dotData: const FlDotData(show: false),
                    ),
                    LineChartBarData(
                      spots: eaten,
                      color: widget.palette.textMuted,
                      barWidth: 1.2,
                      dashArray: const [4, 3],
                      dotData: FlDotData(show: days.length <= 31),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_legend(days, logged.length) case final legend?) ...[
            const SizedBox(height: Dimens.spacing8),
            Text(legend, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  /// Names only the lines drawn: a line takes two days, and a single day
  /// is a dot.
  static String? _legend(List<ExpenditureDay> days, int loggedDays) {
    const formula =
        'still the formula until two weeks of weigh-ins and logging';
    final settled = days.last.settled;
    final parts = [
      if (days.length >= 2)
        'Solid: estimated expenditure${settled ? '' : ', $formula'}'
      else if (!settled)
        'Estimated expenditure is $formula',
      if (loggedDays >= 2) 'Dashed: logged',
    ];
    return parts.isEmpty ? null : '${parts.join('. ')}.';
  }

  Widget _row(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}
