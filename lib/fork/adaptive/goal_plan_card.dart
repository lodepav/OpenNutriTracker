import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/set_target_weight_dialog.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
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
    _setPace(user, kgPerWeek);
    await locator<ProfileBloc>().updateUser(user);
    return true;
  }, startedOn: startedOn);
  if (saved == null) return false;
  paceChanges.value++;
  return true;
}

/// [kgPerWeek] as [user]'s pace, the goal following its sign.
void _setPace(UserEntity user, double kgPerWeek) => user
  ..weeklyWeightGoalKg = kgPerWeek
  ..goal = kgPerWeek < 0
      ? UserWeightGoalEntity.loseWeight
      : kgPerWeek > 0
      ? UserWeightGoalEntity.gainWeight
      : UserWeightGoalEntity.maintainWeight;

/// Home's goal today were [kgPerWeek] the profile's pace, worked out as
/// Home works it out; null when a fixed or adaptive target sets Home's
/// goal, which the pace does not move today.
Future<double?> homeGoalAtPace(double kgPerWeek) async {
  final settings = AdaptiveStore.settings.value;
  if (settings.fixedTarget || settings.adaptiveTarget) return null;
  if (!locator.isRegistered<GetKcalGoalUsecase>()) return null;
  final user = await locator<GetUserUsecase>().getUserData();
  _setPace(user, kgPerWeek);
  return locator<GetKcalGoalUsecase>().getKcalGoal(userEntity: user);
}

