// Fork-owned copy of lib/features/home/presentation/widgets/dashboard_widget.dart
// (D23); upstream's later changes to it are ported by hand:
// fork/tools/upstream-copies.sh.
import 'package:animated_flip_counter/animated_flip_counter.dart';
import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/home/domain/entity/nutrient_contribution_entity.dart';
import 'package:opennutritracker/features/home/presentation/screens/nutrient_contributions_screen.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/kcal_goal_info_screen.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/display/week_bars.dart';
import 'package:opennutritracker/fork/display/macro_foods.dart';
import 'package:opennutritracker/fork/adaptive/activity_credit.dart';
import 'package:opennutritracker/fork/adaptive/activity.dart'
    show maxDailyActivityKcal;
import 'package:provider/provider.dart';

class DashboardWidget extends StatefulWidget {
  final double totalKcalDaily;
  final double totalKcalLeft;
  final double totalKcalSupplied;
  final double totalKcalBurned;
  final double totalCarbsIntake;
  final double totalFatsIntake;
  final double totalProteinsIntake;
  final double totalCarbsGoal;
  final double totalFatsGoal;
  final double totalProteinsGoal;

  /// The day's logged foods, which a macro tile breaks its total into
  /// (#1266).
  final List<IntakeEntity> intakes;

  /// For a food's details, opened from a macro's contributions.
  final bool usesImperialUnits;

  // Home's (logical) day, which the week's bars
  // end on
  final DateTime? forkDay;

  const DashboardWidget({
    super.key,
    required this.totalKcalSupplied,
    required this.totalKcalBurned,
    required this.totalKcalDaily,
    required this.totalKcalLeft,
    required this.totalCarbsIntake,
    required this.totalFatsIntake,
    required this.totalProteinsIntake,
    required this.totalCarbsGoal,
    required this.totalFatsGoal,
    required this.totalProteinsGoal,
    this.intakes = const [],
    this.usesImperialUnits = false,
    this.forkDay,
  });

  @override
  State<DashboardWidget> createState() => _DashboardWidgetState();
}

class _DashboardWidgetState extends State<DashboardWidget> {
  // whether Burned raises the goal; a fixed or
  // adaptive target leaves it out (read again as Home reloads)
  late Future<ActivityCredit> _forkCredit = activityCredit();

  @override
  void didUpdateWidget(DashboardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _forkCredit = activityCredit();
  }

