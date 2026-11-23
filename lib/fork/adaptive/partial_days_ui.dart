import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';

/// The check-in's question on days that look partly logged (D65): each is
/// left out of the estimate or counted as a full day. Nothing while there is
/// none.
class PartialDaysCard extends StatelessWidget {
  final List<PartialDay> days;

  /// Automatic check-ins wait for the answer, which the card says.
  final bool heldBack;

  /// While an answer is saved, the buttons are off.
  final bool saving;
  final void Function(DateTime day) onLeaveOut;
  final void Function(DateTime day) onKeep;

  const PartialDaysCard({
    super.key,
    required this.days,
    required this.heldBack,
    this.saving = false,
    required this.onLeaveOut,
    required this.onKeep,
  });

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppCard(
        key: const ValueKey('partial-days'),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Logged only in part?',
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${days.length == 1 ? 'This day is' : 'These days are'} far '
              'under what you usually log, which would lower your target'
              '${heldBack ? '; the check-in waits for your answer' : ''}.',
              style: theme.textTheme.bodySmall,
            ),
            for (final day in days) ...[
              const SizedBox(height: 12),
              Text(
                '${DateFormat.MMMEd(locale).format(day.date)}: '
                '${energyText(context, day.kcal)}, usually about '
                '${energyText(context, day.usualKcal)}',
              ),
              // A Wrap: the two buttons stack at large text.
              Wrap(
                spacing: 8,
                children: [
                  Semantics(
                    identifier: 'partial-day-leave-out-${_id(day.date)}',
                    child: TextButton(
                      onPressed: saving ? null : () => onLeaveOut(day.date),
                      // the date said after the name: the pairs repeat
                      child: Text(
                        'Leave out',
                        semanticsLabel:
                            'Leave out, ${DateFormat.MMMd(locale).format(day.date)}',
                      ),
                    ),
                  ),
                  Semantics(
                    identifier: 'partial-day-keep-${_id(day.date)}',
                    child: TextButton(
                      onPressed: saving ? null : () => onKeep(day.date),
                      child: Text(
                        'Count as full day',
                        semanticsLabel:
                            'Count as full day, '
                            '${DateFormat.MMMd(locale).format(day.date)}',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _id(DateTime day) => DateFormat('yyyy-MM-dd').format(day);
}
