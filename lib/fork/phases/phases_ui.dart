import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/fork/units/weight_text.dart';

/// As the locale writes a date, as the rest of the app does.
String _date(DateTime d) => DateFormat.yMMMd().format(d);

String _pace(double kgPerWeek) => kgPerWeek == 0
    ? 'at maintenance'
    : '${kgPerWeek > 0 ? '+' : ''}${kgPerWeek.toStringAsFixed(2)} kg a week';

/// Calendar days from [from] to [to], whatever the clock changes between.
int _daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

String _weeks(int weeks) => '$weeks week${weeks == 1 ? '' : 's'}';

/// Whether phase [i] of [plan], one to a weight, stops short of it: at
/// the most weeks a phase runs.
bool _short(PhasePlan plan, int i) {
  final until = plan.phases[i].untilKg, end = plan.weightAt(i + 1);
  return until != null && end != null && (end - until).abs() > 1e-6;
}

String _phaseText(PhasePlan plan, int i, BodyWeightUnit unit) {
  final p = plan.phases[i];
  final pace = p.kgPerWeek == 0 ? _pace(0) : 'at ${_pace(p.kgPerWeek)}';
  return switch (p.untilKg) {
    null => '${p.kind.label}, ${_weeks(p.weeks)} $pace',
    final kg when _short(plan, i) =>
      '${p.kind.label} toward ${weightText(kg, unit)}, ${_weeks(p.weeks)} '
          '(the longest a phase runs) $pace',
    final kg =>
      '${p.kind.label} to ${weightText(kg, unit)}, about ${_weeks(p.weeks)} '
          '$pace',
  };
}

/// ", ~80.0 kg" for a plan that knows the weights, nothing otherwise.
String _about(double? kg, BodyWeightUnit unit) =>
    kg == null ? '' : ', ~${weightText(kg, unit)}';

/// [_about] the end of phase [i], but nothing for one that ends at the
/// weight it names already.
String _aboutEnd(PhasePlan plan, int i, BodyWeightUnit unit) =>
    plan.phases[i].untilKg != null && !_short(plan, i)
    ? ''
    : _about(plan.weightAt(i + 1), unit);

/// Seam S40: diet phases on Trends, the running one and what follows,
/// and the editor. A new plan starts from the trend weight, read from
/// [service], so each phase shows the weight it ends at about.
class DietPhasesCard extends StatefulWidget {
  final PhaseStore? store;
  final DateTime Function() clock;
  final BodyWeightUnit unit;
  final AdaptiveService? service;

  const DietPhasesCard({
    super.key,
    this.store,
    this.clock = DateTime.now,
    this.unit = BodyWeightUnit.kg,
    this.service,
  });

  @override
  State<DietPhasesCard> createState() => _DietPhasesCardState();
}

class _DietPhasesCardState extends State<DietPhasesCard> {
  late final _store = widget.store ?? PhaseStore();
  late Future<({PhasePlan? plan})?> _plan = _load();

  @override
  void initState() {
    super.initState();
    PhaseStore.changes.addListener(_reload);
  }

  @override
  void dispose() {
    PhaseStore.changes.removeListener(_reload);
    super.dispose();
  }