  void _openKcalGoalInfoScreen() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const KcalGoalInfoScreen()));
  }

  void _openNutrientContributions(
    MacroNutrient nutrient,
    double total,
    double goal,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NutrientContributionsScreen(
          nutrient: nutrient,
          intakes: widget.intakes,
          total: total,
          goal: goal,
          day: DateTime.now(),
          usesImperialUnits: widget.usesImperialUnits,
          // every total, for the page's switch
          forkTotals: {
            FoodsMetric.energy: (
              eaten: widget.totalKcalSupplied,
              goal: widget.totalKcalDaily,
            ),
            FoodsMetric.carbs: (
              eaten: widget.totalCarbsIntake,
              goal: widget.totalCarbsGoal,
            ),
            FoodsMetric.fat: (
              eaten: widget.totalFatsIntake,
              goal: widget.totalFatsGoal,
            ),
            FoodsMetric.protein: (
              eaten: widget.totalProteinsIntake,
              goal: widget.totalProteinsGoal,
            ),
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double kcalValue = 0;
    double gaugeValue = 0;
    final usesKilojoules = context.watch<EnergyUnitProvider>().usesKilojoules;
    String kcalLabelText = usesKilojoules
        ? '${S.of(context).kjLabel} ${S.of(context).energyLeftLabel}'
        : S.of(context).kcalLeftLabel;

    if (widget.totalKcalLeft > widget.totalKcalDaily) {
      kcalValue = widget.totalKcalDaily;
      gaugeValue = 0;
    } else if (widget.totalKcalLeft < 0) {
      kcalValue = widget.totalKcalLeft.abs();
      gaugeValue = 1;
      kcalLabelText = usesKilojoules
          ? '${S.of(context).kjLabel} ${S.of(context).energyTooMuchLabel}'
          : S.of(context).kcalTooMuchLabel;
    } else {
      kcalValue = widget.totalKcalLeft;
      gaugeValue =
          (widget.totalKcalDaily - widget.totalKcalLeft) /
          widget.totalKcalDaily;
    }
    final displaySupplied = usesKilojoules
        ? UnitCalc.kcalToKj(widget.totalKcalSupplied)
        : widget.totalKcalSupplied;
    final displayGoal = usesKilojoules
        ? UnitCalc.kcalToKj(widget.totalKcalDaily)
        : widget.totalKcalDaily;
    // Left is the goal less what was eaten, as shown: each rounded first,
    // as every energy figure is (energyValue), so the three add up.
    final leftIsGoalLessEaten =
        (widget.totalKcalDaily -
                widget.totalKcalSupplied -
                widget.totalKcalLeft)
            .abs() <
        0.5;
    final double displayValue =
        leftIsGoalLessEaten && widget.totalKcalLeft <= widget.totalKcalDaily
        ? (displayGoal.round() - displaySupplied.round()).abs().toDouble()
        : usesKilojoules
        ? UnitCalc.kcalToKj(kcalValue)
        : kcalValue;
    final displayBurned = usesKilojoules
        ? UnitCalc.kcalToKj(widget.totalKcalBurned)
        : widget.totalKcalBurned;

    final palette = paletteOf(context);
    final textTheme = Theme.of(context).textTheme;
    final progressColor = widget.totalKcalLeft < 0
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;

    // MacroFactor's dashboard. A small ring beside
    // what was eaten, burned and the goal, the ring counting what is left
    // or what was eaten; the macros in columns, each "g left" or "g over";
    // and the week's bars, all in one card (upstream: a large ring between
    // two stats, then three macro tiles).
    return ValueListenableBuilder<bool>(
      valueListenable: DisplayPrefs.homeShowsEaten,
      builder: (context, showsEaten, _) {
        final ringValue = showsEaten ? displaySupplied : displayValue;
        final ringLabel = showsEaten
            ? '${usesKilojoules ? S.of(context).kjLabel : S.of(context).kcalLabel} eaten'
            : kcalLabelText;
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            Dimens.spacing16,
            Dimens.spacing8,
            Dimens.spacing16,
            Dimens.spacing4,
          ),
          child: AppCard(
            padding: const EdgeInsets.all(Dimens.spacing16),
            child: Column(
              children: [
                Row(
                  children: [
                    Semantics(
                      identifier: 'home-kcal-gauge',
                      label: '${ringValue.round()} $ringLabel',
                      hint: S.of(context).settingsKcalGoalInfoLabel,
                      button: true,
                      excludeSemantics: true,
                      // excludeSemantics strips the GestureDetector's tap
                      // along with the rest, so the node needs its own.
                      onTap: _openKcalGoalInfoScreen,
                      // The ring opens the calorie goal's derivation.
                      child: Tooltip(
                        message: S.of(context).settingsKcalGoalInfoLabel,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _openKcalGoalInfoScreen,
                          child: CircularPercentIndicator(
                            radius: 58,
                            lineWidth: 10,
                            percent: gaugeValue.clamp(0.0, 1.0),
                            animation: true,
                            // The first build shows the real value at once;
                            // a later change (a meal logged) animates.
                            animateToInitialPercent: false,
                            animationDuration: 800,
                            curve: AppMotion.emphasized,
                            circularStrokeCap: CircularStrokeCap.round,
                            backgroundColor: palette.surfaceMuted,
                            progressColor: progressColor,
                            // Large text shrinks to stay inside the stroke.
                            center: SizedBox(
                              // the label sits low, where the ring is narrower
                              width: 72,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AnimatedFlipCounter(
                                      duration: const Duration(
                                        milliseconds: 800,
                                      ),
                                      curve: AppMotion.emphasized,
                                      value: ringValue.round(),
                                      textStyle: textTheme.headlineSmall
                                          ?.copyWith(
                                            height: 1,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    Text(
                                      ringLabel,
                                      style: textTheme.labelSmall?.copyWith(
                                        color: palette.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: Dimens.spacing16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _StatLine(
                            label: 'Eaten',
                            value: '${displaySupplied.round()}',
                          ),
                          // "+" only where it is added
                          FutureBuilder<ActivityCredit>(
                            future: _forkCredit,
                            builder: (context, credit) =>
                                credit.data == ActivityCredit.dailyCapped &&
                                    widget.totalKcalBurned >
                                        maxDailyActivityKcal
                                // The goal counts the burn up to its cap
                                ? _StatLine(
                                    label: 'Burned, up to',
                                    value:
                                        '+${(usesKilojoules ? UnitCalc.kcalToKj(maxDailyActivityKcal) : maxDailyActivityKcal).round()}',
                                  )
                                : credit.data?.raisesGoal ?? true
                                ? _StatLine(
                                    label: 'Burned',
                                    value: '+${displayBurned.round()}',
                                  )
                                : _StatLine(
                                    label: 'Burned, not added',
                                    value: '${displayBurned.round()}',
                                  ),
                          ),
                          _StatLine(
                            label: 'Goal',
                            value: '${displayGoal.round()}',
                          ),
                          const SizedBox(height: Dimens.spacing8),
                          SegmentedButton<bool>(
                            key: const ValueKey('home-ring-mode'),
                            showSelectedIcon: false,
                            style: const ButtonStyle(
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.padded,
                            ),
                            segments: const [
                              ButtonSegment(value: false, label: Text('Left')),
                              ButtonSegment(value: true, label: Text('Eaten')),
                            ],
                            selected: {showsEaten},
                            onSelectionChanged: (picked) =>
                                DisplayPrefs.setHomeShowsEaten(picked.first),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Dimens.spacing16),
                // the macros in the user's order
                MacroOrderBuilder(
                  // at large font sizes the macros
                  // stack, so labels and values are not broken mid-word.
                  builder: (context) => Flex(
                    direction: _stackMacros(context)
                        ? Axis.vertical
                        : Axis.horizontal,
                    crossAxisAlignment: _stackMacros(context)
                        ? CrossAxisAlignment.stretch
                        : CrossAxisAlignment.start,
                    children: [
                      for (final (i, column) in inMacroOrder(
                        carbs: _MacroLeft(
                          label: S.of(context).carbsLabel,
                          intake: widget.totalCarbsIntake,
                          goal: widget.totalCarbsGoal,
                          color: palette.carbs,
                          identifier: 'home-macro-carbs',
                          onTap: () => _openNutrientContributions(
                            MacroNutrient.carbs,
                            widget.totalCarbsIntake,
                            widget.totalCarbsGoal,
                          ),
                        ),
                        fat: _MacroLeft(
                          label: S.of(context).fatLabel,
                          intake: widget.totalFatsIntake,
                          goal: widget.totalFatsGoal,
                          color: palette.fat,
                          identifier: 'home-macro-fat',
                          onTap: () => _openNutrientContributions(
                            MacroNutrient.fat,
                            widget.totalFatsIntake,
                            widget.totalFatsGoal,
                          ),
                        ),
                        protein: _MacroLeft(
                          label: S.of(context).proteinLabel,
                          intake: widget.totalProteinsIntake,
                          goal: widget.totalProteinsGoal,
                          color: palette.protein,
                          identifier: 'home-macro-protein',
                          onTap: () => _openNutrientContributions(
                            MacroNutrient.protein,
                            widget.totalProteinsIntake,
                            widget.totalProteinsGoal,
                          ),
                        ),
                      ).indexed) ...[
                        if (i > 0)
                          const SizedBox(
                            width: Dimens.spacing12,
                            height: Dimens.spacing8,
                          ),
                        if (_stackMacros(context))
                          column
                        else
                          Expanded(child: column),
                      ],
                    ],
                  ),
                ),
                Divider(height: Dimens.spacing24, color: palette.border),
                WeekBars(
                  today: widget.forkDay ?? DateTime.now(),
                  todayKcal: widget.totalKcalSupplied,
                  todayGoalKcal: widget.totalKcalDaily,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// true when text is scaled past 1.3×.
bool _stackMacros(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(10) > 13;

// upstream's _MiniStat and _MacroTile went with the
// large ring and the macro tiles.

/// "Eaten  2897", one line of the stats beside the ring.
class _StatLine extends StatelessWidget {
  final String label;
  final String value;

  const _StatLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(color: palette.textMuted),
            ),
          ),
          Text(
            value,
            style: textTheme.bodyMedium?.copyWith(
              color: palette.textStrong,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// A macro's column: "51 g left" (or "9 g over", in red), a bar and its
/// name; tapping it lists the foods behind it (#1266).
class _MacroLeft extends StatelessWidget {
  final String label;
  final double intake;
  final double goal;
  final Color color;
  final String identifier;
  final VoidCallback onTap;

  const _MacroLeft({
    required this.label,
    required this.intake,
    required this.goal,
    required this.color,
    required this.identifier,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final textTheme = Theme.of(context).textTheme;
    final error = Theme.of(context).colorScheme.error;
    final pct = goal <= 0 ? 0.0 : (intake / goal).clamp(0.0, 1.0);
    final over = goal > 0 && intake.round() > goal.round();
    final grams = (goal - intake).abs().round();
    return Semantics(
      identifier: identifier,
      hint: S.of(context).nutrientContributionsHint,
      button: true,
      label:
          '$label: ${intake.round()} of ${goal.round()} g, '
          '$grams g ${over ? 'over' : 'left'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: Dimens.borderRadiusS,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Dimens.spacing4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$grams g',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: over ? error : palette.textStrong,
                      ),
                    ),
                    TextSpan(text: over ? ' over' : ' left'),
                  ],
                ),
                style: textTheme.bodySmall?.copyWith(color: palette.textMuted),
              ),
              const SizedBox(height: Dimens.spacing4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 5,
                  backgroundColor: palette.surfaceMuted,
                  valueColor: AlwaysStoppedAnimation(over ? error : color),
                ),
              ),
              const SizedBox(height: Dimens.spacing4),
              Text(
                label,
                style: textTheme.labelSmall?.copyWith(color: palette.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
