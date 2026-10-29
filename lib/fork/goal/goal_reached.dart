import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/calendar_day_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/set_target_weight_dialog.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/goal/goal_actions.dart';
import 'package:opennutritracker/fork/goal/goal_chart.dart';
import 'package:opennutritracker/fork/goal/goal_planner.dart';
import 'package:opennutritracker/fork/goal/phase_colors.dart';
import 'package:opennutritracker/fork/goal/planner_screen.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/trends/detail_widgets.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';
import 'package:opennutritracker/fork/units/weight_text.dart';

DateTime _date(DateTime t) => DateTime(t.year, t.month, t.day);

/// How a goal went: the trend since it started and the days logged.
class GoalRun {
  /// The trend, kg, one a day from the plan's start (or the first
  /// weigh-in after it) to today.
  final List<double> trend;
  final DateTime first;
  final double? meanKcal;

  /// Of the days since the start, the share logged, and of those the
  /// share within 10% of the day's calorie goal.
  final double? loggedShare;
  final double? onTargetShare;
  final double? expenditureKcal;

  const GoalRun({
    required this.trend,
    required this.first,
    this.meanKcal,
    this.loggedShare,
    this.onTargetShare,
    this.expenditureKcal,
  });
}

/// [plan]'s run from the profile's trend and diary.
Future<GoalRun> loadGoalRun(PhasePlan plan) async {
  final t = DateTime.now();
  final today = _date(t);
  final start = _date(plan.start);
  final span = CalendarDayCalc.daysBetween(start, today) + 1;
  final inputs = await AdaptiveService.fromLocator().goalPlan(pastDays: span);
  final trend = inputs?.pastTrendKg ?? const <double>[];
  final first = DateTime(today.year, today.month, today.day - trend.length + 1);
  if (!locator.isRegistered<GetTrackedDayUsecase>()) {
    return GoalRun(trend: trend, first: first);
  }
  final days = await locator<GetTrackedDayUsecase>().getTrackedDaysByRange(
    start,
    today,
  );
  final logged = days.where(isLogged).toList();
  final onTarget = logged.where(
    (d) =>
        d.calorieGoal > 0 &&
        (d.caloriesTracked - d.calorieGoal).abs() <= d.calorieGoal * 0.1,
  );
  return GoalRun(
    trend: trend,
    first: first,
    meanKcal: meanOf([for (final d in logged) d.caloriesTracked]),
    loggedShare: span <= 0 ? null : logged.length / span,
    onTargetShare: logged.isEmpty ? null : onTarget.length / logged.length,
    expenditureKcal: inputs?.expenditureKcal,
  );
}

/// Opens Goal reached for [plan] at the trend [nowKg]; true once the goal
/// was completed or extended.
Future<bool> openGoalReached(
  BuildContext context,
  PhasePlan plan,
  double nowKg,
  BodyWeightUnit unit,
) async =>
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GoalReachedPage(plan: plan, nowKg: nowKg, unit: unit),
      ),
    ) ??
    false;

enum _Next { maintain, extend, planNext }

/// Goal reached (round 4, B): the goal done, how it went, and what next:
/// complete it and maintain, extend it, or complete it and plan the next.
class GoalReachedPage extends StatefulWidget {
  final PhasePlan plan;
  final double nowKg;
  final BodyWeightUnit unit;
  final Future<GoalRun> Function(PhasePlan plan)? load;
  final GoalActions? actions;
  final DateTime? today;

  const GoalReachedPage({
    super.key,
    required this.plan,
    required this.nowKg,
    required this.unit,
    this.load,
    this.actions,
    this.today,
  });

  @override
  State<GoalReachedPage> createState() => _GoalReachedPageState();
}

class _GoalReachedPageState extends State<GoalReachedPage> {
  late final Future<GoalRun> _run = (widget.load ?? loadGoalRun)(widget.plan);
  var _next = _Next.maintain;
  var _busy = false;

  // Made as the page opens: its profile is the one acted on.
  late final GoalActions _actions;

  @override
  void initState() {
    super.initState();
    _actions = widget.actions ?? GoalActions();
  }

