import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
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
          children: [
            for (var i = all.length - 1; i >= 0; i--)
              _row(context, all[i], i == 0 ? null : all[i - 1]),
          ],
        );
      },
    ),
  );

  Widget _row(BuildContext context, CheckInRecord r, CheckInRecord? before) {
    final change = before == null ? null : r.acceptedKcal - before.acceptedKcal;
    final edited = (r.acceptedKcal - r.proposedKcal).abs() >= 1;
    return ListTile(
      key: ValueKey('check-in-${DateFormat('yyyy-MM-dd').format(r.date)}'),
      title: Text(
        '${DateFormat('d MMM yyyy').format(r.date)}: '
        '${energyText(context, r.acceptedKcal)}',
      ),
      subtitle: Text(
        [
          'Expenditure ${energyText(context, r.expenditureKcal)}',
          if (edited) 'proposed ${energyText(context, r.proposedKcal)}',
        ].join(' · '),
      ),
      trailing: change == null
          ? null
          : Text(
              change.round() == 0
                  ? 'no change'
                  : energyText(context, change, signed: true),
            ),
    );
  }
}
