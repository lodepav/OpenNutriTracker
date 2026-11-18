import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/goal/phase_colors.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';
import 'package:opennutritracker/fork/units/weight_text.dart';

/// What moved the target from [before] to [now], in parts that add up to
/// the change: the estimate, the counted activity, the user's edits, and
/// the rest, which the goal's pace or the plan made (its energy is not
/// stored). Null when either record is older than its goal and basis.
List<({String label, double kcal})>? checkInChangeParts(
  CheckInRecord before,
  CheckInRecord now,
) {
  if (before.goalRateKgPerWeek == null || before.basis == null) return null;
  if (now.goalRateKgPerWeek == null || now.basis == null) return null;
  final total = now.acceptedKcal - before.acceptedKcal;
  final estimate = now.baseKcal - before.baseKcal;
  final activity = now.activityKcal - before.activityKcal;
  // Under 1 kcal is the accepted target's rounding, not an edit.
  double edit(CheckInRecord r) {
    final by = r.acceptedKcal - r.proposedKcal;
    return by.abs() >= 1 ? by : 0;
  }

  final edited = edit(now) - edit(before);
  return [
    (label: 'Your estimate moved', kcal: estimate),
    (label: 'Counted activity', kcal: activity),
    (label: 'You edited it', kcal: edited),
    (
      label: "Goal's pace or the plan",
      kcal: total - estimate - activity - edited,
    ),
  ];
}

/// The weekly check-ins as accepted, newest first: the target each set,
/// how far it moved from the one before, and the expenditure and proposal
/// it came from. A row whose move can be split opens the split.
class CheckInHistoryScreen extends StatelessWidget {
  final AdaptiveStore store;

  const CheckInHistoryScreen({super.key, required this.store});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Check-in history')),
    body: FutureBuilder<List<CheckInRecord>>(
      future: store.history(),
      builder: (context, snapshot) {
        final all = snapshot.data;
        if (all == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (all.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No check-ins yet. The first is ready on Home once the '
                'adaptive target is on.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.only(top: 12),
          children: [
            for (var i = all.length - 1; i >= 0; i--)
              _row(context, all[i], i == 0 ? null : all[i - 1]),
          ],
        );
      },
    ),
  );

  Widget _row(BuildContext context, CheckInRecord r, CheckInRecord? before) {
    final theme = Theme.of(context);
    final change = before == null ? null : r.acceptedKcal - before.acceptedKcal;
    final edited = (r.acceptedKcal - r.proposedKcal).abs() >= 1;
    final parts = before == null ? null : checkInChangeParts(before, r);
    final tile = ListTile(
      key: ValueKey('check-in-${DateFormat('yyyy-MM-dd').format(r.date)}'),
      title: Text(
        energyText(context, r.acceptedKcal),
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        [
          DateFormat('d MMM yyyy').format(r.date),
          'expenditure ${energyText(context, r.expenditureKcal)}',
          if (edited) 'proposed ${energyText(context, r.proposedKcal)}',
        ].join(' · '),
      ),
      trailing: change == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _changeChip(context, change),
                if (parts != null) const Icon(Icons.chevron_right),
              ],
            ),
      onTap: parts == null
          ? null
          : () => _showParts(context, before!, r, parts),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: AppCard(
        child: parts == null
            ? tile
            : MergeSemantics(
                child: Semantics(hint: 'Shows why it moved', child: tile),
              ),
      ),
    );
  }

  /// The move from the check-in before: down in the cut's orange, up in
  /// the bulk's blue, none plain.
  Widget _changeChip(BuildContext context, double change) {
    final none = change.round() == 0;
    final color = none
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : phaseColor(context, change < 0 ? PhaseKind.cut : PhaseKind.bulk);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        none ? 'no change' : energyText(context, change, signed: true),
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Not registered in the tests that don't set one.
Future<BodyWeightUnit> _weightUnit() async {
  if (!locator.isRegistered<GetConfigUsecase>()) return BodyWeightUnit.kg;
  return (await locator<GetConfigUsecase>().getConfig()).bodyWeightUnit;
}

/// [kgPerWeek] signed, to the quarter kilo a pace is set in.
String _pace(double kgPerWeek, BodyWeightUnit unit) {
  final v = unit == BodyWeightUnit.kg ? kgPerWeek : kgPerWeek * 2.20462;
  final text = v.toStringAsFixed(2);
  final trimmed = text.endsWith('0') ? v.toStringAsFixed(1) : text;
  return '${v > 0 ? '+' : ''}$trimmed';
}

Future<void> _showParts(
  BuildContext context,
  CheckInRecord before,
  CheckInRecord now,
  List<({String label, double kcal})> parts,
) async {
  final unit = await _weightUnit();
  if (!context.mounted) return;
  final rate = before.goalRateKgPerWeek!, nowRate = now.goalRateKgPerWeek!;
  final from = before.targetWeightKg, to = now.targetWeightKg;
  final notes = [
    if ((rate - nowRate).abs() > 0.001)
      'Pace went from ${_pace(rate, unit)} to ${_pace(nowRate, unit)} '
          '${unit == BodyWeightUnit.kg ? 'kg' : 'lb'} a week.',
    if ((from == null) != (to == null) ||
        from != null && (from - to!).abs() > 0.05)
      from != null && to != null
          ? 'Target weight went from ${weightText(from, unit)} to '
                '${weightText(to, unit)}.'
          : 'The target weight changed.',
    if (before.basis != now.basis)
      'How activity or a kg is counted changed in Settings.',
  ];
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) {
      final text = Theme.of(context).textTheme;
      Widget line(String label, String value, {TextStyle? style}) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: MergeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(label, style: style)),
              const SizedBox(width: 12),
              Text(value, style: style),
            ],
          ),
        ),
      );
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Why it moved from ${DateFormat('d MMM').format(before.date)}',
                style: text.titleMedium,
              ),
              for (final p in parts)
                if (energyValue(context, p.kcal) != 0)
                  line(
                    p.label,
                    energyText(context, p.kcal, signed: true),
                    style: text.bodyMedium,
                  ),
              line(
                'In all',
                energyText(
                  context,
                  now.acceptedKcal - before.acceptedKcal,
                  signed: true,
                ),
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              for (final n in notes)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(n, style: text.bodySmall),
                ),
            ],
          ),
        ),
      );
    },
  );
}
