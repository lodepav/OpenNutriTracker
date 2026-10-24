import 'package:flutter/material.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';

/// Seam S84: on a Diary day with entries, leaves the day out of the
/// expenditure estimate (D17), for a day logged only in part: what was
/// logged is not counted, the weigh-in still is.
class SkipDayTile extends StatelessWidget {
  final DateTime day;
  final AdaptiveStore? store;

  const SkipDayTile({super.key, required this.day, this.store});

  @override
  Widget build(BuildContext context) {
    final store = this.store ?? AdaptiveStore();
    final key = DateTime(day.year, day.month, day.day);
    return ValueListenableBuilder(
      valueListenable: AdaptiveStore.skipped,
      builder: (context, days, _) {
        final skipped = days.contains(key);
        return Semantics(
          identifier: 'skip-day',
          container: true,
          child: SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: const Text('Leave out of expenditure'),
            subtitle: Text(
              skipped
                  ? 'Not used in the expenditure estimate; its weigh-in is.'
                  : "Logged only in part? Its food won't shape your target; "
                        'its weigh-in still counts.',
            ),
            value: skipped,
            onChanged: (v) => store.setSkipped(key, v),
          ),
        );
      },
    );
  }
}
