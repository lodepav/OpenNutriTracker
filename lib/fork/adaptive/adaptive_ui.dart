import 'package:flutter/material.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/reload_diary_and_trends.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/macro_program.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/copy/copy_ui.dart';
import 'package:opennutritracker/fork/adaptive/check_in_history.dart';
import 'package:opennutritracker/fork/adaptive/check_in.dart';
import 'package:opennutritracker/fork/adaptive/expenditure_settings_ui.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/display/settings_tile.dart';

/// Seam S13: on home while a check-in is due; nothing otherwise. With
/// automatic check-ins (D17) it accepts a due one and says so instead; in
/// the daily activity mode it keeps today's stored goal in step with the
/// day's activity. [onAccepted] refreshes what shows the target.
class AdaptiveCheckInCard extends StatefulWidget {
  final VoidCallback onAccepted;
  final AdaptiveService? service;

  const AdaptiveCheckInCard({
    super.key,
    required this.onAccepted,
    this.service,
  });

  @override
  State<AdaptiveCheckInCard> createState() => _AdaptiveCheckInCardState();
}

/// Why a check-in is due: the week is up, or the goal changed (D18).
enum _Due { weekly, goal }

class _AdaptiveCheckInCardState extends State<AdaptiveCheckInCard> {
  late final _service = widget.service ?? AdaptiveService.fromLocator();
  late Future<_Due?> _due = _readDue();

  /// A check-in accepted on its own, and why, shown until dismissed.
  CheckIn? _autoAccepted;
  _Due _autoAcceptedFor = _Due.weekly;

  Future<_Due?> _readDue() async {
    if (!await _service.checkInDue()) return null;
    return await _service.goalChanged() ? _Due.goal : _Due.weekly;
  }

  @override
  void initState() {
    super.initState();
    AdaptiveStore.settings.addListener(_recheck);
    _autoAccept();
    _syncDailyGoal();
  }

  @override
  void didUpdateWidget(AdaptiveCheckInCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Home rebuilds after an activity is logged, the app resumes or the
    // profile (its goal) changes.
    _syncDailyGoal();
    if (_autoAccepted == null) {
      _due = _readDue();
      _autoAccept();
    }
  }

  @override
  void dispose() {
    AdaptiveStore.settings.removeListener(_recheck);
    super.dispose();
  }

  void _recheck() {
    final due = _readDue();
    setState(() {
      _due = due;
    });
    _autoAccept();
  }

  /// True while [_autoAccept] runs: Home rebuilding meanwhile must not
  /// accept the same check-in twice.
  bool _accepting = false;

  Future<void> _autoAccept() async {
    if (_accepting) return;
    _accepting = true;
    try {
      await _autoAcceptOnce();
    } finally {
      _accepting = false;
    }
  }

  Future<void> _autoAcceptOnce() async {
    if (!AdaptiveStore.settings.value.autoAcceptCheckIn) return;
    final CheckIn? accepted;
    final _Due reason;
    try {
      reason = await _service.goalChanged() ? _Due.goal : _Due.weekly;
      accepted = await _service.autoAcceptIfDue();
    } catch (_) {
      return; // The card stays, to be done by hand.
    }
    if (accepted == null || !mounted) return;
    setState(() {
      _autoAccepted = accepted;
      _autoAcceptedFor = reason;
      _due = Future.value(null);
    });
    await _refreshGoals();
    widget.onAccepted();
  }

  /// Today's counted activity when the goal was last written, and when.
  static double? _syncedActivity;
  static DateTime? _syncedAt;

  /// In the daily mode, reads today's steps and workouts and rewrites
  /// today's stored goal when they moved; at most once a minute, as Home
  /// rebuilds often.
  Future<void> _syncDailyGoal() async {
    final settings = AdaptiveStore.settings.value;
    if (!settings.adaptiveTarget ||
        settings.fixedTarget ||
        settings.activityMode != ActivityMode.daily ||
        !locator.isRegistered<SettingsBloc>()) {
      return;
    }
    final now = DateTime.now();
    if (_syncedAt != null && now.difference(_syncedAt!).inSeconds < 60) return;
    _syncedAt = now;
    try {
      final today = await locator<SettingsBloc>().getCurrentLogicalDay();
      final activity = await _service.activityOn(today, readHealth: true);
      if (activity == _syncedActivity) return;
      _syncedActivity = activity;
      await _refreshGoals();
    } catch (_) {
      // The goal keeps what it had; the next rebuild tries again.
    }
  }

