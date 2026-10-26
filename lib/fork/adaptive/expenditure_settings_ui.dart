import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/calc/workout_compensation_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/adaptive/activity.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_ui.dart';
import 'package:opennutritracker/fork/adaptive/check_in_history.dart';
import 'package:opennutritracker/fork/adaptive/choice.dart';
import 'package:opennutritracker/fork/adaptive/expenditure.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/fork/health/steps.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';

/// The row's subtitle in "Trend and calorie target".
String expenditureSummary(AdaptiveSettings s) => [
  s.responsiveness.label,
  s.activityMode == ActivityMode.off
      ? 'activity off'
      : 'activity ${s.activityMode.label.toLowerCase()}',
  s.autoAcceptCheckIn ? 'automatic check-ins' : 'check-ins by hand',
].join(' · ');

/// D17: how expenditure is estimated, what activity it counts, and how
/// check-ins set the target; three groups on one screen.
class ExpenditureSettingsScreen extends StatelessWidget {
  final AdaptiveStore store;

  /// The steps reader; tests pass one over a memory box.
  final StepCounts? steps;

  const ExpenditureSettingsScreen({super.key, required this.store, this.steps});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Expenditure')),
    body: ValueListenableBuilder(
      valueListenable: AdaptiveStore.settings,
      builder: (context, settings, _) => ListView(
        // Clear of the system's navigation bar too: a set padding
        // replaces the one ListView would take from it.
        padding: EdgeInsets.only(
          bottom: 24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          _EstimateSection(settings, store),
          const Divider(),
          _ActivitySection(settings, store, steps ?? StepCounts()),
          const Divider(),
          _CheckInSection(settings, store),
        ],
      ),
    ),
  );
}

Future<void> _save(AdaptiveStore store, AdaptiveSettings value) async {
  await store.save(value);
  await refreshGoals();
}

class _Heading extends StatelessWidget {
  final String text;

  const _Heading(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Semantics(
      header: true,
      container: true,
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    ),
  );
}

class _Note extends StatelessWidget {
  final String text;

  const _Note(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Semantics(
      container: true,
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    ),
  );
}

class _EstimateSection extends StatelessWidget {
  final AdaptiveSettings settings;
  final AdaptiveStore store;

  const _EstimateSection(this.settings, this.store);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _Heading('Estimate'),
      StackingChoice<Responsiveness>(
        identifier: 'expenditure-responsiveness',
        values: Responsiveness.values,
        label: (r) => r.label,
        selected: settings.responsiveness,
        onChanged: (r) => _save(store, settings.copyWith(responsiveness: r)),
      ),
      _Note(switch (settings.responsiveness) {
        Responsiveness.steady =>
          'Moves least from day to day; follows a lasting change in about '
              '7 weeks.',
        Responsiveness.standard => 'Follows a lasting change in about 6 weeks.',
        Responsiveness.responsive =>
          'Follows a lasting change in about 5 weeks, and moves more from '
              'day to day.',
      }),
      SwitchListTile(
        title: const Text('Allow for a monthly cycle'),
        subtitle: const Text(
          'Reads a 28-day window, so a cycle\'s water swing moves the '
          'estimate less.',
        ),
        value: settings.cycleWindow,
        onChanged: (v) => _save(store, settings.copyWith(cycleWindow: v)),
      ),
      SwitchListTile(
        key: const ValueKey('flat-energy'),
        title: Text(
          'Count every kg as '
          '${energyText(context, AdaptiveSettings.commonKcalPerKg)}',
        ),
        subtitle: const Text(
          'As most apps do. Off, a kg follows your body composition: part '
          'of a change is lean tissue, which holds less. On, the same pace '
          'takes a larger deficit or surplus.',
        ),
        value: settings.flatEnergy,
        onChanged: (v) => _save(store, settings.copyWith(flatEnergy: v)),
      ),
      _SkippedDaysTile(store),
    ],
  );
}

/// The days left out, each with a way to count it again.
class _SkippedDaysTile extends StatelessWidget {
  final AdaptiveStore store;

  const _SkippedDaysTile(this.store);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: AdaptiveStore.skipped,
    builder: (context, days, _) => Semantics(
      container: true,
      child: ListTile(
        key: const ValueKey('skipped-days'),
        title: const Text('Days left out'),
        subtitle: Text(
          days.isEmpty
              ? 'None. Leave out a day logged only in part from its page in '
                    'the Diary.'
              : '${days.length} day${days.length == 1 ? '' : 's'}: what was '
                    'logged is not counted, the weigh-in is.',
        ),
        trailing: days.isEmpty ? null : const Icon(Icons.chevron_right_rounded),
        onTap: days.isEmpty
            ? null
            : () => showDialog<void>(
                context: context,
                builder: (_) => _SkippedDaysDialog(store),
              ),
      ),
    ),
  );
}

class _SkippedDaysDialog extends StatelessWidget {
  final AdaptiveStore store;

