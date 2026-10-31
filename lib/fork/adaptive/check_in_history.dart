import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/goal/phase_colors.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';

/// The weekly check-ins as accepted, newest first: the target each set,
/// how far it moved from the one before, and the expenditure and proposal
/// it came from.
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
                'No check-ins yet. The first comes a week after the '
                'adaptive target is turned on.',
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: AppCard(
        child: ListTile(
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
          trailing: change == null ? null : _changeChip(context, change),
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
