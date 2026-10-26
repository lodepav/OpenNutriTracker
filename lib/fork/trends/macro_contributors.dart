import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/meal_detail/meal_detail_screen.dart';
import 'package:opennutritracker/fork/display/macro_foods.dart';
import 'package:opennutritracker/fork/report/nutrient_explorer.dart'
    show IntakeLoader, intakesBetween;
import 'package:opennutritracker/fork/trends/trend_stats.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';

/// How many foods the card lists before "See all".
const topFoodsShown = 5;

/// A macro's days as bars, and the foods it came from below them: over the
/// period, or the day whose bar was tapped. All of them open on their own
/// page.
class MacroDaysAndFoods extends StatefulWidget {
  final FoodsMetric metric;
  final DaySeries series;
  final List<DateTime> dates;
  final double? goal;
  final Color color;
  final String chartLabel;
  final IntakeLoader load;

  const MacroDaysAndFoods({
    super.key,
    required this.metric,
    required this.series,
    required this.dates,
    required this.goal,
    required this.color,
    required this.chartLabel,
    this.load = intakesBetween,
  });

  @override
  State<MacroDaysAndFoods> createState() => _MacroDaysAndFoodsState();
}

class _MacroDaysAndFoodsState extends State<MacroDaysAndFoods> {
  int? _day;
  final _loaded = <(DateTime, DateTime), Future<List<IntakeEntity>>>{};

  Future<List<IntakeEntity>> _intakes(DateTime first, DateTime last) =>
      _loaded[(first, last)] ??= widget
          .load(first, last)
          // None to read (no locator, in widget tests): no foods.
          .catchError((Object _) => const <IntakeEntity>[]);

  @override
  void didUpdateWidget(MacroDaysAndFoods old) {
    super.didUpdateWidget(old);
    if (old.dates.length != widget.dates.length ||
        old.dates.lastOrNull != widget.dates.lastOrNull) {
      _day = null;
      _loaded.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final day = _day == null ? null : widget.dates[_day!];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.all(Dimens.spacing16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DailyBarChart(
                values: widget.series,
                dates: widget.dates,
                color: widget.color,
                goal: widget.goal,
                unit: 'g',
                label: widget.chartLabel,
                selected: _day,
                onTap: (i) => setState(() => _day = _day == i ? null : i),
              ),
              const SizedBox(height: Dimens.spacing8),
              Text(
                'Tap a day for its foods.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: paletteOf(context).textMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Dimens.spacing16),
        FutureBuilder(
          future: widget.dates.isEmpty
              ? Future.value(const <IntakeEntity>[])
              : _intakes(day ?? widget.dates.first, day ?? widget.dates.last),
          builder: (context, snapshot) => TopFoods(
            metric: widget.metric,
            color: widget.color,
            intakes: snapshot.data,
            scope: day == null
                ? 'Last ${widget.dates.length} days'
                : intl.DateFormat.MMMEd().format(day),
            onClearDay: day == null ? null : () => setState(() => _day = null),
          ),
        ),
      ],
    );
  }
}

/// The foods behind [metric] over the window [dates], loaded once: the
/// Calories page's.
class PeriodTopFoods extends StatefulWidget {
  final FoodsMetric metric;
  final List<DateTime> dates;
  final Color color;
  final IntakeLoader load;

  const PeriodTopFoods({
    super.key,
    required this.metric,
    required this.dates,
    required this.color,
    this.load = intakesBetween,
  });

  @override
  State<PeriodTopFoods> createState() => _PeriodTopFoodsState();
}

class _PeriodTopFoodsState extends State<PeriodTopFoods> {
  late final Future<List<IntakeEntity>> _intakes = widget.dates.isEmpty
      ? Future.value(const <IntakeEntity>[])
      : widget
            .load(widget.dates.first, widget.dates.last)
            .catchError((Object _) => const <IntakeEntity>[]);

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _intakes,
    builder: (context, snapshot) => TopFoods(
      metric: widget.metric,
      color: widget.color,
      intakes: snapshot.data,
      scope: 'Last ${widget.dates.length} days',
      onClearDay: null,
    ),
  );
}

/// The foods that gave the most of [metric], with a way to all of them.
class TopFoods extends StatelessWidget {
  final FoodsMetric metric;
  final Color color;
  final List<IntakeEntity>? intakes;
  final String scope;
  final VoidCallback? onClearDay;

  const TopFoods({
    super.key,
    required this.metric,
    required this.color,
    required this.intakes,
    required this.scope,
    required this.onClearDay,
  });

  void _open(BuildContext context, FoodShare share) =>
      Navigator.of(context).pushNamed(
        NavigationOptions.mealDetailRoute,
        arguments: MealDetailScreenArguments(
          share.meal,
          share.meals.first,
          share.first.dateTime,
          false,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = paletteOf(context);
    final shares = intakes == null
        ? const <FoodShare>[]
        : FoodShare.of(intakes!, metric);
    final total = shares.fold(0.0, (s, f) => s + f.value);
    final top = shares.isEmpty ? 0.0 : shares.first.value;
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: Dimens.spacing8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text('Top foods', style: text.titleMedium),
                      ),
                      Text(
                        scope,
                        style: text.bodySmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onClearDay != null)
                  TextButton(
                    onPressed: onClearDay,
                    child: const Text('All days'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Dimens.spacing4),
          if (intakes == null)
            const Padding(
              padding: EdgeInsets.all(Dimens.spacing16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (shares.isEmpty)
            Padding(
              padding: const EdgeInsets.all(Dimens.spacing16),
              child: Text(
                metric == FoodsMetric.energy
                    ? 'No foods logged in this range.'
                    : 'No foods logged with ${metric.name} in this range.',
                style: text.bodyMedium?.copyWith(color: palette.textMuted),
              ),
            )
          else ...[
            for (final (i, share) in shares.take(topFoodsShown).indexed) ...[
              if (i > 0) Divider(height: 1, color: palette.surfaceMuted),
              FoodShareRow(
                share: share,
                amount: metric == FoodsMetric.energy
                    ? energyText(context, share.value)
                    : share.value < 0.5
                    ? '<1 g'
                    : '${share.value.round()} g',
                percent: total > 0
                    ? '${(100 * share.value / total).round()}%'
                    : null,
                fraction: top > 0 ? share.value / top : 0,
                color: color,
                palette: palette,
                text: text,
                onTap: () => _open(context, share),
              ),
            ],
            if (shares.length > topFoodsShown)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Dimens.spacing8,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    key: const Key('top-foods-all'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MacroFoodsPage(
                          initial: metric,
                          intakes: intakes!,
                          totals: const {},
                          day: null,
                          title: 'Foods · $scope',
                        ),
                      ),
                    ),
                    child: Text('See all ${shares.length} foods'),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
