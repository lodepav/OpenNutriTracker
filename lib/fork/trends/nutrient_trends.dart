import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
import 'package:opennutritracker/fork/report/nutrient_explorer.dart';
import 'package:opennutritracker/fork/trends/detail_stats.dart';
import 'package:opennutritracker/fork/trends/detail_widgets.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';

/// The micronutrients Trends gives a tile and a page, by their names in
/// [explorerNutrients].
const microLabels = {
  TrendMetric.fibre: 'Fibre',
  TrendMetric.sugars: 'Sugars',
  TrendMetric.sodium: 'Salt',
};

ExplorerNutrient microNutrient(TrendMetric m) =>
    explorerNutrients.firstWhere((n) => n.label == microLabels[m]);

/// The window's intakes, with what reads them as the Diary does.
typedef MicroData = ({
  List<IntakeEntity> intakes,
  int dayStartMinutes,
  UserEntity? user,
});

/// [dates]' intakes through [load]; null without a database, in widget
/// tests.
Future<MicroData?> loadMicros(IntakeLoader load, List<DateTime> dates) async {
  if (dates.isEmpty) return null;
  try {
    return (
      intakes: await load(dates.first, dates.last),
      dayStartMinutes: await dayStartMinutes(),
      user: await loadUser(),
    );
  } catch (_) {
    return null;
  }
}

/// [m] each day of [dates], and its summary over them: the goal or limit,
/// and the foods it came from.
({DaySeries series, NutrientSummary summary}) microOf(
  MicroData data,
  List<TrackedDayEntity> days,
  List<DateTime> dates,
  TrendMetric m,
) {
  final nutrient = microNutrient(m);
  return (
    series: nutrientByDay(
      data.intakes,
      dates,
      nutrient,
      dayStartMinutes: data.dayStartMinutes,
    ),
    summary: summarizeNutrients(
      data.intakes,
      days,
      data.user,
      dayStartMinutes: data.dayStartMinutes,
    ).firstWhere((s) => s.nutrient == nutrient),
  );
}

/// The foods a page lists before "Show all".
const microTopFoods = 5;

/// A micronutrient's page: its average against the goal or limit, the
/// range, each day's bar, how the days went, and the foods it came from.
class MicroDetail extends StatefulWidget {
  final TrendMetric metric;
  final TrendsLoaded state;
  final List<DateTime> dates;
  final Widget pills;
  final IntakeLoader load;

  const MicroDetail({
    super.key,
    required this.metric,
    required this.state,
    required this.dates,
    required this.pills,
    required this.load,
  });

  @override
  State<MicroDetail> createState() => _MicroDetailState();
}

class _MicroDetailState extends State<MicroDetail> {
  late Future<MicroData?> _data = loadMicros(widget.load, widget.dates);
  var _allFoods = false;

  @override
  void didUpdateWidget(MicroDetail old) {
    super.didUpdateWidget(old);
    if (old.dates.first != widget.dates.first || old.state != widget.state) {
      _data = loadMicros(widget.load, widget.dates);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _data,
    builder: (context, snapshot) {
      const gap = SizedBox(height: Dimens.spacing16);
      final palette = paletteOf(context);
      final muted = Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: palette.textMuted);
      final nutrient = microNutrient(widget.metric);
      final unit = nutrient.unit;
      final data = snapshot.data;
      final micro = data == null
          ? null
          : microOf(data, widget.state.days, widget.dates, widget.metric);
      final series = micro?.series ?? [for (final _ in widget.dates) null];
      final mean = meanOf(series);
      final goal = micro?.summary.goal;
      final known = series.whereType<double>().toList();
      final good = goal == null
          ? null
          : known.where((v) => nutrient.isLimit ? v <= goal : v >= goal).length;
      final format = intl.DateFormat.MMMd(
        Localizations.localeOf(context).toLanguageTag(),
      );
      ({double v, DateTime on})? high;
      for (final (i, v) in series.indexed) {
        if (v != null && (high == null || v > high.v)) {
          high = (v: v, on: widget.dates[i]);
        }
      }
      final foods = micro?.summary.foods ?? const [];
      final without = micro?.summary.foodsWithout ?? 0;
      final shown = _allFoods ? foods : foods.take(microTopFoods).toList();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StatHeader(
            stats: [
              (
                label: 'Average',
                value: mean == null ? '–' : nutrient.text(mean),
                unit: unit,
              ),
              (
                label: nutrient.isLimit ? 'Limit' : 'Goal',
                value: goal == null ? '–' : nutrient.text(goal),
                unit: unit,
              ),
              (
                label: nutrient.isLimit ? 'Under it' : 'Met',
                value: good == null ? '–' : '$good',
                unit: 'of ${days(known.length)}',
              ),
            ],
          ),
          gap,
          widget.pills,
          gap,
          AppCard(
            padding: const EdgeInsets.all(Dimens.spacing16),
            child: DailyBarChart(
              values: series,
              dates: widget.dates,
              color: Theme.of(context).colorScheme.primary,
              goal: goal,
              unit: unit,
              format: nutrient.text,
              label: '${nutrient.label} chart',
            ),
          ),
          if (snapshot.connectionState == ConnectionState.done &&
              known.isEmpty) ...[
            const SizedBox(height: Dimens.spacing8),
            Text(
              'Nothing logged in this range has a figure for '
              '${nutrient.label.toLowerCase()}.',
              style: muted,
            ),
          ],
          if (known.isNotEmpty) ...[
            trendSection(context, 'How the days went'),
            TrendRows(
              rows: [
                if (good != null)
                  (
                    label: nutrient.isLimit
                        ? 'Over the limit'
                        : 'Short of the goal',
                    value: days(known.length - good),
                  ),
                if (high != null)
                  (
                    label: 'Highest',
                    value:
                        '${nutrient.text(high.v)} $unit, ${high.on == widget.dates.last ? 'today' : format.format(high.on)}',
                  ),
              ],
            ),
          ],
          if (foods.isNotEmpty) ...[
            trendSection(context, 'Where it came from'),
            TrendRows(
              rows: [
                for (final f in shown)
                  (label: f.name, value: '${nutrient.text(f.amount)} $unit'),
              ],
            ),
            if (foods.length > microTopFoods)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => setState(() => _allFoods = !_allFoods),
                  child: Text(
                    _allFoods ? 'Show fewer' : 'Show all ${foods.length}',
                  ),
                ),
              ),
          ],
          if (without > 0) ...[
            const SizedBox(height: Dimens.spacing8),
            Text(
              without == 1
                  ? '1 food logged here has no figure for '
                        '${nutrient.label.toLowerCase()}, so the real amount '
                        'may be higher.'
                  : '$without foods logged here have no figure for '
                        '${nutrient.label.toLowerCase()}, so the real amount '
                        'may be higher.',
              style: muted,
            ),
          ],
        ],
      );
    },
  );
}