  /// Null hides the card, when the store can't be read.
  Future<({PhasePlan? plan})?> _load() async {
    try {
      return (plan: await _store.plan());
    } catch (_) {
      return null;
    }
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _plan = _load();
    });
  }

  Future<double?> _nowKg() async {
    try {
      return (await (widget.service ?? AdaptiveService.fromLocator())
              .goalPlan())
          ?.nowKg;
    } catch (_) {
      return null; // No weights: phases by time only.
    }
  }

  Future<void> _edit(PhasePlan? plan) async {
    // The editor opens at once; the weights come in when the trend is read.
    final edited = await Navigator.of(context).push<({PhasePlan? plan})>(
      MaterialPageRoute(
        builder: (_) => PhasePlanScreen(
          plan: plan,
          today: widget.clock(),
          nowKg: _nowKg(),
          unit: widget.unit,
        ),
      ),
    );
    if (edited != null) await _store.save(edited.plan);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<({PhasePlan? plan})?>(
    future: _plan,
    builder: (context, snapshot) {
      final read = snapshot.data;
      if (read == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: Dimens.spacing16),
        child: _card(context, read.plan),
      );
    },
  );

  Widget _card(BuildContext context, PhasePlan? plan) {
    final theme = Theme.of(context);
    final unit = widget.unit;
    final now = widget.clock();
    final index = plan?.indexOn(now);
    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Diet phases', style: theme.textTheme.titleMedium),
              ),
              TextButton(
                key: const ValueKey('phases-edit'),
                onPressed: () => _edit(plan),
                child: Text(plan == null ? 'Plan' : 'Edit'),
              ),
            ],
          ),
          if (plan == null || index == null)
            Text(
              'A cut, maintenance (a diet break) and a bulk, one after '
              'another: each phase\'s pace goes into your goal as it begins.',
              style: theme.textTheme.bodySmall,
            )
          else ...[
            if (index < 0)
              Text('Starts ${_date(plan.start)}')
            else if (index >= plan.phases.length)
              Text(
                'Ended ${_date(plan.end)}'
                '${_about(plan.weightAt(plan.phases.length), unit)}; '
                'at maintenance since.',
              )
            else ...[
              Text(
                'Now: ${_phaseText(plan, index, unit)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                'Week ${_daysBetween(plan.startOf(index), now) ~/ 7 + 1} '
                'of ${plan.phases[index].weeks}, until '
                '${_date(plan.startOf(index + 1))}'
                '${_aboutEnd(plan, index, unit)}',
              ),
            ],
            const SizedBox(height: Dimens.spacing8),
            for (final (i, _) in plan.phases.indexed)
              if (i > index)
                Text(
                  '${_date(plan.startOf(i))}: ${_phaseText(plan, i, unit)}'
                  '${_aboutEnd(plan, i, unit)}',
                  style: theme.textTheme.bodySmall,
                ),
          ],
        ],
      ),
    );
  }
}

/// Builds the plan: its start and the phases in order. Pops a record, its
/// plan null to remove it; nothing when left unsaved.
class PhasePlanScreen extends StatefulWidget {
  final PhasePlan? plan;
  final DateTime today;

  /// The trend weight a new plan starts from, read as the editor opens;
  /// null, or none read, leaves phases by time.
  final Future<double?>? nowKg;
  final BodyWeightUnit unit;

  const PhasePlanScreen({
    super.key,
    this.plan,
    required this.today,
    this.nowKg,
    this.unit = BodyWeightUnit.kg,
  });

  @override
  State<PhasePlanScreen> createState() => _PhasePlanScreenState();
}

class _PhasePlanScreenState extends State<PhasePlanScreen> {
  late DateTime _start =
      widget.plan?.start ??
      DateTime(widget.today.year, widget.today.month, widget.today.day);
  late final List<DietPhase> _phases = [
    ...?widget.plan?.phases,
    if (widget.plan == null)
      const DietPhase(kind: PhaseKind.cut, kgPerWeek: -0.5, weeks: 12),
  ];

  static double _defaultPace(PhaseKind kind) => switch (kind) {
    PhaseKind.cut => -0.5,
    PhaseKind.maintain => 0,
    PhaseKind.bulk => 0.25,
  };

  /// The weight the plan starts from: its own, kept from when it was
  /// made, or today's trend for a new one (and, until it runs, for a plan
  /// from before weights were kept) once read.
  late double? _startKg = widget.plan?.startKg;

  /// The trend weight being read, when the plan takes it; Save waits for
  /// it, so a plan saved at once still keeps its weight.
  Future<double?>? _reading;

  @override
  void initState() {
    super.initState();
    final plan = widget.plan;
    if (plan == null || plan.startKg == null && !plan.start.isBefore(_today)) {
      _reading = widget.nowKg?.then((kg) {
        if (kg != null && mounted) {
          setState(() {
            _startKg = kg;
            _reflow();
          });
        }
        return kg;
      });
    }
  }

  DateTime get _today =>
      DateTime(widget.today.year, widget.today.month, widget.today.day);

  PhasePlan get _plan =>
      PhasePlan(start: _start, phases: List.of(_phases), startKg: _startKg);

