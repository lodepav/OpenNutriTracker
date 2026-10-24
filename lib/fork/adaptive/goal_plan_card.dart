import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/set_target_weight_dialog.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';
import 'package:opennutritracker/fork/units/weight_text.dart';

/// Bumped when [savePace] saved a pace (by hand or a diet phase), so the
/// goal planner reloads.
final paceChanges = ValueNotifier(0);

/// Saves [kgPerWeek] as the profile's pace, the goal following its sign,
/// through upstream's profile update (which rewrites today's goal). False
/// when a profile switch dropped the update: the user is read and written
/// for the profile current at [startedOn] (by default, as it begins).
Future<bool> savePace(double kgPerWeek, [ProfileStamp? startedOn]) async {
  // Read and updated under the tracked-day lock, which a switch takes too:
  // the update, under the same (reentrant) lock, writes to this profile.
  final saved = await withTrackedDayLockOnProfile(() async {
    final user = await locator<GetUserUsecase>().getUserData();
    user
      ..weeklyWeightGoalKg = kgPerWeek
      ..goal = kgPerWeek < 0
          ? UserWeightGoalEntity.loseWeight
          : kgPerWeek > 0
          ? UserWeightGoalEntity.gainWeight
          : UserWeightGoalEntity.maintainWeight;
    await locator<ProfileBloc>().updateUser(user);
    return true;
  }, startedOn: startedOn);
  if (saved == null) return false;
  paceChanges.value++;
  return true;
}

/// Asks for a target weight with upstream's dialog, seeded from [nowKg],
/// and saves it to the profile as the Profile page does. False when
/// cancelled, or a profile switch dropped the update.
Future<bool> setTargetWeight(
  BuildContext context,
  BodyWeightUnit unit,
  double nowKg,
) async {
  final startedOn = ProfileStamp.now();
  final result = await showDialog<TargetWeightDialogResult>(
    context: context,
    builder: (_) => SetTargetWeightDialog(
      initialKg: nowKg,
      hasExistingTarget: false,
      unit: unit,
    ),
  );
  final kg = result?.value;
  if (kg == null) return false;
  final saved = await withTrackedDayLockOnProfile(() async {
    final user = await locator<GetUserUsecase>().getUserData();
    user.targetWeightKg = kg;
    await locator<ProfileBloc>().updateUser(user);
    return true;
  }, startedOn: startedOn);
  if (saved == null) return false;
  paceChanges.value++;
  return true;
}

/// Seam S40: MacroFactor's goal planner on Trends. A pace slider shows the
/// projected weight curve to the target, when it is reached, and the
/// daily target that pace needs at the measured expenditure; "Use this
/// pace" saves it to the profile. Nothing before the first weigh-in.
class GoalPlanCard extends StatefulWidget {
  final AppPalette palette;
  final BodyWeightUnit unit;
  final AdaptiveService? service;
  final Future<void> Function(double kgPerWeek) onUsePace;
  final Future<bool> Function(
    BuildContext context,
    BodyWeightUnit unit,
    double nowKg,
  )
  onSetTarget;

  const GoalPlanCard({
    super.key,
    required this.palette,
    required this.unit,
    this.service,
    this.onUsePace = savePace,
    this.onSetTarget = setTargetWeight,
  });

  @override
  State<GoalPlanCard> createState() => _GoalPlanCardState();
}

class _GoalPlanCardState extends State<GoalPlanCard> {
  late Future<GoalPlanInputs?> _inputs = _load();
  double? _pace;

  Future<GoalPlanInputs?> _load() =>
      (widget.service ?? AdaptiveService.fromLocator()).goalPlan();

  void _reload() {
    if (!mounted) return;
    setState(() {
      _pace = null;
      _inputs = _load();
    });
  }

  @override
  void initState() {
    super.initState();
    paceChanges.addListener(_reload);
  }

  @override
  void dispose() {
    paceChanges.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<GoalPlanInputs?>(
    future: _inputs,
    builder: (context, snapshot) {
      final inputs = snapshot.data;
      if (inputs == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: Dimens.spacing16),
        child: _card(context, inputs),
      );
    },
  );

  String _weight(double kg) => weightText(kg, widget.unit);

  String _change(double kg) => weightChangeText(kg, widget.unit);

  String _paceText(double kgPerWeek) {
    final sign = kgPerWeek > 0 ? '+' : '';
    return switch (widget.unit) {
      BodyWeightUnit.kg => '$sign${kgPerWeek.toStringAsFixed(2)} kg a week',
      _ => '$sign${(kgPerWeek * 2.20462).toStringAsFixed(2)} lb a week',
    };
  }

  static String _date(int days) {
    final d = DateTime.now().add(Duration(days: days));
    final weeks = (days / 7).round();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')} '
        '($weeks week${weeks == 1 ? '' : 's'})';
  }

