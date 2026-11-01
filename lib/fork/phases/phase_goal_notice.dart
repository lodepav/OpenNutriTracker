import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';

/// Seam S193: says on Home that the goal moved by itself, from what to what,
/// until dismissed. [onShown] as one appears: Home read the old goal if it
/// loaded before the phase was applied.
class PhaseGoalNoticeCard extends StatefulWidget {
  final VoidCallback onShown;
  final PhaseStore? store;

  const PhaseGoalNoticeCard({super.key, required this.onShown, this.store});

  @override
  State<PhaseGoalNoticeCard> createState() => _PhaseGoalNoticeCardState();
}

class _PhaseGoalNoticeCardState extends State<PhaseGoalNoticeCard> {
  void _changed() {
    if (PhaseStore.goalNotice.value != null) widget.onShown();
  }

  @override
  void initState() {
    super.initState();
    PhaseStore.goalNotice.addListener(_changed);
  }

  @override
  void dispose() {
    PhaseStore.goalNotice.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: PhaseStore.goalNotice,
    builder: (context, notice, _) {
      if (notice == null) return const SizedBox.shrink();
      final text = Theme.of(context).textTheme;
      return AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(notice.title, style: text.titleMedium),
                  Text(
                    'Your daily goal went from '
                    '${energyText(context, notice.fromKcal)} to '
                    '${energyText(context, notice.toKcal)}.',
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              icon: const Icon(Icons.close),
              onPressed: () =>
                  (widget.store ?? PhaseStore()).dismissGoalNotice(),
            ),
          ],
        ),
      );
    },
  );
}