  const _SkippedDaysDialog(this.store);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Days left out'),
    content: ValueListenableBuilder(
      valueListenable: AdaptiveStore.skipped,
      builder: (context, skipped, _) {
        final days = skipped.toList()..sort((a, b) => b.compareTo(a));
        if (days.isEmpty) return const Text('None left out.');
        return SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final day in days)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(DateFormat.yMMMEd().format(day)),
                  // The row reads as one: the date, then the button.
                  trailing: TextButton(
                    onPressed: () => store.setSkipped(day, false),
                    child: const Text('Count again'),
                  ),
                ),
            ],
          ),
        );
      },
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );
}

class _ActivitySection extends StatefulWidget {
  final AdaptiveSettings settings;
  final AdaptiveStore store;
  final StepCounts steps;

  const _ActivitySection(this.settings, this.store, this.steps);

  @override
  State<_ActivitySection> createState() => _ActivitySectionState();
}

class _ActivitySectionState extends State<_ActivitySection> {
  /// Whether Health Connect steps are connected; false until read.
  bool _stepsOn = false;

  @override
  void initState() {
    super.initState();
    _readStepsOn();
  }

  /// A box that cannot be read (tests) leaves the switch off.
  Future<void> _readStepsOn() async {
    final on = await widget.steps.isOn().catchError((Object _) => false);
    if (mounted) setState(() => _stepsOn = on);
  }

  /// The share suggested from body composition, in percent; null until
  /// read, or where the profile cannot be read (tests).
  late final Future<double?> _suggested = _readSuggested();

  Future<double?> _readSuggested() async {
    if (!locator.isRegistered<GetUserUsecase>()) return null;
    final UserEntity user = await locator<GetUserUsecase>().getUserData();
    final bodyFat = await MeasurementStore().recentBodyFat(DateTime.now());
    return toShareStep(
          WorkoutCompensationCalc.suggestedMultiplier(
            bodyFatPercent: bodyFat,
            user: user,
          ),
        ) *
        100;
  }

  Future<void> _countSteps(bool on) async {
    final settings = widget.settings;
    if (on && !await widget.steps.isOn()) {
      final granted = await widget.steps.turnOn().catchError(
        (Object _) => false,
      );
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Steps need the Health Connect permission.'),
            ),
          );
        }
        return;
      }
    }
    await _readStepsOn();
    await _save(widget.store, settings.copyWith(countSteps: on));
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final store = widget.store;
    final counting = settings.activityMode != ActivityMode.off;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Heading('Activity'),
        StackingChoice<ActivityMode>(
          identifier: 'expenditure-activity-mode',
          values: ActivityMode.values,
          label: (m) => m.label,
          selected: settings.activityMode,
          onChanged: (m) => _save(store, settings.copyWith(activityMode: m)),
        ),
        _Note(switch (settings.activityMode) {
          ActivityMode.off =>
            'Your weight and what you log already show what you burn, '
                'activity included. The target is the same every day.',
          ActivityMode.weekly =>
            "Each check-in adds the past week's average activity, so the "
                'target follows a change in training within a week. It '
                'stays the same all week.',
          ActivityMode.daily =>
            "Each day's activity is added to that day's target as it "
                'comes in, so active days get more and rest days less.',
        }),
        if (counting) ...[
          SwitchListTile(
            key: const ValueKey('count-steps'),
            title: const Text('Steps'),
            subtitle: const Text(
              'From Health Connect, at what walking costs for your weight '
              'and height. Steps within an imported workout count once.',
            ),
            value: settings.countSteps && _stepsOn,
            onChanged: _countSteps,
          ),
          SwitchListTile(
            key: const ValueKey('count-workouts'),
            title: const Text('Workouts'),
            subtitle: const Text(
              'Logged ones, and those imported from Health Connect, at the '
              'calories the device reported.',
            ),
            value: settings.countWorkouts,
            onChanged: (v) => _save(store, settings.copyWith(countWorkouts: v)),
          ),
          if (settings.countWorkouts)
            FutureBuilder<double?>(
              future: _suggested,
              builder: (context, snapshot) => _WorkoutShare(
                settings: settings,
                suggestedPct: snapshot.data,
                onChanged: (pct) =>
                    _save(store, settings.copyWith(workoutSharePct: () => pct)),
              ),
            ),
          const _Note(
            'The estimate takes your average counted activity off first, '
            'so activity that is overstated hardly moves the average target. '
            'What it changes is how much one active day or week adds.',
          ),
        ],
      ],
    );
  }
}

/// The share of workout calories counted: a slider from 30 to 100%, and
/// the suggestion until one is set.
class _WorkoutShare extends StatelessWidget {
  final AdaptiveSettings settings;
  final double? suggestedPct;
  final ValueChanged<double?> onChanged;