  /// A step of the target weight: half a kilo, or a pound.
  double get _stepKg => widget.unit == BodyWeightUnit.kg ? 0.5 : 1 / 2.20462;

  double _round(double kg) => (kg / _stepKg).round() * _stepKg;

  String _weight(double kg) => weightText(kg, widget.unit);

  /// A first target for a phase to a weight: where its weeks would take it,
  /// rounded to a step, and past [from] the pace's way, as the stepper
  /// allows.
  double _seed(double from, DietPhase p) {
    final way = p.kgPerWeek < 0 ? -1 : 1;
    var kg = _round(from + p.kgPerWeek * p.weeks);
    while ((kg - from) * way <= 1e-9) {
      kg += way * _stepKg;
    }
    return kg;
  }

  /// Works out again the weeks of each phase to a weight, from the weight
  /// it now starts at.
  void _reflow() {
    for (var i = 0; i < _phases.length; i++) {
      final p = _phases[i];
      final until = p.untilKg;
      final from = _plan.weightAt(i);
      if (until == null || from == null) continue;
      // Earlier phases now get past it: a phase by time, as long as it was.
      final passed = (until - from) * p.kgPerWeek <= 0;
      _phases[i] = DietPhase(
        kind: p.kind,
        kgPerWeek: p.kgPerWeek,
        weeks: passed ? p.weeks : DietPhase.weeksTo(from, until, p.kgPerWeek),
        untilKg: passed ? null : until,
      );
    }
  }

  /// Whether the user changed anything, so back asks before it's lost.
  bool _changed = false;

  void _set(int i, DietPhase phase) => setState(() {
    _changed = true;
    _phases[i] = phase;
    _reflow();
  });

  void _until(int i, double kg) {
    final p = _phases[i];
    _set(
      i,
      DietPhase(
        kind: p.kind,
        kgPerWeek: p.kgPerWeek,
        weeks: p.weeks,
        untilKg: kg,
      ),
    );
  }

