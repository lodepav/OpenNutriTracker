import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/calorie_goal_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/set_target_weight_dialog.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart'
    as adaptive;
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_ui.dart';
import 'package:opennutritracker/fork/adaptive/expenditure_settings_ui.dart';
import 'package:opennutritracker/fork/adaptive/macro_program.dart';
import 'package:opennutritracker/fork/adaptive/macro_program_ui.dart';
import 'package:opennutritracker/fork/adaptive/onboarding_macros.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/goal/goal_actions.dart';
import 'package:opennutritracker/fork/goal/goal_planner.dart';
import 'package:opennutritracker/fork/goal/phase_colors.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';
import 'package:opennutritracker/fork/units/weight_text.dart';

/// What the planner plans from: the body, the weight now and what it burns.
class PlannerSetup {
  /// The trend weight, or the weight typed in with no weigh-in yet.
  final double nowKg;
  final BodyWeightUnit unit;
  final double expenditureKcal;
  final double bodyFatPercent;

  /// What the Formula target starts from: upstream's estimate from the
  /// profile alone, with the manual adjustment, before the pace and
  /// logged activities. Not [expenditureKcal], which only an Adaptive
  /// target is built on.
  final double formulaKcal;

  /// The goal running now, to edit or replace.
  final PhasePlan? running;

  /// The goals planned after [running], in order.
  final List<PhasePlan> upcoming;

  /// The profile's target weight, a new goal's starting point.
  final double? targetKg;

  /// In onboarding: the macros wait in [OnboardingMacros.pending] for the
  /// profile.
  final bool onboarding;

  const PlannerSetup({
    required this.nowKg,
    required this.unit,
    required this.expenditureKcal,
    required this.bodyFatPercent,
    double? formulaKcal,
    this.running,
    this.upcoming = const [],
    this.targetKg,
    this.onboarding = false,
  }) : formulaKcal = formulaKcal ?? expenditureKcal;

  /// For [user], with no weigh-ins: onboarding's, or a profile's before its
  /// first.
  factory PlannerSetup.ofUser(
    UserEntity user,
    BodyWeightUnit unit, {
    bool onboarding = false,
    PhasePlan? running,
    List<PhasePlan> upcoming = const [],
    double kcalAdjustment = 0,
  }) => PlannerSetup(
    nowKg: user.weightKG,
    unit: unit,
    expenditureKcal: CalorieGoalCalc.getTdee(user),
    formulaKcal: CalorieGoalCalc.getTdee(user) + kcalAdjustment,
    bodyFatPercent: adaptive.bodyFatPercent(user),
    targetKg: user.targetWeightKg,
    running: running,
    upcoming: upcoming,
    onboarding: onboarding,
  );

  /// The active profile's.
  static Future<PlannerSetup> load() async {
    final user = await locator<GetUserUsecase>().getUserData();
    final config = await locator<GetConfigUsecase>().getConfig();
    final unit = config.bodyWeightUnit;
    final adjustment = config.userKcalAdjustment ?? 0;
    final running = await PhaseStore().plan();
    final upcoming = await PhaseStore().upcoming();
    final inputs = await adaptive.AdaptiveService.fromLocator().goalPlan();
    if (inputs == null) {
      return PlannerSetup.ofUser(
        user,
        unit,
        running: running,
        upcoming: upcoming,
        kcalAdjustment: adjustment,
      );
    }
    return PlannerSetup(
      nowKg: inputs.nowKg,
      unit: unit,
      expenditureKcal: inputs.expenditureKcal,
      formulaKcal: CalorieGoalCalc.getTdee(user) + adjustment,
      bodyFatPercent: inputs.bodyFatPercent,
      targetKg: inputs.targetWeightKg,
      running: running,
      upcoming: upcoming,
    );
  }
}

