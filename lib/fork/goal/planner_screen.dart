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

  /// The goal running now, to edit or replace.
  final PhasePlan? running;

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
    this.running,
    this.targetKg,
    this.onboarding = false,
  });

  /// For [user], with no weigh-ins: onboarding's, or a profile's before its
  /// first.
  factory PlannerSetup.ofUser(
    UserEntity user,
    BodyWeightUnit unit, {
    bool onboarding = false,
    PhasePlan? running,
  }) => PlannerSetup(
    nowKg: user.weightKG,
    unit: unit,
    expenditureKcal: CalorieGoalCalc.getTdee(user),
    bodyFatPercent: adaptive.bodyFatPercent(user),
    targetKg: user.targetWeightKg,
    running: running,
    onboarding: onboarding,
  );

  /// The active profile's.
  static Future<PlannerSetup> load() async {
    final user = await locator<GetUserUsecase>().getUserData();
    final unit = (await locator<GetConfigUsecase>().getConfig()).bodyWeightUnit;
    final running = await PhaseStore().plan();
    final inputs = await adaptive.AdaptiveService.fromLocator().goalPlan();
    if (inputs == null) {
      return PlannerSetup.ofUser(user, unit, running: running);
    }
    return PlannerSetup(
      nowKg: inputs.nowKg,
      unit: unit,
      expenditureKcal: inputs.expenditureKcal,
      bodyFatPercent: inputs.bodyFatPercent,
      targetKg: inputs.targetWeightKg,
      running: running,
    );
  }
}

/// Opens the planner on the active profile's goal: [fresh] plans a new one
/// (the running one is kept as completed when it starts), else the
/// running goal is edited. True once a plan was started.
Future<bool> openGoalPlanner(BuildContext context, {bool fresh = false}) async {
  final setup = await PlannerSetup.load();
  if (!context.mounted) return false;
  final running = setup.running;
  final today = DateTime.now();
  final draft = running != null && !fresh
      ? GoalDraft.of(running, setup.nowKg)
      : GoalDraft.fresh(setup.nowKg, today, targetKg: setup.targetKg);
  final started = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => GoalPlannerScreen(
        setup: setup,
        draft: draft,
        onStart: (plan) => GoalActions().start(
          plan,
          replacing: fresh ? running : null,
          nowKg: setup.nowKg,
        ),
      ),
    ),
  );
  return started ?? false;
}

const _stepNames = [
  'Goal',
  'Pace',
  'What you burn',
  'Calorie target',
  'Macros',
  'Your plan',
];

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

  const GoalPlannerScreen({
    super.key,
    required this.setup,
    required this.draft,
    required this.onStart,
    this.store,
  });

  @override
  State<GoalPlannerScreen> createState() => _GoalPlannerScreenState();
}

class _GoalPlannerScreenState extends State<GoalPlannerScreen> {
  late final _store = widget.store ?? AdaptiveStore();
  late final _before = AdaptiveStore.settings.value;
  late final _macrosBefore = OnboardingMacros.pending.value;
  late GoalDraft _draft = widget.draft;
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
  double _kcalAt(double kgPerWeek) =>
      _setup.expenditureKcal + kgPerWeek * AdaptiveSettings.commonKcalPerKg / 7;

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
    final saved = await widget.onStart(_draft.toPlan());
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