  Widget _phase(int i) {
    final p = _phases[i];
    final from = _plan.weightAt(i);
    final until = p.untilKg;
    return Card(
      key: ValueKey('phase-$i'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    children: [
                      for (final kind in PhaseKind.values)
                        ChoiceChip(
                          key: ValueKey('phase-$i-${kind.name}'),
                          label: Text(kind.label),
                          selected: p.kind == kind,
                          onSelected: (_) => _set(
                            i,
                            DietPhase(
                              kind: kind,
                              kgPerWeek: _defaultPace(kind),
                              weeks: p.weeks,
                              untilKg: kind == p.kind ? p.untilKg : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('phase-$i-remove'),
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: _phases.length == 1
                      ? null
                      : () => setState(() {
                          _changed = true;
                          _phases.removeAt(i);
                          _reflow();
                        }),
                ),
              ],
            ),
            if (p.kind != PhaseKind.maintain) ...[
              Text('Pace ${_pace(p.kgPerWeek)}'),
              Slider(
                key: ValueKey('phase-$i-pace'),
                min: 0.1,
                max: 1,
                divisions: 18,
                value: p.kgPerWeek.abs().clamp(0.1, 1.0),
                label: p.kgPerWeek.abs().toStringAsFixed(2),
                semanticFormatterCallback: (v) =>
                    'Pace, ${_pace(p.kind == PhaseKind.cut ? -v : v)}',
                onChanged: (v) => _set(
                  i,
                  DietPhase(
                    kind: p.kind,
                    kgPerWeek: (p.kind == PhaseKind.cut ? -v : v),
                    weeks: p.weeks,
                    untilKg: p.untilKg,
                  ),
                ),
              ),
            ],
            if (from != null && p.kind != PhaseKind.maintain)
              Wrap(
                spacing: 6,
                children: [
                  ChoiceChip(
                    key: ValueKey('phase-$i-for-time'),
                    label: const Text('For a time'),
                    selected: until == null,
                    onSelected: (_) => _set(
                      i,
                      DietPhase(
                        kind: p.kind,
                        kgPerWeek: p.kgPerWeek,
                        weeks: p.weeks,
                      ),
                    ),
                  ),
                  ChoiceChip(
                    key: ValueKey('phase-$i-until'),
                    label: const Text('Until a weight'),
                    selected: until != null,
                    onSelected: (_) => _set(
                      i,
                      DietPhase(
                        kind: p.kind,
                        kgPerWeek: p.kgPerWeek,
                        weeks: p.weeks,
                        untilKg: _seed(from, p),
                      ),
                    ),
                  ),
                ],
              ),
            if (until != null && from != null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _short(_plan, i)
                          ? 'Until ${_weight(until)}: ${_weeks(p.weeks)}, '
                                'the longest a phase runs'
                          : 'Until ${_weight(until)}: about ${_weeks(p.weeks)}',
                    ),
                  ),
                  IconButton(
                    key: ValueKey('phase-$i-lighter'),
                    tooltip: 'Lighter',
                    icon: const Icon(Icons.remove_rounded),
                    onPressed: p.kgPerWeek > 0 && until - _stepKg <= from
                        ? null
                        : () => _until(i, _round(until) - _stepKg),
                  ),
                  IconButton(
                    key: ValueKey('phase-$i-heavier'),
                    tooltip: 'Heavier',
                    icon: const Icon(Icons.add_rounded),
                    onPressed: p.kgPerWeek < 0 && until + _stepKg >= from
                        ? null
                        : () => _until(i, _round(until) + _stepKg),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(child: Text(_weeks(p.weeks))),
                  IconButton(
                    key: ValueKey('phase-$i-shorter'),
                    tooltip: 'Shorter',
                    icon: const Icon(Icons.remove_rounded),
                    onPressed: p.weeks <= 1
                        ? null
                        : () => _set(
                            i,
                            DietPhase(
                              kind: p.kind,
                              kgPerWeek: p.kgPerWeek,
                              weeks: p.weeks - 1,
                            ),
                          ),
                  ),
                  IconButton(
                    key: ValueKey('phase-$i-longer'),
                    tooltip: 'Longer',
                    icon: const Icon(Icons.add_rounded),
                    onPressed: p.weeks >= 52
                        ? null
                        : () => _set(
                            i,
                            DietPhase(
                              kind: p.kind,
                              kgPerWeek: p.kgPerWeek,
                              weeks: p.weeks + 1,
                            ),
                          ),
                  ),
                ],
              ),
            Text(
              'Ends ${from == null ? '' : 'about '}'
              '${_date(_plan.startOf(i + 1))}'
              '${_aboutEnd(_plan, i, widget.unit)}',
              key: ValueKey('phase-$i-ends'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _ask(String title, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              key: const ValueKey('phases-confirm'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_changed,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      if (await _ask('Discard your changes?', 'Discard') && context.mounted) {
        _changed = false;
        Navigator.pop(context);
      }
    },
    child: _screen(context),
  );

  Widget _screen(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Diet phases'),
      actions: [
        if (widget.plan != null)
          TextButton(
            key: const ValueKey('phases-delete'),
            onPressed: () async {
              if (await _ask('Delete this plan?', 'Delete') &&
                  context.mounted) {
                _changed = false;
                Navigator.pop(context, (plan: null));
              }
            },
            child: const Text('Delete'),
          ),
        TextButton(
          key: const ValueKey('phases-save'),
          onPressed: () async {
            if (_startKg == null) {
              // Not for long: a read that hangs saves the plan by time.
              final kg = await _reading?.timeout(
                const Duration(seconds: 5),
                onTimeout: () => null,
              );
              _startKg ??= kg;
            }
            if (context.mounted) {
              _changed = false;
              Navigator.pop(context, (plan: _plan));
            }
          },
          child: const Text('Save'),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_rounded),
          title: Text('Starts ${_date(_start)}'),
          subtitle: Text(
            'Ends ${_date(_plan.end)}'
            '${_about(_plan.weightAt(_phases.length), widget.unit)}, '
            'then maintenance',
          ),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _start,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) {
              setState(() {
                _changed = true;
                _start = picked;
              });
            }
          },
        ),
        for (var i = 0; i < _phases.length; i++) _phase(i),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('phases-add'),
          onPressed: () => setState(() {
            _changed = true;
            _phases.add(
              const DietPhase(kind: PhaseKind.maintain, kgPerWeek: 0, weeks: 2),
            );
          }),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add a phase'),
        ),
      ],
    ),
  );
}
