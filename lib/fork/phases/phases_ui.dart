import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/fork/phases/phases.dart';

String _date(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _pace(double kgPerWeek) => kgPerWeek == 0
    ? 'at maintenance'
    : '${kgPerWeek > 0 ? '+' : ''}${kgPerWeek.toStringAsFixed(2)} kg a week';

/// Calendar days from [from] to [to], whatever the clock changes between.
int _daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

String _phaseText(DietPhase p) =>
    '${p.kind.label}, ${p.weeks} week${p.weeks == 1 ? '' : 's'} '
    '${_pace(p.kgPerWeek)}';

/// Seam S40: diet phases on Trends, the running one and what follows,
/// and the editor.
class DietPhasesCard extends StatefulWidget {
  final PhaseStore? store;
  final DateTime Function() clock;

  const DietPhasesCard({super.key, this.store, this.clock = DateTime.now});

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

  Future<void> _edit(PhasePlan? plan) async {
    final edited = await Navigator.of(context).push<({PhasePlan? plan})>(
      MaterialPageRoute(
        builder: (_) => PhasePlanScreen(plan: plan, today: widget.clock()),
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
              Text('Ended ${_date(plan.end)}; at maintenance since.')
            else ...[
              Text(
                'Now: ${_phaseText(plan.phases[index])}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                'Week ${_daysBetween(plan.startOf(index), now) ~/ 7 + 1} '
                'of ${plan.phases[index].weeks}, until '
                '${_date(plan.startOf(index + 1))}',
              ),
            ],
            const SizedBox(height: Dimens.spacing8),
            for (final (i, p) in plan.phases.indexed)
              if (i > index)
                Text(
                  '${_date(plan.startOf(i))}: ${_phaseText(p)}',
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

  const PhasePlanScreen({super.key, this.plan, required this.today});

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

  void _set(int i, DietPhase phase) => setState(() => _phases[i] = phase);

  Widget _phase(int i) {
    final p = _phases[i];
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
                      : () => setState(() => _phases.removeAt(i)),
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
                onChanged: (v) => _set(
                  i,
                  DietPhase(
                    kind: p.kind,
                    kgPerWeek: (p.kind == PhaseKind.cut ? -v : v),
                    weeks: p.weeks,
                  ),
                ),
              ),
            ],
            Row(
              children: [
                Expanded(child: Text('${p.weeks} weeks')),
                IconButton(
                  key: ValueKey('phase-$i-shorter'),
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
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Diet phases'),
      actions: [
        if (widget.plan != null)
          TextButton(
            key: const ValueKey('phases-delete'),
            onPressed: () => Navigator.pop(context, (plan: null)),
            child: const Text('Delete'),
          ),
        TextButton(
          key: const ValueKey('phases-save'),
          onPressed: () => Navigator.pop(context, (
            plan: PhasePlan(start: _start, phases: List.of(_phases)),
          )),
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
            'Ends ${_date(PhasePlan(start: _start, phases: _phases).end)}, '
            'then maintenance',
          ),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _start,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) setState(() => _start = picked);
          },
        ),
        for (var i = 0; i < _phases.length; i++) _phase(i),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('phases-add'),
          onPressed: () => setState(
            () => _phases.add(
              const DietPhase(kind: PhaseKind.maintain, kgPerWeek: 0, weeks: 2),
            ),
          ),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add a phase'),
        ),
      ],
    ),
  );
}