  @override
  Widget build(BuildContext context) {
    final accepted = _autoAccepted;
    if (accepted != null) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: ListTile(
          leading: const Icon(Icons.insights_rounded),
          title: Text(
            _autoAcceptedFor == _Due.goal
                ? 'Target set for your new goal'
                : 'Weekly check-in done',
          ),
          subtitle: Text(
            'New target: ${energyText(context, accepted.proposedTargetKcal)}'
            '${AdaptiveStore.settings.value.activityMode == ActivityMode.daily ? ' before activity' : ''}.',
          ),
          trailing: IconButton(
            tooltip: 'Dismiss',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => setState(() => _autoAccepted = null),
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CheckInHistoryScreen(store: AdaptiveStore()),
            ),
          ),
        ),
      );
    }
    return FutureBuilder<_Due?>(
      future: _due,
      builder: (context, snapshot) {
        final due = snapshot.data;
        if (due == null) return const SizedBox.shrink();
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: const Icon(Icons.insights_rounded),
            title: Text(
              due == _Due.goal ? 'Your goal changed' : 'Weekly check-in',
            ),
            subtitle: Text(
              due == _Due.goal
                  ? 'A target for it is ready to check.'
                  : 'Your expenditure and next target are ready.',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              final accepted = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => CheckInScreen(service: _service),
                ),
              );
              if (accepted == true) {
                _recheck();
                await _refreshGoals();
                widget.onAccepted();
              }
            },
          ),
        );
      },
    );
  }
}

class CheckInScreen extends StatefulWidget {
  final AdaptiveService service;

  const CheckInScreen({super.key, required this.service});

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  late final Future<CheckIn> _checkIn = widget.service.checkIn();
  final _target = TextEditingController();

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  String _kcal(double value) => energyText(context, value);

  static String _kg(double value, {bool signed = false}) =>
      '${signed && value > 0 ? '+' : ''}${value.toStringAsFixed(1)} kg';

  static String _eta(int days) {
    final date = DateTime.now().add(Duration(days: days));
    final weeks = (days / 7).round();
    return 'about $weeks week${weeks == 1 ? '' : 's'} '
        '(${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')})';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Weekly check-in')),
    body: FutureBuilder<CheckIn>(
      future: _checkIn,
      builder: (context, snapshot) {
        final checkIn = snapshot.data;
        if (snapshot.hasError) {
          return const Center(child: Text("Couldn't read your data."));
        }
        if (checkIn == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_target.text.isEmpty) {
          _target.text = '${energyValue(context, checkIn.proposedTargetKcal)}';
        }
        final theme = Theme.of(context);
        final capped =
            (checkIn.uncappedTargetKcal - checkIn.proposedTargetKcal).abs() >=
            1;
        final settings = AdaptiveStore.settings.value;
        final cap = settings.maxCheckInChangeKcal;
        final daily = settings.activityMode == ActivityMode.daily;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Past week', style: theme.textTheme.titleMedium),
            _row(
              'Average logged',
              checkIn.averageIntakeKcal == null
                  ? 'nothing logged'
                  : '${_kcal(checkIn.averageIntakeKcal!)} '
                        '(${checkIn.loggedDays} of 7 days)',
            ),
            _row('Weigh-ins', '${checkIn.weighIns}'),
            if (checkIn.trendKg != null) _row('Trend', _kg(checkIn.trendKg!)),
            if (checkIn.weekChangeKg != null)
              _row('Trend change', _kg(checkIn.weekChangeKg!, signed: true)),
            if (!checkIn.enoughData)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Not enough data this week (4 logged days and a weigh-in '
                  'are needed), so the expenditure carries from before.',
                  style: TextStyle(color: theme.colorScheme.tertiary),
                ),
              ),
            const Divider(height: 32),
            _row('Expenditure', _kcal(checkIn.expenditureKcal)),
            if (checkIn.activityKcal case final activity?)
              _row('Of it, counted activity', '${_kcal(activity)} a day'),
            _row(
              daily ? 'Proposed target before activity' : 'Proposed target',
              _kcal(checkIn.proposedTargetKcal),
            ),
            if (daily)
              Text(
                "Each day's counted activity is added to it.",
                style: theme.textTheme.bodySmall,
              ),
            if (capped && cap != null)
              Text(
                'A check-in moves the expenditure under the target at most '
                '${_kcal(cap)}; the full change would put the target at '
                '${_kcal(checkIn.uncappedTargetKcal)}.',
                style: theme.textTheme.bodySmall,
              ),
            if (checkIn.daysToTargetAtGoal != null)
              _row(
                'Target weight, chosen pace',
                _eta(checkIn.daysToTargetAtGoal!),
              ),
            if (checkIn.daysToTargetAtTrend != null)
              _row(
                'Target weight, current trend',
                _eta(checkIn.daysToTargetAtTrend!),
              ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('check-in-target'),
              controller: _target,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Daily target',
                suffixText: energyUnit(context),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                final typed = double.tryParse(_target.text.trim());
                if (typed == null || !typed.isFinite || typed <= 0) return;
                final target = kcalFromInput(context, typed);
                await widget.service.accept(checkIn, target);
                if (context.mounted) Navigator.of(context).pop(true);
              },
              child: const Text('Accept'),
            ),
          ],
        );
      },
    ),
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