/// Opens the planner on the active profile's goal: [fresh] plans a new one,
/// after the goals planned or replacing the running one (kept as
/// completed when it starts); [upcomingIndex] edits that upcoming goal;
/// else the running goal is edited. True once a plan was saved.
Future<bool> openGoalPlanner(
  BuildContext context, {
  bool fresh = false,
  int? upcomingIndex,
}) async {
  final setup = await PlannerSetup.load();
  if (!context.mounted) return false;
  final running = setup.running;
  final today = DateTime.now();
  // Made now, so a profile switch while planning drops the save.
  final actions = GoalActions();
  if (upcomingIndex != null) {
    if (upcomingIndex >= setup.upcoming.length) return false;
    final queued = setup.upcoming[upcomingIndex];
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GoalPlannerScreen(
          setup: setup,
          draft: GoalDraft.of(queued, queued.startKg ?? setup.nowKg),
          queuedAt: upcomingIndex,
          onStart: (_) async => false,
          onQueue: (at, plan) => actions.replaceUpcoming(at, plan),
        ),
      ),
    );
    return saved ?? false;
  }
  final editing = fresh ? null : running;
  final begun = editing != null && editing.indexOn(today) >= 0;
  final draft = editing != null
      // Begun, what is still to go is planned from the weight now.
      ? GoalDraft.of(
          editing,
          setup.nowKg,
        ).copyWith(startKg: begun ? setup.nowKg : null)
      : GoalDraft.fresh(setup.nowKg, today, targetKg: setup.targetKg);
  final started = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => GoalPlannerScreen(
        setup: setup,
        draft: draft,
        editing: editing,
        onStart: (plan) => actions.start(
          plan,
          // Another kind of goal, once one is begun, is a new goal; the
          // one before is kept.
          replacing: fresh || (begun && plan.kind != running?.kind)
              ? running
              : null,
          nowKg: setup.nowKg,
        ),
        onQueue: fresh
            ? (at, plan) => actions.add(plan, at: at, nowKg: setup.nowKg)
            : null,
      ),
    ),
  );
  return started ?? false;
}

enum _Step {
  goal('Goal'),
  pace('Pace'),
  burn('What you burn'),
  target('Calorie target'),
  macros('Macros'),
  carried('Carried over'),
  plan('Your plan');

  final String label;
  const _Step(this.label);
}

/// The goal planner (design A, round 4): the goal, its pace, the
/// expenditure, how the target is set, the macros and the plan, one full
/// screen each, from onboarding and from the goal page. The expenditure,
/// target and macro settings save as they change, as Settings' do, and
/// go back as they were when the planner is left without a plan.
class GoalPlannerScreen extends StatefulWidget {
  final PlannerSetup setup;
  final GoalDraft draft;

  /// Saves the plan; false when it was not (a profile switch).
  final Future<bool> Function(PhasePlan plan) onStart;
  final AdaptiveStore? store;

  /// The running goal being edited: once begun, its phases so far stay
  /// and the draft plans what is still to go (`editedPlan`).
  final PhasePlan? editing;

  /// Today; the clock's by default.
  final DateTime? today;

  /// Puts the plan among the upcoming goals at its place there; with a
  /// goal running, the start offers a place after each goal planned.
  final Future<bool> Function(int at, PhasePlan plan)? onQueue;

  /// The upcoming goal at this place being edited: it keeps its place.
  final int? queuedAt;

  const GoalPlannerScreen({
    super.key,
    required this.setup,
    required this.draft,
    required this.onStart,
    this.store,
    this.editing,
    this.today,
    this.onQueue,
    this.queuedAt,
  });

  @override
  State<GoalPlannerScreen> createState() => _GoalPlannerScreenState();
}

class _GoalPlannerScreenState extends State<GoalPlannerScreen> {
  late final _store = widget.store ?? AdaptiveStore();
  late final _before = AdaptiveStore.settings.value;
  late final _macrosBefore = OnboardingMacros.pending.value;
  late GoalDraft _draft = widget.draft;

  DateTime get _today => widget.today ?? DateTime.now();

  /// The place among the upcoming goals the plan goes to; null when it
  /// starts on a day of its own, replacing the goal running.
  late int? _place =
      widget.queuedAt ??
      (widget.onQueue != null &&
              widget.editing == null &&
              _setup.running != null
          ? _setup.upcoming.length
          : null);

  bool get _queued => _place != null;

  /// The goal before [place]: the one running, or an upcoming one.
  PhasePlan _goalBefore(int place) =>
      place == 0 ? _setup.running! : _setup.upcoming[place - 1];

  /// The steps set up anew in a queued goal, the rest carried over:
  /// another kind of goal than the one before has its own pace.
  final _opened = <_Step>{};

  List<_Step> get _steps {
    final place = _place;
    if (place == null) {
      return const [
        _Step.goal,
        _Step.pace,
        _Step.burn,
        _Step.target,
        _Step.macros,
        _Step.plan,
      ];
    }
    final paceAgain = _draft.kind != _goalBefore(place).kind;
    return [
      _Step.goal,
      for (final step in [_Step.pace, _Step.burn, _Step.target, _Step.macros])
        if (_opened.contains(step) || (step == _Step.pace && paceAgain)) step,
      _Step.carried,
      _Step.plan,
    ];
  }

  _Step get _at => _steps[_step];

  /// Shows [step], opening it in a queued goal.
  void _goTo(_Step step) => setState(() {
    _opened.add(step);
    _step = _steps.indexOf(step);
  });