  Future<void> _continue() async {
    setState(() => _busy = true);
    var done = false;
    switch (_next) {
      case _Next.maintain:
        done = await _actions.complete(widget.plan, widget.nowKg);
      case _Next.extend:
        done = await showExtendSheet(
          context,
          widget.plan,
          widget.nowKg,
          widget.unit,
          ended: false,
          actions: _actions,
        );
      case _Next.planNext:
        done = await _actions.complete(widget.plan, widget.nowKg);
        if (done && mounted) await openGoalPlanner(context, fresh: true);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (done) {
      Navigator.of(context).pop(true);
    } else if (_next != _Next.extend) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not saved: the profile changed.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final unit = widget.unit;
    final theme = Theme.of(context);
    final today = _date(widget.today ?? DateTime.now());
    final locale = Localizations.localeOf(context).toLanguageTag();
    final format = intl.DateFormat.yMMMd(locale);
    final weeks = (CalendarDayCalc.daysBetween(plan.start, today) / 7).round();
    final startKg = plan.startKg;
    final target = plan.targetKg;
    return Scaffold(
      appBar: AppBar(title: const Text('Goal reached')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          Dimens.spacing16,
          Dimens.spacing8,
          Dimens.spacing16,
          Dimens.spacing32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Center(
            child: CircleAvatar(
              radius: 32,
              backgroundColor: phaseColor(context, plan.kind),
              child: Icon(
                Icons.check_rounded,
                size: 36,
                color: onPhaseColor(context, plan.kind),
              ),
            ),
          ),
          const SizedBox(height: Dimens.spacing12),
          Text(
            '${plan.kind.label}'
            '${target == null ? '' : ' to ${weightText(target, unit)}'}: done',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          Text(
            '${format.format(plan.start)} – ${format.format(today)} · '
            '$weeks ${weeks == 1 ? 'week' : 'weeks'}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: Dimens.spacing16),
          FutureBuilder(
            future: _run,
            builder: (context, snapshot) {
              final run = snapshot.data;
              if (run == null) {
                return const SizedBox(
                  height: 160,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (run.trend.length >= 2)
                    AppCard(
                      padding: const EdgeInsets.all(Dimens.spacing16),
                      child: GoalWeightChart(
                        trend: run.trend,
                        first: run.first,
                        unit: unit,
                        targetKg: target,
                        bands: [
                          for (final (i, p) in plan.phases.indexed)
                            (
                              start: plan.startOf(i),
                              end: plan.startOf(i + 1),
                              kind: p.kind,
                            ),
                        ],
                        label:
                            'Trend from ${weightText(run.trend.first, unit)} '
                            'to ${weightText(run.trend.last, unit)}',
                      ),
                    ),
                  const SizedBox(height: Dimens.spacing12),
                  FigureGrid(
                    tiles: [
                      FigureTile(
                        label: 'Change',
                        value: startKg == null
                            ? '–'
                            : weightChangeText(widget.nowKg - startKg, unit),
                        note: startKg == null
                            ? null
                            : '${weightText(startKg, unit)} → '
                                  '${weightText(widget.nowKg, unit)}',
                      ),
                      FigureTile(
                        label: 'Weeks',
                        value: '$weeks',
                        note: plan.extensions == 0
                            ? 'as planned: ${_plannedWeeks(plan)}'
                            : 'extended ${plan.extensions}×',
                      ),
                      FigureTile(
                        label: 'Average eaten',
                        value: run.meanKcal == null
                            ? '–'
                            : energyText(context, run.meanKcal!),
                        note: 'a logged day',
                      ),
                      FigureTile(
                        label: 'Days logged',
                        value: run.loggedShare == null
                            ? '–'
                            : '${(run.loggedShare! * 100).round()}%',
                        note: run.onTargetShare == null
                            ? null
                            : '${(run.onTargetShare! * 100).round()}% '
                                  'within 10% of the target',
                      ),
                      if (run.expenditureKcal != null)
                        FigureTile(
                          label: 'You burn now',
                          value: energyText(context, run.expenditureKcal!),
                          note: 'a day',
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
          trendSection(context, 'What next?'),
          RadioGroup<_Next>(
            groupValue: _next,
            onChanged: (v) => setState(() => _next = v ?? _next),
            child: AppCard(
              padding: const EdgeInsets.symmetric(vertical: Dimens.spacing4),
              child: Column(
                children: [
                  _choice(
                    _Next.maintain,
                    'goal-next-maintain',
                    'Mark completed and maintain',
                    'Eat at what you burn from today.',
                  ),
                  _choice(
                    _Next.extend,
                    'goal-next-extend',
                    'Extend the goal',
                    'Go on to a new weight, or for more weeks.',
                  ),
                  _choice(
                    _Next.planNext,
                    'goal-next-plan',
                    'Mark completed and plan the next',
                    'A new cut, maintenance or bulk.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Dimens.spacing16),
          Semantics(
            identifier: 'goal-reached-continue',
            child: FilledButton(
              onPressed: _busy ? null : _continue,
              child: const Text('Continue'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _choice(_Next value, String id, String title, String subtitle) =>
      Semantics(
        identifier: id,
        child: RadioListTile<_Next>(
          value: value,
          title: Text(title),
          subtitle: Text(subtitle),
        ),
      );

  static String _plannedWeeks(PhasePlan plan) {
    final w = plan.phases.fold(0, (w, p) => w + p.weeks);
    return '$w ${w == 1 ? 'week' : 'weeks'}';
  }
}

enum _Extend { untilTarget, newWeight, weeks }

/// The weeks an extension can run for.
const extendWeeksChoices = [2, 4, 8];

/// The goal extended or completed: until the target (when [ended] without
/// reaching it), to a new weight, or for more weeks, after a diet break
/// when chosen. True once saved.
Future<bool> showExtendSheet(
  BuildContext context,
  PhasePlan plan,
  double nowKg,
  BodyWeightUnit unit, {
  required bool ended,
  GoalActions? actions,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ExtendSheet(
        plan: plan,
        nowKg: nowKg,
        unit: unit,
        ended: ended,
        actions: actions ?? GoalActions(),
      ),
    ) ??
    false;

class ExtendSheet extends StatefulWidget {
  final PhasePlan plan;
  final double nowKg;
  final BodyWeightUnit unit;
  final bool ended;
  final GoalActions actions;
  final DateTime? today;

  const ExtendSheet({
    super.key,
    required this.plan,
    required this.nowKg,
    required this.unit,
    required this.ended,
    required this.actions,
    this.today,
  });

  @override
  State<ExtendSheet> createState() => _ExtendSheetState();
}

class _ExtendSheetState extends State<ExtendSheet> {
  late var _how = _canReachTarget ? _Extend.untilTarget : _Extend.weeks;
  double? _newKg;
  var _weeks = extendWeeksChoices[1];
  var _break = false;
  var _busy = false;

  bool get _canReachTarget =>
      widget.ended &&
      widget.plan.targetKg != null &&
      widget.plan.kind != PhaseKind.maintain;

  bool get _cut => widget.plan.kind == PhaseKind.cut;

  DateTime get _today => widget.today ?? DateTime.now();

  /// The plan extended as chosen; null until a new weight is set.
  PhasePlan? get _extended {
    final plan = widget.plan;
    return switch (_how) {
      _Extend.untilTarget => extendedPlan(
        plan,
        today: _today,
        nowKg: widget.nowKg,
        breakFirst: _break,
      ),
      _Extend.newWeight =>
        _newKg == null
            ? null
            : extendedPlan(
                plan,
                today: _today,
                nowKg: widget.nowKg,
                untilKg: _newKg,
                breakFirst: _break,
              ),
      _Extend.weeks => extendedPlan(
        plan,
        today: _today,
        nowKg: widget.nowKg,
        weeks: _weeks,
        breakFirst: _break,
      ),
    };
  }

  /// Why the new weight cannot be planned; null when it can.
  String? get _problem {
    final kg = _newKg;
    if (_how != _Extend.newWeight || kg == null) return null;
    if (widget.plan.kind == PhaseKind.cut && kg > widget.nowKg - 0.1) {
      return 'A cut needs a weight below your weight now.';
    }
    if (widget.plan.kind == PhaseKind.bulk && kg < widget.nowKg + 0.1) {
      return 'A bulk needs a weight above your weight now.';
    }
    return null;
  }

  Future<void> _pickWeight() async {
    final result = await showDialog<TargetWeightDialogResult>(
      context: context,
      builder: (_) => SetTargetWeightDialog(
        initialKg: _newKg ?? widget.plan.targetKg ?? widget.nowKg,
        hasExistingTarget: false,
        unit: widget.unit,
      ),
    );
    final kg = result?.value;
    if (kg == null || !mounted) return;
    setState(() {
      _newKg = kg;
      _how = _Extend.newWeight;
    });
  }

  Future<void> _save(Future<bool> Function() action) async {
    setState(() => _busy = true);
    final done = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (done) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not saved: the profile changed.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final unit = widget.unit;
    final theme = Theme.of(context);
    final target = plan.targetKg;
    final extended = _problem == null ? _extended : null;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final format = intl.DateFormat.yMMMd(locale);
    final hold = plan.kind == PhaseKind.maintain;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Dimens.spacing16,
          0,
          Dimens.spacing16,
          Dimens.spacing16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.ended ? 'The plan has ended' : 'Extend the goal',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              widget.ended && target != null && !hold
                  ? 'You are at ${weightText(widget.nowKg, unit)}, '
                        '${weightText((target - widget.nowKg).abs(), unit)} '
                        'from ${weightText(target, unit)}.'
                  : 'You are at ${weightText(widget.nowKg, unit)}.',
            ),
            const SizedBox(height: Dimens.spacing12),
            RadioGroup<_Extend>(
              groupValue: _how,
              onChanged: (v) {
                if (v == _Extend.newWeight && _newKg == null) {
                  _pickWeight();
                  return;
                }
                setState(() => _how = v ?? _how);
              },
              child: Column(
                children: [
                  if (_canReachTarget)
                    Semantics(
                      identifier: 'goal-extend-target',
                      child: RadioListTile<_Extend>(
                        value: _Extend.untilTarget,
                        title: Text('Until ${weightText(target!, unit)}'),
                        subtitle: Text(
                          'At the same pace, about '
                          '${DietPhase.weeksTo(widget.nowKg, target, _pace)} '
                          'more weeks',
                        ),
                      ),
                    ),
                  if (!hold)
                    Semantics(
                      identifier: 'goal-extend-weight',
                      child: RadioListTile<_Extend>(
                        value: _Extend.newWeight,
                        title: Text(
                          _newKg == null
                              ? 'To a new weight'
                              : 'To ${weightText(_newKg!, unit)}',
                        ),
                        subtitle: Text(
                          _problem ??
                              (_newKg == null
                                  ? 'Choose the weight'
                                  : 'Tap to change'),
                          style: _problem == null
                              ? null
                              : TextStyle(color: theme.colorScheme.error),
                        ),
                        secondary: _newKg == null
                            ? null
                            : IconButton(
                                tooltip: 'Change the weight',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: _pickWeight,
                              ),
                      ),
                    ),
                  Semantics(
                    identifier: 'goal-extend-weeks',
                    child: RadioListTile<_Extend>(
                      value: _Extend.weeks,
                      title: const Text('For more weeks'),
                      subtitle: hold
                          ? const Text('Maintenance, for')
                          : const Text('At the same pace, for'),
                    ),
                  ),
                ],
              ),
            ),
            if (_how == _Extend.weeks)
              Padding(
                padding: const EdgeInsets.only(left: 56),
                child: Wrap(
                  spacing: Dimens.spacing8,
                  children: [
                    for (final w in extendWeeksChoices)
                      Semantics(
                        identifier: 'goal-extend-weeks-$w',
                        child: ChoiceChip(
                          label: Text('$w weeks'),
                          selected: _weeks == w,
                          onSelected: (_) => setState(() => _weeks = w),
                        ),
                      ),
                  ],
                ),
              ),
            if (_cut)
              Semantics(
                identifier: 'goal-extend-break',
                child: SwitchListTile(
                  value: _break,
                  onChanged: (v) => setState(() => _break = v),
                  title: Text('A diet break first'),
                  subtitle: Text(
                    '$breakWeeks weeks at maintenance before cutting on.',
                  ),
                ),
              ),
            if (extended != null) ...[
              const SizedBox(height: Dimens.spacing8),
              PhaseBar(extended),
              const SizedBox(height: 6),
              Text(
                'Ends about ${format.format(extended.end)}.',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: Dimens.spacing16),
            Row(
              children: [
                if (widget.ended) ...[
                  Expanded(
                    child: Semantics(
                      identifier: 'goal-extend-complete',
                      child: OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _save(
                                () =>
                                    widget.actions.complete(plan, widget.nowKg),
                              ),
                        child: Text(
                          'Complete at ${weightText(widget.nowKg, unit)}',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: Dimens.spacing8),
                ],
                Expanded(
                  child: Semantics(
                    identifier: 'goal-extend-save',
                    child: FilledButton(
                      onPressed: _busy || extended == null
                          ? null
                          : () => _save(() => widget.actions.extend(extended)),
                      child: const Text('Extend'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double get _pace => widget.plan.phases
      .lastWhere(
        (p) => p.kind == widget.plan.kind,
        orElse: () => widget.plan.phases.last,
      )
      .kgPerWeek;
}