/// Where the kcal goal comes from; stored as the two switches.
enum _TargetMode { formula, adaptive, fixed }

_TargetMode _modeOf(AdaptiveSettings s) => s.fixedTarget
    ? _TargetMode.fixed
    : s.adaptiveTarget
    ? _TargetMode.adaptive
    : _TargetMode.formula;

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Today's stored goal and the screens showing it, after the target
/// changes; skipped where the app's blocs are not registered (tests).
Future<void> refreshGoals() => _refreshGoals();

Future<void> _refreshGoals() async {
  if (!locator.isRegistered<SettingsBloc>()) return;
  final settings = locator<SettingsBloc>();
  await settings.updateTrackedDay(await settings.getCurrentLogicalDay());
  locator<HomeBloc>().add(const LoadItemsEvent());
  reloadDiaryAndTrends();
}

/// Seam S14: the D13 switches in settings, with the fixed target and the
/// weekday shift.
class AdaptiveSettingsTile extends StatelessWidget {
  final AdaptiveStore? store;

  const AdaptiveSettingsTile({super.key, this.store});

  @override
  Widget build(BuildContext context) => ForkSettingsTile(
    icon: Icons.insights_rounded,
    title: 'Trend and calorie target',
    subtitle: ValueListenableBuilder(
      valueListenable: AdaptiveStore.settings,
      builder: (context, settings, _) => Text(
        '${settings.smoothedTrend ? 'Smoothed trend' : '7-day average'} · '
        '${switch (_modeOf(settings)) {
          _TargetMode.formula => 'Formula target',
          _TargetMode.adaptive => 'Adaptive target',
          _TargetMode.fixed => 'Fixed target',
        }}'
        '${settings.weekdayOffsets.any((o) => o != 0) ? ' · by weekday' : ''}',
      ),
    ),
    onTap: () => showDialog<void>(
      context: context,
      builder: (_) => _AdaptiveSettingsDialog(store ?? AdaptiveStore()),
    ),
  );
}

class _AdaptiveSettingsDialog extends StatelessWidget {
  final AdaptiveStore store;

  const _AdaptiveSettingsDialog(this.store);