  /// [_draft] at [place]: from the day the goal before ends, at the
  /// weight it ends at, with its pace when it is the same kind.
  void _moveTo(int place) {
    final before = _goalBefore(place);
    final kg = endKgOf(before) ?? _setup.nowKg;
    _place = place;
    _draft = _draft.copyWith(start: before.end, startKg: kg);
    if (_draft.kind == before.kind) {
      final same = GoalDraft.of(before, kg);
      _draft = _draft.copyWith(
        paceKg: same.paceKg,
        breaks: same.breaks,
        maintainWeeks: same.maintainWeeks,
      );
    }
    _customPace = !_draft.paces.any((p) => (p - _draft.paceKg).abs() < 0.001);
  }

  @override
  void initState() {
    super.initState();
    final place = _place;
    if (place != null && widget.queuedAt == null) _moveTo(place);
  }

  /// The goal edited, once begun: its start stays.
  bool get _begun =>
      widget.editing != null && widget.editing!.indexOn(_today) >= 0;

  /// The plan [draft] makes: a new goal's own, or the goal edited with its
  /// past kept. Another kind of goal starts anew.
  PhasePlan _planOf(GoalDraft draft) {
    final editing = widget.editing;
    if (editing == null || draft.kind != editing.kind) {
      return draft.copyWith(start: _begun ? _date0(_today) : null).toPlan();
    }
    return editedPlan(editing, draft, today: _today, nowKg: _setup.nowKg);
  }

  static DateTime _date0(DateTime t) => DateTime(t.year, t.month, t.day);

  /// A pace of the user's own on the slider, not one of the three.
  late bool _customPace = !_draft.paces.any(
    (p) => (p - _draft.paceKg).abs() < 0.001,
  );
  int _step = 0;
  bool _macrosValid = true;
  bool _saving = false;

  PlannerSetup get _setup => widget.setup;
  BodyWeightUnit get _unit => _setup.unit;
  bool get _perLb => _unit != BodyWeightUnit.kg;

  String _kg(double kg) => weightText(kg, _unit);

  String _rate(double kg) => _unit == BodyWeightUnit.kg
      ? '${_trim(kg)} kg a week'
      : '${_trim(kg * MacroProgram.lbPerKg)} lb a week';

  static String _trim(double v) {
    final text = v.toStringAsFixed(2);
    return text.endsWith('0') ? v.toStringAsFixed(1) : text;
  }