  String _eta(int? days, double kgPerDay, double nowKg, double target) {
    if (days == null) {
      return kgPerDay == 0 || (target - nowKg).abs() < 0.1
          ? 'At the target'
          : 'Moving away from the target';
    }
    return days > maxPlanDays ? 'Over a year' : _date(days);
  }

  Widget _card(BuildContext context, GoalPlanInputs inputs) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final pace = _pace ?? inputs.paceKgPerWeek;
    final plan = planAt(inputs, pace);
    final target = inputs.targetWeightKg;
    final trendPerDay = inputs.trendKgPerDay;

    final past = inputs.pastTrendKg;
    final offset = past.length - 1;
    final pastSpots = [
      for (final (i, kg) in past.indexed) FlSpot(i - offset.toDouble(), kg),
    ];
    final planSpots = [
      for (final (i, kg) in plan.projectedKg.indexed) FlSpot(i.toDouble(), kg),
    ];
    final ys = [...past, ...plan.projectedKg, ?target];
    final minY = ys.reduce((a, b) => a < b ? a : b) - 1;
    final maxY = ys.reduce((a, b) => a > b ? a : b) + 1;

    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text('Goal planner', style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: Dimens.spacing8),
          _row('Trend weight', _weight(inputs.nowKg)),
          for (final MapEntry(key: days, value: kg) in trendChanges(
            past,
          ).entries)
            _row(
              'Last $days days',
              '${_change(kg)} (${_paceText(kg / days * 7)})',
            ),
          if (target != null)
            _row('Target', _weight(target))
          else
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              children: [
                const Text('No target weight, so no date to reach it.'),
                TextButton(
                  key: const ValueKey('plan-set-target'),
                  onPressed: () async {
                    if (await widget.onSetTarget(
                      context,
                      widget.unit,
                      inputs.nowKg,
                    )) {
                      _reload();
                    }
                  },
                  child: const Text('Set target weight'),
                ),
              ],
            ),
          const SizedBox(height: Dimens.spacing16),
          Semantics(
            label: 'Projected weight',
            child: SizedBox(
              height: 140,
              child: LineChart(
                LineChartData(
                  minX: -offset.toDouble(),
                  maxX: (plan.projectedKg.length - 1).toDouble(),
                  minY: minY,
                  maxY: maxY,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  lineTouchData: const LineTouchData(enabled: false),
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      if (target != null)
                        HorizontalLine(
                          y: target,
                          color: widget.palette.textMuted,
                          strokeWidth: 1,
                          dashArray: const [6, 4],
                        ),
                    ],
                    verticalLines: [
                      VerticalLine(
                        x: 0,
                        color: widget.palette.textMuted.withValues(alpha: 0.4),
                        strokeWidth: 1,
                      ),
                    ],
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: pastSpots,
                      color: accent,
                      barWidth: 3,
                      dotData: const FlDotData(show: false),
                    ),
                    LineChartBarData(
                      spots: planSpots,
                      color: accent,
                      barWidth: 2,
                      dashArray: const [5, 4],
                      dotData: const FlDotData(show: false),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: Dimens.spacing8),
          Text(
            'Solid: your trend. Dashed: at the pace below.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: Dimens.spacing8),
          // The slider reads its own name and value.
          ExcludeSemantics(child: Text('Pace: ${_paceText(pace)}')),
          MergeSemantics(
            child: Semantics(
              label: 'Pace',
              child: Slider(
                key: const ValueKey('plan-pace'),
                min: -1,
                max: 1,
                divisions: 40,
                value: pace.clamp(-1.0, 1.0),
                semanticFormatterCallback: _paceText,
                onChanged: (v) => setState(() => _pace = v),
              ),
            ),
          ),
          if (target != null)
            _row(
              'Reached',
              _eta(plan.daysToTarget, pace / 7, inputs.nowKg, target),
            ),
          if (target != null && trendPerDay != null)
            _row(
              'At your trend (${_paceText(trendPerDay * 7)})',
              _eta(
                daysToTarget(inputs.nowKg, target, trendPerDay),
                trendPerDay,
                inputs.nowKg,
                target,
              ),
            ),
          _row(
            'Daily target at this pace',
            energyText(context, plan.dailyTargetKcal),
          ),
          Text(
            'From an expenditure of '
            '${energyText(context, inputs.expenditureKcal)}.',
            style: theme.textTheme.bodySmall,
          ),
          if ((pace - inputs.paceKgPerWeek).abs() > 0.001)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  await widget.onUsePace(pace);
                  _reload();
                },
                child: const Text('Use this pace'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    // A Wrap: at a large font the value moves under its label rather than
    // squeezing both into broken words.
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 12,
      children: [
        Text(label),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}