  Future<void> _save(AdaptiveSettings value) async {
    await store.save(value);
    await _refreshGoals();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Trend and calorie target'),
    content: ValueListenableBuilder(
      valueListenable: AdaptiveStore.settings,
      builder: (context, settings, _) {
        final mode = _modeOf(settings);
        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Smoothed weight trend'),
                subtitle: const Text(
                  'On the weight chart, in place of the 7-day average.',
                ),
                value: settings.smoothedTrend,
                onChanged: (v) => _save(settings.copyWith(smoothedTrend: v)),
              ),
              const SizedBox(height: 8),
              Text(
                'Calorie target',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SegmentedButton<_TargetMode>(
                key: const ValueKey('target-mode'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: _TargetMode.formula,
                    label: Text('Formula'),
                  ),
                  ButtonSegment(
                    value: _TargetMode.adaptive,
                    label: Text('Adaptive'),
                  ),
                  ButtonSegment(value: _TargetMode.fixed, label: Text('Fixed')),
                ],
                selected: {mode},
                onSelectionChanged: (picked) => _save(
                  settings.copyWith(
                    adaptiveTarget: picked.single == _TargetMode.adaptive,
                    fixedTarget: picked.single == _TargetMode.fixed,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(switch (mode) {
                _TargetMode.formula =>
                  'From your profile and goal, plus logged activities.',
                _TargetMode.adaptive =>
                  'Measured from your weight and what you log, set at a '
                      'weekly check-in. ${switch (settings.activityMode) {
                        ActivityMode.off => 'Logged activities are not added to it.',
                        ActivityMode.weekly => "It counts the past week's activity.",
                        ActivityMode.daily => "Each day's activity is added to it.",
                      }}',
                _TargetMode.fixed =>
                  'One you set. Logged activities and the kcal adjustment '
                      'are not added to it.',
              }, style: Theme.of(context).textTheme.bodySmall),
              if (mode == _TargetMode.fixed)
                ListTile(
                  key: const ValueKey('fixed-target'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Fixed target: '
                    '${energyText(context, settings.fixedTargetKcal)}',
                  ),
                  subtitle: Text(
                    settings.fixedMacros == null
                        ? 'Macros from your split'
                        : _macroText(settings.fixedMacros!),
                  ),
                  trailing: const Icon(Icons.edit_rounded),
                  onTap: () async {
                    final edited = await showDialog<AdaptiveSettings>(
                      context: context,
                      builder: (_) => _FixedTargetDialog(settings),
                    );
                    if (edited != null) await _save(edited);
                  },
                ),
              if (mode == _TargetMode.adaptive)
                ListTile(
                  key: const ValueKey('expenditure-settings'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Expenditure and check-ins'),
                  subtitle: Text(expenditureSummary(settings)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ExpenditureSettingsScreen(store: store),
                    ),
                  ),
                ),
              ListTile(
                key: const ValueKey('weekday-targets'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Targets by weekday'),
                subtitle: Text(_offsetsText(context, settings.weekdayOffsets)),
                trailing: const Icon(Icons.edit_rounded),
                onTap: () async {
                  final edited = await showDialog<List<double>>(
                    context: context,
                    builder: (_) =>
                        _WeekdayTargetsDialog(settings.weekdayOffsets),
                  );
                  if (edited != null) {
                    await _save(settings.copyWith(weekdayOffsets: edited));
                  }
                },
              ),
              ListTile(
                key: const ValueKey('macro-program'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Macros'),
                subtitle: Text(
                  mode == _TargetMode.fixed && settings.fixedMacros != null
                      ? 'The fixed target\'s grams'
                      : settings.macroProgram?.summary ??
                            'Percentages from your macro split',
                ),
                trailing: const Icon(Icons.edit_rounded),
                onTap: () async {
                  final edited = await showDialog<({MacroProgram? program})>(
                    context: context,
                    builder: (_) => _MacroProgramDialog(settings.macroProgram),
                  );
                  if (edited != null) {
                    await _save(
                      settings.copyWith(macroProgram: () => edited.program),
                    );
                  }
                },
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

  static String _offsetsText(BuildContext context, List<double> offsets) {
    if (offsets.every((o) => o == 0)) return 'The same every day';
    return [
      for (final (i, o) in offsets.indexed)
        if (o != 0) '${_weekdays[i]} ${energyText(context, o, signed: true)}',
    ].join(', ');
  }
}

String _macroText(FixedMacros m) => inMacroOrder(
  protein: 'Protein ${m.proteinG.round()} g',
  carbs: 'Carbs ${m.carbsG.round()} g',
  fat: 'Fat ${m.fatG.round()} g',
).join(' · ');

/// The fixed target's energy, or its macros in grams, whose energy it
/// then is.
class _FixedTargetDialog extends StatefulWidget {
  final AdaptiveSettings settings;

  const _FixedTargetDialog(this.settings);

  @override
  State<_FixedTargetDialog> createState() => _FixedTargetDialogState();
}

class _FixedTargetDialogState extends State<_FixedTargetDialog> {
  late bool _grams = widget.settings.fixedMacros != null;
  final _kcal = TextEditingController();
  late final _protein = _field(widget.settings.fixedMacros?.proteinG);
  late final _carbs = _field(widget.settings.fixedMacros?.carbsG);
  late final _fat = _field(widget.settings.fixedMacros?.fatG);

  static TextEditingController _field(double? grams) =>
      TextEditingController(text: grams == null ? '' : '${grams.round()}');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_kcal.text.isEmpty) {
      _kcal.text = '${energyValue(context, widget.settings.fixedKcal)}';
    }
  }

  @override
  void dispose() {
    for (final c in [_kcal, _protein, _carbs, _fat]) {
      c.dispose();
    }
    super.dispose();
  }

  FixedMacros? get _macros {
    final p = double.tryParse(_protein.text.trim());
    final c = double.tryParse(_carbs.text.trim());
    final f = double.tryParse(_fat.text.trim());
    if (p == null ||
        c == null ||
        f == null ||
        !(p + c + f).isFinite ||
        p < 0 ||
        c < 0 ||
        f < 0) {
      return null;
    }
    final macros = FixedMacros(proteinG: p, carbsG: c, fatG: f);
    return macros.kcal > 0 ? macros : null;
  }

  @override
  Widget build(BuildContext context) {
    final macros = _macros;
    return AlertDialog(
      title: const Text('Fixed target'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Set macros in grams'),
              value: _grams,
              onChanged: (v) => setState(() => _grams = v),
            ),
            if (!_grams)
              TextField(
                key: const ValueKey('fixed-kcal'),
                controller: _kcal,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Daily target',
                  suffixText: energyUnit(context),
                ),
              )
            else ...[
              for (final (label, controller, key) in inMacroOrder(
                protein: ('Protein', _protein, 'fixed-protein'),
                carbs: ('Carbs', _carbs, 'fixed-carbs'),
                fat: ('Fat', _fat, 'fixed-fat'),
              ))
                TextField(
                  key: ValueKey(key),
                  controller: controller,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: label,
                    suffixText: 'g',
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                macros == null
                    ? 'Fill in all three.'
                    : 'Daily target: ${energyText(context, macros.kcal)}',
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            if (_grams) {
              if (macros == null) return;
              Navigator.pop(
                context,
                widget.settings.copyWith(fixedMacros: () => macros),
              );
              return;
            }
            final typed = double.tryParse(_kcal.text.trim());
            if (typed == null || !typed.isFinite || typed <= 0) return;
            Navigator.pop(
              context,
              widget.settings.copyWith(
                fixedKcal: kcalFromInput(context, typed),
                fixedMacros: () => null,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// kcal added to the target on each weekday (MacroFactor's calorie
/// shifting); the week's net is shown so a shift can be kept even.
class _WeekdayTargetsDialog extends StatefulWidget {
  final List<double> offsets;

  const _WeekdayTargetsDialog(this.offsets);

  @override
  State<_WeekdayTargetsDialog> createState() => _WeekdayTargetsDialogState();
}

class _WeekdayTargetsDialogState extends State<_WeekdayTargetsDialog> {
  final _fields = [for (var i = 0; i < 7; i++) TextEditingController()];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final (i, field) in _fields.indexed) {
      if (field.text.isEmpty) {
        field.text = '${energyValue(context, widget.offsets[i])}';
      }
    }
  }

  @override
  void dispose() {
    for (final f in _fields) {
      f.dispose();
    }
    super.dispose();
  }

  List<double>? _read(BuildContext context) {
    final out = <double>[];
    for (final f in _fields) {
      final text = f.text.trim();
      final typed = text.isEmpty ? 0.0 : double.tryParse(text);
      if (typed == null || !typed.isFinite) return null;
      out.add(kcalFromInput(context, typed));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final offsets = _read(context);
    final net = offsets?.fold<double>(0, (a, b) => a + b);
    return AlertDialog(
      title: const Text('Targets by weekday'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Added to the target on that day, or taken off with a minus.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            for (final (i, field) in _fields.indexed)
              TextField(
                key: ValueKey('weekday-$i'),
                controller: field,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: _weekdays[i],
                  suffixText: energyUnit(context),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              net == null
                  ? 'Numbers only.'
                  : net.abs() < 1
                  ? 'The week adds up to the same total.'
                  : 'The week is ${energyText(context, net, signed: true)} '
                        'on the usual total.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final read = _read(context);
            if (read != null) Navigator.pop(context, read);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Seam S17: atop "How your goal is calculated" while the adaptive or
/// fixed target is on, since the formula below it is then not the goal.
class AdaptiveGoalNote extends StatelessWidget {
  final AdaptiveStore? store;

  const AdaptiveGoalNote({super.key, this.store});

  /// The logical today, and the last check-in while the adaptive target
  /// sets the goal.
  Future<(DateTime, CheckInRecord?)> _read(AdaptiveSettings settings) async => (
    await logicalToday(),
    settings.adaptiveTarget && !settings.fixedTarget
        ? await (store ?? AdaptiveStore()).lastCheckIn()
        : null,
  );

  @override
  Widget build(BuildContext context) {
    final settings = AdaptiveStore.settings.value;
    if (!settings.fixedTarget &&
        !settings.adaptiveTarget &&
        settings.weekdayOffsets.every((o) => o == 0)) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<(DateTime, CheckInRecord?)>(
      future: _read(settings),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) return const SizedBox.shrink();
        final (today, last) = data;
        // Today's shift, as the goal on Home carries it.
        final shift = settings.weekdayOffsets[today.weekday - 1];
        String goal(double kcal) =>
            'Your goal today is ${energyText(context, kcal + shift)}'
            '${shift == 0 ? '' : ' (${energyText(context, shift, signed: true)} for the weekday)'}';
        if (settings.fixedTarget) {
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: ListTile(
              leading: const Icon(Icons.lock_outline_rounded),
              title: const Text('Fixed target is on'),
              subtitle: Text(
                '${goal(settings.fixedTargetKcal)}'
                '${settings.fixedMacros == null ? '' : ', from ${_macroText(settings.fixedMacros!)}'}, '
                'as set in Settings. The formula below is not used; logged '
                'activities and the kcal adjustment are not added.',
              ),
            ),
          );
        }
        if (!settings.adaptiveTarget) {
          if (shift == 0) return const SizedBox.shrink();
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: ListTile(
              leading: const Icon(Icons.calendar_view_week_rounded),
              title: const Text('Targets by weekday'),
              subtitle: Text(
                'Today ${energyText(context, shift, signed: true)} is added to '
                'the total below.',
              ),
            ),
          );
        }
        final d = last?.date;
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: ListTile(
            leading: const Icon(Icons.insights_rounded),
            title: const Text('Adaptive target is on'),
            subtitle: Text(
              last == null
                  ? 'Until the first weekly check-in, the formula below sets '
                        'your goal.'
                  : '${goal(last.acceptedKcal)}, set at '
                        'the check-in on ${d!.year}-'
                        '${d.month.toString().padLeft(2, '0')}-'
                        '${d.day.toString().padLeft(2, '0')} from a measured '
                        'expenditure of ${energyText(context, last.expenditureKcal)}. '
                        'The formula below is not used; logged activities '
                        'and the kcal adjustment are not added.',
            ),
          ),
        );
      },
    );
  }
}

/// The macro program, or none for upstream's percentages; pops a record
/// so "off" and "cancelled" differ.
class _MacroProgramDialog extends StatefulWidget {
  final MacroProgram? program;

  const _MacroProgramDialog(this.program);

  @override
  State<_MacroProgramDialog> createState() => _MacroProgramDialogState();
}

class _MacroProgramDialogState extends State<_MacroProgramDialog> {
  late bool _on = widget.program != null;
  late MacroProgram _program = widget.program ?? const MacroProgram();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Macros'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              key: const ValueKey('macro-program-on'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Protein per kg and a diet style'),
              subtitle: const Text(
                'In place of the percentages. Protein holds steady; carbs '
                'and fat take a weekday\'s shift.',
              ),
              value: _on,
              onChanged: (v) => setState(() => _on = v),
            ),
            if (_on) ...[
              Wrap(
                spacing: 6,
                children: [
                  for (final style in MacroStyle.values)
                    ChoiceChip(
                      key: ValueKey('macro-style-${style.name}'),
                      label: Text(style.label),
                      selected: _program.style == style,
                      onSelected: (_) => setState(
                        () => _program = MacroProgram(
                          style: style,
                          proteinGPerKg: _program.proteinGPerKg,
                          leanMass: _program.leanMass,
                        ),
                      ),
                    ),
                ],
              ),
              Text(
                _program.style.explanation,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Text(
                'Protein ${_program.proteinGPerKg.toStringAsFixed(1)} g per kg'
                '${_program.leanMass ? ' of lean mass' : ' of body weight'}',
              ),
              Slider(
                key: const ValueKey('macro-protein'),
                min: 1,
                max: 3,
                divisions: 20,
                value: _program.proteinGPerKg.clamp(1.0, 3.0),
                label: _program.proteinGPerKg.toStringAsFixed(1),
                onChanged: (v) => setState(
                  () => _program = MacroProgram(
                    style: _program.style,
                    proteinGPerKg: (v * 10).round() / 10,
                    leanMass: _program.leanMass,
                  ),
                ),
              ),
              SwitchListTile(
                key: const ValueKey('macro-lean'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Per kg of lean mass'),
                subtitle: const Text(
                  'Weight less body fat: your latest measured body fat %, '
                  'or an estimate from your BMI and age.',
                ),
                value: _program.leanMass,
                onChanged: (v) => setState(
                  () => _program = MacroProgram(
                    style: _program.style,
                    proteinGPerKg: v
                        ? MacroProgram.defaultPerKgLean
                        : MacroProgram.defaultPerKg,
                    leanMass: v,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, (program: _on ? _program : null)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