/// Asks for a target weight with upstream's dialog, seeded from [targetKg]
/// or, with none yet, [nowKg], and saves it to the profile as the Profile
/// page does; with a target, Clear takes it off. False when cancelled, or
/// a profile switch dropped the update.
Future<bool> setTargetWeight(
  BuildContext context,
  BodyWeightUnit unit,
  double nowKg,
  double? targetKg,
) async {
  final startedOn = ProfileStamp.now();
  final result = await showDialog<TargetWeightDialogResult>(
    context: context,
    builder: (_) => SetTargetWeightDialog(
      initialKg: targetKg ?? nowKg,
      hasExistingTarget: targetKg != null,
      unit: unit,
    ),
  );
  if (result == null || (result.value == null && !result.clear)) return false;
  final saved = await withTrackedDayLockOnProfile(() async {
    final user = await locator<GetUserUsecase>().getUserData();
    user.targetWeightKg = result.value;
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

  /// Where the milestone step is kept; the active profile's by default.
  final PhaseStore? phases;

  /// False when the save was dropped (a profile switch).
  final Future<bool> Function(double kgPerWeek) onUsePace;
  final Future<bool> Function(
    BuildContext context,
    BodyWeightUnit unit,
    double nowKg,
    double? targetKg,
  )
  onSetTarget;
  final Future<double?> Function(double kgPerWeek) goalAtPace;

  const GoalPlanCard({
    super.key,
    required this.palette,
    required this.unit,
    this.service,
    this.phases,
    this.onUsePace = savePace,
    this.onSetTarget = setTargetWeight,
    this.goalAtPace = homeGoalAtPace,
  });

  @override
  State<GoalPlanCard> createState() => _GoalPlanCardState();
}

class _GoalPlanCardState extends State<GoalPlanCard> {
  late Future<GoalPlanInputs?> _inputs = _load();
  double? _pace;
  late final _phases = widget.phases ?? PhaseStore();

  /// The milestone step's place in [_steps] from 1; 0 for none.
  int _milestoneStep = 0;

  List<int> get _steps =>
      widget.unit == BodyWeightUnit.kg ? milestoneStepsKg : milestoneStepsLb;

  String get _stepUnit => widget.unit == BodyWeightUnit.kg ? 'kg' : 'lb';

  Future<void> _loadMilestoneStep() async {
    try {
      final step = await _phases.milestoneStep();
      if (mounted) setState(() => _milestoneStep = step);
    } catch (_) {
      // Unreadable: no milestones, as before there were any.
    }
  }

  Future<void> _setMilestoneStep(int step) async {
    setState(() => _milestoneStep = step);
    await _phases.saveMilestoneStep(step);
  }

  Future<GoalPlanInputs?> _load() =>
      (widget.service ?? AdaptiveService.fromLocator()).goalPlan();

  /// Home's goal at [_homeGoalPace], when the formula sets it; read as
  /// the pace moves.
  double? _homeGoal;
  double? _homeGoalPace;

  /// While a chosen pace is saved: the card keeps it rather than show the
  /// old one until the reload (JC2).
  bool _saving = false;

  Future<void> _readHomeGoal(double pace) async {
    _homeGoalPace = pace;
    double? goal;
    try {
      goal = await widget.goalAtPace(pace);
    } catch (_) {
      goal = null; // The planner's own figure stands.
    }
    if (mounted && _homeGoalPace == pace) setState(() => _homeGoal = goal);
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      // The chosen pace stays on screen until the saved one is read.
      _inputs = _load().then((inputs) {
        if (mounted) {
          setState(() {
            _pace = null;
            _saving = false;
          });
          if (inputs != null) _readHomeGoal(inputs.paceKgPerWeek);
        }
        return inputs;
      });
    });
  }

  @override
  void initState() {
    super.initState();
    paceChanges.addListener(_reload);
    _loadMilestoneStep();
    // A failed read is the FutureBuilder's to show.
    _inputs.then((inputs) {
      if (inputs != null) _readHomeGoal(inputs.paceKgPerWeek);
    }).ignore();
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
    // By the calendar: adding hours across a clock change can land on
    // the day before.
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, now.day + days);
    final weeks = (days / 7).round();
    // As the locale writes it, as the rest of the app does.
    return '${DateFormat.yMMMd().format(d)} '
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
    final homeGoal = _homeGoalPace == pace ? _homeGoal : null;
    // Read here: the unit can't be read in the tap.
    final done =
        'Goal set to ${_paceText(pace)}: '
        '${energyText(context, homeGoal ?? plan.dailyTargetKcal)} a day';
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
    final milestones = target == null || _milestoneStep == 0
        ? const <double>[]
        : milestonesKg(
            inputs.nowKg,
            target,
            _steps[_milestoneStep - 1],
            perKg: widget.unit == BodyWeightUnit.kg ? 1 : 2.20462,
          );
    final ys = [...past, ...plan.projectedKg, ?target];
    final minY = ys.reduce((a, b) => a < b ? a : b) - 1;
    final maxY = ys.reduce((a, b) => a > b ? a : b) + 1;

    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Its own node, so the heading is the title, not the card.
          Semantics(
            container: true,
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
            // Changed or cleared here too, as on You (JC4).
            Semantics(
              button: true,
              hint: 'Change or clear the target weight',
              child: InkWell(
                key: const ValueKey('plan-target'),
                onTap: () => _setTarget(inputs),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    children: [
                      Expanded(child: _row('Target', _weight(target))),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: widget.palette.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              children: [
                const Text('No target weight, so no date to reach it.'),
                TextButton(
                  key: const ValueKey('plan-set-target'),
                  onPressed: () => _setTarget(inputs),
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
                      for (final m in milestones)
                        HorizontalLine(
                          y: m,
                          color: widget.palette.textMuted.withValues(
                            alpha: 0.35,
                          ),
                          strokeWidth: 1,
                          dashArray: const [2, 4],
                        ),
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
                onChanged: (v) {
                  setState(() => _pace = v);
                  _readHomeGoal(v);
                },
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
          if (target != null) ..._milestoneRows(milestones, pace, inputs),
          // Under the formula, Home's goal is the formula's at the pace,
          // not the measured expenditure's (JC1).
          if (homeGoal != null) ...[
            _row('Your goal becomes', energyText(context, homeGoal)),
            Text(
              "Today's, from your profile's formula and activity, as Home "
              'shows it.',
              style: theme.textTheme.bodySmall,
            ),
          ] else ...[
            _row(
              'Daily target at this pace',
              energyText(context, plan.dailyTargetKcal),
            ),
            Text(
              'From an expenditure of '
              '${energyText(context, inputs.expenditureKcal)}.',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if ((pace - inputs.paceKgPerWeek).abs() > 0.001)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _saving ? null : () => _usePace(pace, done),
                child: const Text('Use this pace'),
              ),
            ),
        ],
      ),
    );
  }

  /// Saves [pace], then says [done].
  Future<void> _usePace(double pace, String done) async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final bool saved;
    try {
      saved = await widget.onUsePace(pace);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
      rethrow;
    }
    if (saved) messenger?.showSnackBar(SnackBar(content: Text(done)));
    _reload();
  }

  Future<void> _setTarget(GoalPlanInputs inputs) async {
    if (await widget.onSetTarget(
      context,
      widget.unit,
      inputs.nowKg,
      inputs.targetWeightKg,
    )) {
      _reload();
    }
  }

  /// The step choice, then each milestone and when the pace reaches it.
  List<Widget> _milestoneRows(
    List<double> milestones,
    double pace,
    GoalPlanInputs inputs,
  ) => [
    const SizedBox(height: Dimens.spacing8),
    Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('Milestones'),
        for (var i = 0; i <= _steps.length; i++)
          ChoiceChip(
            key: ValueKey('plan-milestones-$i'),
            label: Text(i == 0 ? 'Off' : 'Every ${_steps[i - 1]} $_stepUnit'),
            selected: _milestoneStep == i,
            onSelected: (_) => _setMilestoneStep(i),
          ),
      ],
    ),
    for (final m in milestones)
      switch (daysToTarget(inputs.nowKg, m, pace / 7)) {
        null => _row(_weight(m), 'Not at this pace'),
        final days => _row(
          _weight(m),
          days > maxPlanDays ? 'Over a year' : _date(days),
        ),
      },
    const SizedBox(height: Dimens.spacing8),
  ];

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