  bool get _canGoOn => switch (_step) {
    0 => _draft.problem == null,
    4 => _macrosValid,
    _ => true,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = _step == _stepNames.length - 1;
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
          title: const Text('Plan your goal'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    for (var i = 0; i < _stepNames.length; i++) ...[
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
        body: ListView(
          key: ValueKey('goal-planner-step-$_step'),
          padding: const EdgeInsets.only(bottom: Dimens.spacing24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Step ${_step + 1} of ${_stepNames.length} · '
                '${_stepNames[_step]}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ...switch (_step) {
              0 => _goalStep(context),
              1 => _paceStep(context),
              2 => _burnStep(context),
              3 => _targetStep(context),
              4 => _macrosStep(context),
              _ => _planStep(context),
            },
          ],
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
                      child: Text(last ? 'Start plan' : 'Next'),
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
        'Your ${_setup.running == null ? 'weight' : 'trend weight'} is '
            '${_kg(_setup.nowKg)}. Diet breaks come in the next step.',
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
            _draft = _draft.copyWith(
              kind: kind,
              paceKg: switch (kind) {
                PhaseKind.cut => cutPacesKg[1],
                PhaseKind.bulk => bulkPacesKg[1],
                PhaseKind.maintain => 0,
              },
              breaks: kind == PhaseKind.cut && _draft.breaks,
            );
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
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(
          spacing: 8,
          children: [
            for (final (id, label, day) in [
              ('today', 'Today, ${_date(today)}', today),
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
                  selected: _sameDay(_draft.start, day),
                  onSelected: (_) => setState(
                    () => _draft = _draft.copyWith(
                      start: DateTime(day.year, day.month, day.day),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ];
  }

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

  List<Widget> _paceStep(BuildContext context) {
    final plan = _draft.toPlan();
    final end = _dayBefore(plan.end);
    if (_draft.kind == PhaseKind.maintain) {
      return [
        _question(
          context,
          'For how long?',
          'Maintenance at what you burn, about '
              '${energyText(context, _setup.expenditureKcal)} a day. When '
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
            final at = _draft.copyWith(paceKg: pace).toPlan();
            final kcal = (pace * AdaptiveSettings.commonKcalPerKg / 7).round();
            return _OptionCard(
              identifier: 'goal-pace-$i',
              selected: _draft.paceKg == pace,
              title: '${['Gentle', 'Steady', 'Fast'][i]} · ${_rate(pace)}',
              subtitle:
                  'about ${energyText(context, kcal.toDouble())} '
                  '${cut ? 'under' : 'over'} · until '
                  '${_date(_dayBefore(at.end))} · '
                  '${(pace / _draft.startKg * 100).toStringAsFixed(1)}% a week',
              onTap: () =>
                  setState(() => _draft = _draft.copyWith(paceKg: pace)),
            );
          },
        ),
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
      'What you burn a day. The target is built on it, so a good estimate '
          'matters more than the pace.',
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
      ],
    ),
    ExpenditureGroups.estimate(store: _store),
  ];

  // -------------------------------------------------------------- target

  List<Widget> _targetStep(BuildContext context) {
    final pace = _draft.signedPace;
    final shift = (pace * AdaptiveSettings.commonKcalPerKg / 7).round();
    final breaks = _draft.toPlan().phases.length > 1;
    return [
      _question(
        context,
        'How the target is set',
        pace == 0
            ? 'At maintenance the target is what you burn, about '
                  '${energyText(context, _setup.expenditureKcal)}.'
            : 'What you burn, ${energyText(context, _setup.expenditureKcal)}, '
                  '${pace < 0 ? 'less' : 'plus'} the pace\'s '
                  '${energyText(context, shift.abs().toDouble())} gives about '
                  '${energyText(context, _kcalAt(pace))} a day'
                  '${breaks ? '; on diet breaks, what you burn.' : '.'}',
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

  // ---------------------------------------------------------------- plan

  List<Widget> _planStep(BuildContext context) {
    final plan = _draft.toPlan();
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
            onChange: () => setState(() => _step = 2),
          ),
          _ChangeRow(
            identifier: 'goal-plan-change-target',
            title: 'Calorie target',
            subtitle: targetSummary(settings),
            onChange: () => setState(() => _step = 3),
          ),
          _ChangeRow(
            identifier: 'goal-plan-change-macros',
            title: 'Macros',
            subtitle: settings.fixedTarget && settings.fixedMacros != null
                ? 'The fixed target\'s grams'
                : program?.summary(perLb: _perLb) ??
                      'Percentages from your macro split',
            onChange: () => setState(() => _step = 4),
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