  const _WorkoutShare({
    required this.settings,
    required this.suggestedPct,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final set = settings.workoutSharePct;
    final pct =
        (set ??
                suggestedPct ??
                toShareStep(WorkoutCompensationCalc.fallbackMultiplier) * 100)
            .clamp(30.0, 100.0);
    final suggested = suggestedPct?.round();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The slider reads its own name and value; the text is for the
          // eye, and its own node so it does not take in the heading.
          ExcludeSemantics(
            child: Text('Workout calories counted: ${pct.round()}%'),
          ),
          MergeSemantics(
            child: Semantics(
              identifier: 'workout-share',
              label: 'Workout calories counted',
              child: Slider(
                value: pct,
                min: 30,
                max: 100,
                divisions: 14,
                semanticFormatterCallback: (v) => '${v.round()}%',
                onChanged: (v) => onChanged(v.roundToDouble()),
              ),
            ),
          ),
          Semantics(
            container: true,
            child: Text(
              'Watches tend to overstate a workout, and the body makes up part '
              'of it by moving less afterwards. '
              '${suggested == null ? '' : 'Suggested for your body: $suggested%. '}'
              'Lower it if workout days leave you over.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (set != null && suggested != null && set.round() != suggested)
            TextButton(
              onPressed: () => onChanged(null),
              child: const Text('Use the suggestion'),
            ),
        ],
      ),
    );
  }
}

class _CheckInSection extends StatelessWidget {
  final AdaptiveSettings settings;
  final AdaptiveStore store;

  const _CheckInSection(this.settings, this.store);

  static String _weekday(int weekday) =>
      // 2024-01-01 was a Monday.
      DateFormat.EEEE().format(DateTime(2024, 1, weekday));

  @override
  Widget build(BuildContext context) {
    final adaptive = settings.adaptiveTarget && !settings.fixedTarget;
    final cap = settings.maxCheckInChangeKcal;
    final kj = usesKj(context);
    final steps = kj ? const [400, 800, 1200] : const [100, 200, 300];
    double shown(double kcal) => kj ? UnitCalc.kcalToKj(kcal) : kcal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Heading('Check-in'),
        if (!adaptive)
          const _Note(
            'Used when the calorie target is Adaptive. The estimate above '
            'shows on Trends either way.',
          ),
        ListTile(
          key: const ValueKey('check-in-day'),
          enabled: adaptive,
          title: const Text('Check-in day'),
          subtitle: Text(
            settings.checkInWeekday == null
                ? 'A week after the last one'
                : 'Every ${_weekday(settings.checkInWeekday!)}; a missed '
                      'one stays due until done',
          ),
          trailing: const Icon(Icons.edit_rounded),
          onTap: () async {
            final picked = await showDialog<({int? weekday})>(
              context: context,
              builder: (context) => SimpleDialog(
                title: const Text('Check-in day'),
                children: [
                  for (final day in [null, 1, 2, 3, 4, 5, 6, 7])
                    ListTile(
                      selected: day == settings.checkInWeekday,
                      trailing: day == settings.checkInWeekday
                          ? const Icon(Icons.check_rounded)
                          : null,
                      title: Text(
                        day == null
                            ? 'A week after the last one'
                            : _weekday(day),
                      ),
                      onTap: () => Navigator.pop(context, (weekday: day)),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                  ),
                ],
              ),
            );
            if (picked != null) {
              await _save(
                store,
                settings.copyWith(checkInWeekday: () => picked.weekday),
              );
            }
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          // The segments below carry it as their group's name.
          child: ExcludeSemantics(
            child: Text(
              'Largest change per check-in',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
        const _Note(
          'A limit keeps one odd week from moving the expenditure under the '
          'target far. A goal you change applies in full at once.',
        ),
        // Round steps in the display unit; a limit set in the other unit
        // shows as its nearest step.
        StackingChoice<int>(
          identifier: 'check-in-cap',
          groupLabel: 'Largest change per check-in',
          values: [...steps, 0],
          label: (v) => v == 0 ? 'No limit' : '$v ${energyUnit(context)}',
          selected: cap == null
              ? 0
              : steps.reduce(
                  (a, b) =>
                      (a - shown(cap)).abs() <= (b - shown(cap)).abs() ? a : b,
                ),
          onChanged: adaptive
              ? (v) => _save(
                  store,
                  settings.copyWith(
                    maxCheckInChangeKcal: () =>
                        v == 0 ? null : kcalFromInput(context, v.toDouble()),
                  ),
                )
              : null,
        ),
        SwitchListTile(
          key: const ValueKey('auto-accept-check-in'),
          title: const Text('Accept check-ins automatically'),
          subtitle: const Text(
            'The proposed target is set without asking; Home says so.',
          ),
          value: settings.autoAcceptCheckIn,
          onChanged: adaptive
              ? (v) => _save(store, settings.copyWith(autoAcceptCheckIn: v))
              : null,
        ),
        ListTile(
          key: const ValueKey('check-in-history'),
          title: const Text('Check-in history'),
          subtitle: const Text('Each target set, and from what'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => CheckInHistoryScreen(store: store),
            ),
          ),
        ),
      ],
    );
  }
}
