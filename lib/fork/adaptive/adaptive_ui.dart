import 'package:flutter/material.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/reload_diary_and_trends.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/macro_program.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/check_in_history.dart';
import 'package:opennutritracker/fork/adaptive/check_in.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';

/// Seam S13: on home while a check-in is due; nothing otherwise.
/// [onAccepted] refreshes what shows the target.
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

class _AdaptiveCheckInCardState extends State<AdaptiveCheckInCard> {
  late final _service = widget.service ?? AdaptiveService.fromLocator();
  late Future<bool> _due = _service.checkInDue();

  @override
  void initState() {
    super.initState();
    AdaptiveStore.settings.addListener(_recheck);
  }

  @override
  void dispose() {
    AdaptiveStore.settings.removeListener(_recheck);
    super.dispose();
  }

  void _recheck() {
    final due = _service.checkInDue();
    setState(() {
      _due = due;
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _due,
    builder: (context, snapshot) {
      if (snapshot.data != true) return const SizedBox.shrink();
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: ListTile(
          leading: const Icon(Icons.insights_rounded),
          title: const Text('Weekly check-in'),
          subtitle: const Text('Your expenditure and next target are ready.'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () async {
            final accepted = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => CheckInScreen(service: _service),
              ),
            );
            if (accepted == true) {
              _recheck();
              widget.onAccepted();
            }
          },
        ),
      );
    },
  );
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
            _row('Proposed target', _kcal(checkIn.proposedTargetKcal)),
            if (capped)
              Text(
                'A check-in moves the target at most '
                '${_kcal(maxCheckInChangeKcal)}; the full change '
                'would be ${_kcal(checkIn.uncappedTargetKcal)}.',
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
                if (typed == null || typed <= 0) return;
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
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.insights_rounded),
    title: const Text('Trend and calorie target'),
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
                      'weekly check-in. Logged activities are not added to it.',
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
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Allow for a monthly cycle'),
                  subtitle: const Text(
                    'Reads a 28-day window, so a cycle\'s water swing moves '
                    'the estimate less.',
                  ),
                  value: settings.cycleWindow,
                  onChanged: (v) => _save(settings.copyWith(cycleWindow: v)),
                ),
              if (mode == _TargetMode.adaptive)
                ListTile(
                  key: const ValueKey('check-in-history'),
                  contentPadding: EdgeInsets.zero,
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

String _macroText(FixedMacros m) =>
    'Protein ${m.proteinG.round()} g · Carbs ${m.carbsG.round()} g · '
    'Fat ${m.fatG.round()} g';

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
    if (p == null || c == null || f == null || p < 0 || c < 0 || f < 0) {
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
              for (final (label, controller, key) in [
                ('Protein', _protein, 'fixed-protein'),
                ('Carbs', _carbs, 'fixed-carbs'),
                ('Fat', _fat, 'fixed-fat'),
              ])
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
            if (typed == null || typed <= 0) return;
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
      if (typed == null) return null;
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

  @override
  Widget build(BuildContext context) {
    final settings = AdaptiveStore.settings.value;
    if (settings.fixedTarget) {
      return Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: ListTile(
          leading: const Icon(Icons.lock_outline_rounded),
          title: const Text('Fixed target is on'),
          subtitle: Text(
            'Your goal is ${energyText(context, settings.fixedTargetKcal)}'
            '${settings.fixedMacros == null ? '' : ' (${_macroText(settings.fixedMacros!)})'}, '
            'as set in Settings. The formula below is not used; logged '
            'activities and the kcal adjustment are not added.',
          ),
        ),
      );
    }
    if (!settings.adaptiveTarget) {
      final now = DateTime.now();
      final shift = settings.weekdayOffsets[now.weekday - 1];
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
    return FutureBuilder<CheckInRecord?>(
      future: (store ?? AdaptiveStore()).lastCheckIn(),
      builder: (context, snapshot) {
        final last = snapshot.data;
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
                  : 'Your goal is ${energyText(context, last.acceptedKcal)}, set at '
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