  String _date(DateTime d) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return (d.year == DateTime.now().year
            ? intl.DateFormat.MMMd(locale)
            : intl.DateFormat.yMMMd(locale))
        .format(d);
  }

  /// The day before [d], a phase's last.
  static DateTime _dayBefore(DateTime d) =>
      DateTime(d.year, d.month, d.day - 1);

  static String _weeks(int w) => '$w ${w == 1 ? 'week' : 'weeks'}';

  /// About what a day of a phase at [kgPerWeek] gets.
  /// The Formula target is on: neither Adaptive nor Fixed.
  static bool get _formula {
    final s = AdaptiveStore.settings.value;
    return !s.adaptiveTarget && !s.fixedTarget;
  }

  /// What the target is built on: the profile's formula for a Formula
  /// target, else the expenditure estimate.
  double get _baseKcal =>
      _formula ? _setup.formulaKcal : _setup.expenditureKcal;

  double _kcalAt(double kgPerWeek) =>
      _baseKcal + kgPerWeek * AdaptiveSettings.commonKcalPerKg / 7;

  double get _mainKcal {
    final s = AdaptiveStore.settings.value;
    return s.fixedTarget ? s.fixedTargetKcal : _kcalAt(_draft.signedPace);
  }

  Future<void> _leave() async {
    final keep = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave without a plan?'),
        content: const Text(
          'Your goal stays as it is, and the settings changed here go back.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (keep != true || !mounted) return;
    await _restore();
    if (mounted) Navigator.of(context).pop(false);
  }

  Future<void> _restore() async {
    OnboardingMacros.pending.value = _macrosBefore;
    if (identical(AdaptiveStore.settings.value, _before)) return;
    await _store.save(_before);
    await refreshGoals();
  }

  Future<void> _start() async {
    setState(() => _saving = true);
    final place = _place;
    final saved = place == null
        ? await widget.onStart(_planOf(_draft))
        : await widget.onQueue!(place, _draft.toPlan());
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not saved: the profile changed.')),
      );
    }
  }

  bool get _canGoOn => switch (_at) {
    _Step.goal => _draft.problem == null,
    _Step.macros => _macrosValid,
    _ => true,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = _steps;
    final last = _step == steps.length - 1;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_step > 0) {
          setState(() => _step--);
        } else {
          _leave();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: Semantics(
            identifier: 'goal-planner-close',
            child: IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close_rounded),
              onPressed: _leave,
            ),
          ),
          title: Text(
            widget.queuedAt != null
                ? 'Edit an upcoming goal'
                : _queued
                ? 'Plan the next goal'
                : 'Plan your goal',
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    for (var i = 0; i < steps.length; i++) ...[
                      if (i > 0) const SizedBox(width: 4),
                      Expanded(
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: i <= _step
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        // The mode toggled on the target step changes its figures.
        body: ValueListenableBuilder(
          valueListenable: AdaptiveStore.settings,
          builder: (context, _, _) => ListView(
            key: ValueKey('goal-planner-step-${_at.name}'),
            padding: const EdgeInsets.only(bottom: Dimens.spacing24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  'Step ${_step + 1} of ${steps.length} · ${_at.label}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              ...switch (_at) {
                _Step.goal => _goalStep(context),
                _Step.pace => _paceStep(context),
                _Step.burn => _burnStep(context),
                _Step.target => _targetStep(context),
                _Step.macros => _macrosStep(context),
                _Step.carried => _carriedStep(context),
                _Step.plan => _planStep(context),
              },
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                if (_step > 0) ...[
                  Semantics(
                    identifier: 'goal-planner-back',
                    child: OutlinedButton(
                      onPressed: () => setState(() => _step--),
                      child: const Text('Back'),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Semantics(
                    identifier: last
                        ? 'goal-planner-start'
                        : 'goal-planner-next',
                    child: FilledButton(
                      onPressed: !_canGoOn || _saving
                          ? null
                          : last
                          ? _start
                          : () => setState(() => _step++),
                      child: Text(
                        _at == _Step.carried
                            ? 'Keep all and go on'
                            : !last
                            ? 'Next'
                            : widget.queuedAt != null
                            ? 'Save goal'
                            : _queued
                            ? 'Add to the plan'
                            : _setup.onboarding
                            ? 'Use this plan'
                            : 'Start plan',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _question(BuildContext context, String title, String? text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.headlineSmall),
          ),
          if (text != null) ...[
            const SizedBox(height: 4),
            Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _heading(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
    child: Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    ),
  );

  // ---------------------------------------------------------------- goal

  List<Widget> _goalStep(BuildContext context) {
    final target = _draft.targetKg;
    final problem = _draft.problem;
    final monday = _nextMonday(DateTime.now());
    final today = DateTime.now();
    return [
      _question(
        context,
        'What do you want to do?',
        _queued
            ? 'It starts from ${_kg(_draft.startKg)}, where '
                  '${_goalName(_goalBefore(_place!))} ends. Diet breaks '
                  'come in the next step.'
            : 'Your ${_setup.running == null ? 'weight' : 'trend weight'} '
                  'is ${_kg(_setup.nowKg)}. Diet breaks come in the next '
                  'step.',
      ),
      for (final (kind, title, text) in [
        (PhaseKind.cut, 'Lose fat', 'A cut: eat under what you burn'),
        (PhaseKind.maintain, 'Maintain', 'Hold your weight for a few weeks'),
        (PhaseKind.bulk, 'Gain', 'A bulk: eat over what you burn'),
      ])
        _OptionCard(
          identifier: 'goal-kind-${kind.name}',
          selected: _draft.kind == kind,
          color: phaseColor(context, kind),
          title: title,
          subtitle: text,
          onTap: () => setState(() {
            _customPace = false;
            _draft = _draft.copyWith(
              kind: kind,
              paceKg: switch (kind) {
                PhaseKind.cut => cutPacesKg[1],
                PhaseKind.bulk => bulkPacesKg[1],
                PhaseKind.maintain => 0,
              },
              breaks: kind == PhaseKind.cut && _draft.breaks,
            );
            final place = _place;
            if (place != null) _moveTo(place);
          }),
        ),
      if (_draft.kind != PhaseKind.maintain) ...[
        _heading(context, 'Target weight'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Semantics(
            identifier: 'goal-target-weight',
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                alignment: Alignment.centerLeft,
              ),
              onPressed: _pickTarget,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      target == null ? 'Set a target weight' : _kg(target),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (target != null && problem == null)
                    Text(
                      '${weightChangeText(target - _draft.startKg, _unit)} '
                      'to go',
                    ),
                  const SizedBox(width: 8),
                  const Icon(Icons.edit_rounded),
                ],
              ),
            ),
          ),
        ),
        if (problem != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(
              problem,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
      _heading(context, 'Start'),
      if (widget.queuedAt != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Starts ${_date(_draft.start)}, after '
            '${_goalName(_goalBefore(widget.queuedAt!))}. To change when, '
            'move it on the calendar.',
          ),
        )
      else if (_begun && _draft.kind == widget.editing!.kind)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Started ${_date(widget.editing!.start)}. The weeks so far stay '
            'as they were; a change applies from the end of this week.',
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            children: [
              if (widget.onQueue != null && _setup.running != null)
                for (var place = _setup.upcoming.length; place >= 0; place--)
                  Semantics(
                    identifier: 'goal-start-after-$place',
                    child: ChoiceChip(
                      label: Text(
                        'After ${_goalName(_goalBefore(place))} · '
                        '${_date(_goalBefore(place).end)}',
                      ),
                      selected: _place == place,
                      onSelected: (_) => setState(() => _moveTo(place)),
                    ),
                  ),
              for (final (id, label, day) in [
                (
                  'today',
                  _setup.running != null && widget.onQueue != null
                      ? 'Today, replacing ${_goalName(_setup.running!)}'
                      : 'Today, ${_date(today)}',
                  today,
                ),
                if (!_sameDay(monday, today))
                  ('monday', 'Monday, ${_date(monday)}', monday),
                if (_setup.running != null &&
                    !_sameDay(_setup.running!.start, today) &&
                    !_sameDay(_setup.running!.start, monday))
                  (
                    'kept',
                    'As planned, ${_date(_setup.running!.start)}',
                    _setup.running!.start,
                  ),
              ])
                Semantics(
                  identifier: 'goal-start-$id',
                  child: ChoiceChip(
                    label: Text(label),
                    selected: !_queued && _sameDay(_draft.start, day),
                    onSelected: (_) => setState(() {
                      _place = null;
                      _opened.clear();
                      _draft = _draft.copyWith(
                        start: DateTime(day.year, day.month, day.day),
                        startKg: _setup.nowKg,
                      );
                    }),
                  ),
                ),
            ],
          ),
        ),
    ];
  }

  /// [plan] in a sentence: "the cut", "maintaining", "the bulk".
  static String _goalName(PhasePlan plan) => switch (plan.kind) {
    PhaseKind.cut => 'the cut',
    PhaseKind.maintain => 'maintaining',
    PhaseKind.bulk => 'the bulk',
  };

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static DateTime _nextMonday(DateTime t) {
    final ahead = (DateTime.monday - t.weekday) % 7;
    return DateTime(t.year, t.month, t.day + (ahead == 0 ? 7 : ahead));
  }

  Future<void> _pickTarget() async {
    final result = await showDialog<TargetWeightDialogResult>(
      context: context,
      builder: (_) => SetTargetWeightDialog(
        initialKg: _draft.targetKg ?? _draft.startKg,
        hasExistingTarget: false,
        unit: _unit,
      ),
    );
    final kg = result?.value;
    if (kg == null || !mounted) return;
    setState(() => _draft = _draft.copyWith(targetKg: () => kg));
  }

  // ---------------------------------------------------------------- pace

  /// The custom pace's toggle and, when on, its slider.
  List<Widget> _customPaceRows(BuildContext context, bool cut) {
    final range = cut ? cutCustomPaceKg : bulkCustomPaceKg;
    final pace = _draft.paceKg.clamp(range.min, range.max);
    final kcal = pace * AdaptiveSettings.commonKcalPerKg / 7;
    final percent = pace / _draft.startKg * 100;
    final theme = Theme.of(context);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Semantics(
          identifier: 'goal-pace-custom',
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Custom pace'),
            subtitle: const Text('Set your own on a slider'),
            value: _customPace,
            onChanged: (on) => setState(() {
              _customPace = on;
              if (!on && !_draft.paces.contains(_draft.paceKg)) {
                _draft = _draft.copyWith(paceKg: _draft.paces[1]);
              }
            }),
          ),
        ),
      ),
      if (_customPace)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_rate(pace), style: theme.textTheme.titleMedium),
              Text(
                'about ${energyText(context, kcal)} '
                '${cut ? 'under' : 'over'} · '
                '${percent.toStringAsFixed(1)}% of your weight a week',
                style: theme.textTheme.bodySmall,
              ),
              Semantics(
                identifier: 'goal-pace-slider',
                child: Slider(
                  value: pace,
                  min: range.min,
                  max: range.max,
                  divisions: ((range.max - range.min) / customPaceStepKg)
                      .round(),
                  label: _rate(pace),
                  semanticFormatterCallback: _rate,
                  onChanged: (v) => setState(
                    () => _draft = _draft.copyWith(
                      paceKg: (v / customPaceStepKg).round() * customPaceStepKg,
                    ),
                  ),
                ),
              ),
              if (percent > (cut ? 1 : 0.5))
                Text(
                  cut
                      ? 'Over 1% a week: more hunger and more muscle lost.'
                      : 'Over 0.5% a week: more of the gain is fat.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _paceStep(BuildContext context) {
    final plan = _planOf(_draft);
    final end = _dayBefore(plan.end);
    if (_draft.kind == PhaseKind.maintain) {
      return [
        _question(
          context,
          'For how long?',
          'Maintenance at what you burn, about '
              '${energyText(context, _baseKcal)} a day. When '
              'it ends, mark it completed or extend it.',
        ),
        for (final w in maintainWeeksChoices)
          _OptionCard(
            identifier: 'goal-maintain-$w',
            selected: _draft.maintainWeeks == w,
            title: _weeks(w),
            subtitle:
                'Until ${_date(DateTime(_draft.start.year, _draft.start.month, _draft.start.day + w * 7 - 1))}',
            onTap: () =>
                setState(() => _draft = _draft.copyWith(maintainWeeks: w)),
          ),
      ];
    }
    final cut = _draft.kind == PhaseKind.cut;
    return [
      _question(
        context,
        'How fast?',
        cut
            ? 'Faster costs more hunger and some muscle. 0.5 to 1% of your '
                  'weight a week is the usual range.'
            : 'Slower keeps more of the gain lean. 0.25 to 0.5% of your '
                  'weight a week is the usual range.',
      ),
      for (final (i, pace) in _draft.paces.indexed)
        Builder(
          builder: (context) {
            final at = _planOf(_draft.copyWith(paceKg: pace));
            final kcal = (pace * AdaptiveSettings.commonKcalPerKg / 7).round();
            return _OptionCard(
              identifier: 'goal-pace-$i',
              selected: !_customPace && _draft.paceKg == pace,
              title: '${['Gentle', 'Steady', 'Fast'][i]} · ${_rate(pace)}',
              subtitle:
                  'about ${energyText(context, kcal.toDouble())} '
                  '${cut ? 'under' : 'over'} · until '
                  '${_date(_dayBefore(at.end))} · '
                  '${(pace / _draft.startKg * 100).toStringAsFixed(1)}% a week',
              onTap: () => setState(() {
                _customPace = false;
                _draft = _draft.copyWith(paceKg: pace);
              }),
            );
          },
        ),
      ..._customPaceRows(context, cut),
      if (cut)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Semantics(
            identifier: 'goal-diet-breaks',
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Diet breaks'),
              subtitle: const Text(
                '$breakWeeks weeks at maintenance after every '
                '$breakEveryWeeks weeks of cutting',
              ),
              value: _draft.breaks,
              onChanged: (v) =>
                  setState(() => _draft = _draft.copyWith(breaks: v)),
            ),
          ),
        ),
      _Panel(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_date(plan.start)} → about ${_date(end)}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text(_weeks(plan.phases.fold(0, (w, p) => w + p.weeks))),
            ],
          ),
          const SizedBox(height: 8),
          PhaseBar(plan),
          const SizedBox(height: 8),
          Text(
            'After the goal: maintenance until you plan the next one.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ];
  }

  // ---------------------------------------------------------------- burn

  List<Widget> _burnStep(BuildContext context) => [
    _question(
      context,
      'Your expenditure',
      'What you burn a day. An Adaptive target is built on it, so a good '
          'estimate matters more than the pace.',
    ),
    _Panel(
      children: [
        Text(
          _setup.onboarding ? 'Starting estimate' : 'Estimate now',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        Text(
          '${energyText(context, _setup.expenditureKcal)} a day',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        Text(
          _setup.onboarding
              ? 'From your age, height, weight and activity. Your '
                    'weigh-ins and what you log correct it from the second '
                    'week.'
              : 'From your weigh-ins and what you log, with the settings '
                    'below.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_formula)
          Text(
            'Your target is on Formula, which goes by your profile, '
            '${energyText(context, _setup.formulaKcal)}; this estimate sets '
            'it only on Adaptive.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    ),
    ExpenditureGroups.estimate(store: _store),
  ];

  // -------------------------------------------------------------- target

  List<Widget> _targetStep(BuildContext context) {
    final pace = _draft.signedPace;
    final shift = (pace * AdaptiveSettings.commonKcalPerKg / 7).round();
    final breaks = _planOf(_draft).phases.length > 1;
    final settings = AdaptiveStore.settings.value;
    final base = energyText(context, _baseKcal);
    final from = _formula
        ? 'The formula\'s estimate from your age, height, weight and '
              'activity, $base,'
        : 'What you burn, $base,';
    return [
      _question(
        context,
        'How the target is set',
        settings.fixedTarget
            ? 'A fixed target: '
                  '${energyText(context, settings.fixedTargetKcal)} a day, '
                  'whatever the pace.'
            : pace == 0
            ? '${_formula ? 'The formula\'s estimate from your age, height, weight and activity' : 'At maintenance the target is what you burn'}, '
                  'about $base.'
            : '$from ${pace < 0 ? 'less' : 'plus'} the pace\'s '
                  '${energyText(context, shift.abs().toDouble())} gives about '
                  '${energyText(context, _kcalAt(pace))} a day'
                  '${breaks ? '; on diet breaks, $base.' : '.'}',
      ),
      if (_formula && !_setup.onboarding)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Semantics(
            identifier: 'goal-target-adaptive-hint',
            child: Text(
              'With a few weeks of weigh-ins and logging, Adaptive follows '
              'what you actually burn, '
              '${energyText(context, _setup.expenditureKcal)} by the '
              'estimate now, rather than the formula\'s guess.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      if (_formula && _setup.onboarding)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            'After a few weeks of weigh-ins and logging, Adaptive follows '
            'what you actually burn: switch in Settings, or here when you '
            'edit the plan.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TargetModeFields(
          _store,
          perLb: _perLb,
          showMacros: false,
          showExpenditure: false,
        ),
      ),
      const Divider(),
      ExpenditureGroups.checkIn(store: _store),
    ];
  }

  // -------------------------------------------------------------- macros

  List<Widget> _macrosStep(BuildContext context) {
    final settings = AdaptiveStore.settings.value;
    final program = _setup.onboarding
        ? OnboardingMacros.pending.value
        : settings.macroProgram;
    final kcal = _mainKcal;
    final grams = program?.macrosFor(
      kcal: kcal,
      weightKg: _setup.nowKg,
      bodyFatPercent: _setup.bodyFatPercent,
    );
    return [
      _question(
        context,
        'Protein, fat and carbs',
        'Set protein and fat by your weight, and carbs take the rest. Off, '
            'the percentages of your macro split stand.',
      ),
      if (settings.fixedTarget && settings.fixedMacros != null)
        _Panel(
          children: [
            const Text(
              'Your fixed target sets its own grams. Change them in the '
              'previous step.',
            ),
          ],
        )
      else ...[
        if (grams != null)
          _Panel(
            children: [
              Text(
                'At about ${energyText(context, kcal)}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 4),
              Text(
                inMacroOrder(
                  protein: 'Protein ${grams.proteinG.round()} g',
                  carbs: 'Carbs ${grams.carbsG.round()} g',
                  fat: 'Fat ${grams.fatG.round()} g',
                ).join(' · '),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: MacroProgramForm(
            program,
            perLb: _perLb,
            onChanged: (program, valid) async {
              setState(() => _macrosValid = valid);
              if (!valid) return;
              if (_setup.onboarding) {
                OnboardingMacros.pending.value = program;
              } else {
                await _store.save(
                  AdaptiveStore.settings.value.copyWith(
                    macroProgram: () => program,
                  ),
                );
                await refreshGoals();
              }
              if (mounted) setState(() {});
            },
          ),
        ),
      ],
    ];
  }

  // ------------------------------------------------------------- carried

  /// A queued goal's steps set up already (design B): kept, or one opened.
  List<Widget> _carriedStep(BuildContext context) {
    final settings = AdaptiveStore.settings.value;
    final steps = _steps;
    final before = _goalName(_goalBefore(_place!));
    return [
      _question(
        context,
        'The rest is set up',
        'From $before. Keep them, or change one: a change applies to '
            'every goal, the one now included.',
      ),
      _Panel(
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          if (!steps.contains(_Step.pace))
            _ChangeRow(
              identifier: 'goal-carried-pace',
              title: _draft.kind == PhaseKind.maintain ? 'How long' : 'Pace',
              subtitle: _draft.kind == PhaseKind.maintain
                  ? _weeks(_draft.maintainWeeks)
                  : '${_rate(_draft.paceKg)}'
                        '${_draft.breaks ? ' · diet breaks' : ''}',
              onChange: () => _goTo(_Step.pace),
            ),
          if (!steps.contains(_Step.burn))
            _ChangeRow(
              identifier: 'goal-carried-burn',
              title: 'Expenditure',
              subtitle:
                  '${energyText(context, _setup.expenditureKcal)} now · '
                  '${expenditureSummary(settings)}',
              onChange: () => _goTo(_Step.burn),
            ),
          if (!steps.contains(_Step.target))
            _ChangeRow(
              identifier: 'goal-carried-target',
              title: 'Calorie target',
              subtitle:
                  '${targetSummary(settings)}'
                  '${settings.fixedTarget ? '' : ' · about ${energyText(context, _mainKcal)}'}',
              onChange: () => _goTo(_Step.target),
            ),
          if (!steps.contains(_Step.macros))
            _ChangeRow(
              identifier: 'goal-carried-macros',
              title: 'Macros',
              subtitle:
                  settings.macroProgram?.summary(perLb: _perLb) ??
                  'Percentages from your macro split',
              onChange: () => _goTo(_Step.macros),
            ),
        ],
      ),
    ];
  }

  // ---------------------------------------------------------------- plan

  List<Widget> _planStep(BuildContext context) {
    final plan = _planOf(_draft);
    final theme = Theme.of(context);
    final settings = AdaptiveStore.settings.value;
    final inCut = plan.kind == PhaseKind.cut;
    final program = _setup.onboarding
        ? OnboardingMacros.pending.value
        : settings.macroProgram;
    final title = switch (plan.kind) {
      PhaseKind.cut => 'Cut to ${_kg(plan.targetKg!)}',
      PhaseKind.bulk => 'Bulk to ${_kg(plan.targetKg!)}',
      PhaseKind.maintain => 'Maintain for ${_weeks(_draft.maintainWeeks)}',
    };
    final weeks = plan.phases.fold(0, (w, p) => w + p.weeks);
    return [
      _question(
        context,
        title,
        '${_date(plan.start)} → about ${_date(_dayBefore(plan.end))} · '
        '${_weeks(weeks)}'
        '${_draft.paceKg > 0 && plan.kind != PhaseKind.maintain ? ' · ${_rate(_draft.paceKg)}' : ''}',
      ),
      _Panel(
        children: [
          PhaseBar(plan),
          const SizedBox(height: 6),
          for (final (i, p) in plan.phases.indexed)
            _Row(
              label:
                  '${_date(plan.startOf(i))} – ${_date(_dayBefore(plan.startOf(i + 1)))}',
              value:
                  '${phaseName(p.kind, inCut: inCut)}'
                  '${settings.fixedTarget ? '' : ' · about ${energyText(context, _kcalAt(p.kgPerWeek))}'}',
            ),
          _Row(label: 'From ${_date(plan.end)}', value: 'Maintenance'),
        ],
      ),
      _Panel(
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          _ChangeRow(
            identifier: 'goal-plan-change-burn',
            title: 'Expenditure',
            subtitle:
                '${energyText(context, _setup.expenditureKcal)} · '
                '${expenditureSummary(settings)}',
            onChange: () => _goTo(_Step.burn),
          ),
          _ChangeRow(
            identifier: 'goal-plan-change-target',
            title: 'Calorie target',
            subtitle: targetSummary(settings),
            onChange: () => _goTo(_Step.target),
          ),
          _ChangeRow(
            identifier: 'goal-plan-change-macros',
            title: 'Macros',
            subtitle: settings.fixedTarget && settings.fixedMacros != null
                ? 'The fixed target\'s grams'
                : program?.summary(perLb: _perLb) ??
                      'Percentages from your macro split',
            onChange: () => _goTo(_Step.macros),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Text(
          plan.kind == PhaseKind.maintain
              ? 'When it ends you choose: mark it completed, or extend it. '
                    'Each day shows on the goal\'s calendar in its colour.'
              : 'When you reach ${_kg(plan.targetKg!)}, or its last day '
                    'comes, you choose: mark the goal completed, or extend '
                    'it. Each day shows on the goal\'s calendar in its '
                    'colour.',
          style: theme.textTheme.bodySmall,
        ),
      ),
    ];
  }
}

/// A choice as a card: selected, it is outlined in the accent.
class _OptionCard extends StatelessWidget {
  final String identifier;
  final bool selected;
  final Color? color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _OptionCard({
    required this.identifier,
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Semantics(
        identifier: identifier,
        inMutuallyExclusiveGroup: true,
        checked: selected,
        child: Material(
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.35)
              : scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            minVerticalPadding: 12,
            onTap: onTap,
            leading: color == null
                ? null
                : Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(subtitle),
            trailing: ExcludeSemantics(
              child: Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  const _Panel({
    required this.children,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;

  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ChangeRow extends StatelessWidget {
  final String identifier;
  final String title;
  final String subtitle;
  final VoidCallback onChange;

  const _ChangeRow({
    required this.identifier,
    required this.title,
    required this.subtitle,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: Semantics(
      identifier: identifier,
      child: TextButton(
        onPressed: onChange,
        child: Text('Change', semanticsLabel: 'Change $title'),
      ),
    ),
  );
}
