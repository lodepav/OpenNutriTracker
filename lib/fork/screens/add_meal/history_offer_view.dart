import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/fork/dish/dish_strings.dart';

/// [day] as the offer says it: "today", "yesterday", or a short weekday,
/// day and month in the app's locale ("Tue 4 Nov"); [date] when the last.
({String text, bool date}) historyDayText(
  BuildContext context,
  DateTime day,
  DateTime now,
) {
  final that = DateUtils.dateOnly(day);
  final today = DateUtils.dateOnly(now);
  if (that == today) return (text: DishStrings.today, date: false);
  if (that == DateTime(today.year, today.month, today.day - 1)) {
    return (text: DishStrings.yesterday, date: false);
  }
  final locale = Localizations.maybeLocaleOf(context)?.toString() ?? 'en';
  String format(String locale) => DateFormat.MMMEd(locale).format(that);
  try {
    return (text: format(locale), date: true);
  } catch (_) {
    return (text: format('en'), date: true);
  }
}

/// On a photo's meal card, above its Size: the user's own amounts from a
/// meal like this one that they corrected, to use with one tap; once used,
/// where they came from and a way back.
class HistoryOfferView extends StatelessWidget {
  /// The day of the meal the amounts are from, and its slot ("dinner").
  final DateTime day;
  final String slot;

  /// The meal's energy with the amounts used, formatted.
  final String energy;
  final bool taken;
  final VoidCallback onUse;
  final VoidCallback onUndo;

  /// Today, for "today" and "yesterday"; the clock's by default.
  final DateTime? now;

  const HistoryOfferView({
    super.key,
    required this.day,
    required this.slot,
    required this.energy,
    required this.taken,
    required this.onUse,
    required this.onUndo,
    this.now,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = paletteOf(context);
    final when = historyDayText(context, day, now ?? DateTime.now());
    if (taken) {
      return Semantics(
        container: true,
        child: Row(
          key: const ValueKey('bulk-add-history-taken'),
          children: [
            Expanded(
              child: Text(
                DishStrings.historyUsing(when.text),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: palette.textStrong,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              identifier: 'bulk-add-history-undo',
              child: TextButton(
                key: const ValueKey('bulk-add-history-undo'),
                onPressed: onUndo,
                child: const Text(DishStrings.historyUndo),
              ),
            ),
          ],
        ),
      );
    }
    return Semantics(
      container: true,
      child: Column(
        key: const ValueKey('bulk-add-history-offer'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DishStrings.historyLike(slot, when.text, date: when.date),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: palette.textStrong,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            DishStrings.historyAmounts(energy),
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Semantics(
            identifier: 'bulk-add-history-use',
            child: FilledButton.tonal(
              key: const ValueKey('bulk-add-history-use'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(48, 48),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              onPressed: onUse,
              child: const Text(
                DishStrings.historyUse,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
