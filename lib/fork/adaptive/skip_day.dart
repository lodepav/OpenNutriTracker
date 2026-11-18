import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/display/contrast.dart';

/// Seam S84: a Diary day can be left out of the expenditure estimate (D17),
/// for a day logged only in part: what was logged is not counted, the
/// weigh-in still is. The Day menu switches it ([skipDayItem]); while it is
/// on, the day says so ([SkipDayNote]).
bool isSkippedDay(DateTime day) =>
    AdaptiveStore.skipped.value.contains(_key(day));

DateTime _key(DateTime day) => DateTime(day.year, day.month, day.day);

/// Leaves [day] out, or counts it again when it is out.
Future<void> toggleSkippedDay(DateTime day, {AdaptiveStore? store}) =>
    (store ?? AdaptiveStore()).setSkipped(_key(day), !isSkippedDay(day));

/// The Day menu's "Leave out of expenditure", ticked while [day] is out,
/// its explanation under it.
PopupMenuEntry<T> skipDayItem<T>(BuildContext context, T value, DateTime day) {
  final skipped = isSkippedDay(day);
  // Only the adaptive target follows the estimate.
  final shapes = AdaptiveStore.settings.value.adaptiveTarget
      ? "won't shape your target"
      : "won't shape your expenditure estimate";
  return CheckedPopupMenuItem<T>(
    key: const ValueKey('skip-day'),
    value: value,
    checked: skipped,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Leave out of expenditure'),
        Text(
          skipped
              ? 'Not used in the expenditure estimate; its weigh-in is.'
              : 'Logged only in part? Its food $shapes; its weigh-in '
                    'still counts.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: paletteOf(context).textMuted),
        ),
      ],
    ),
  );
}

/// One line on a day left out of the estimate, so that is never hidden;
/// a tap counts the day again.
class SkipDayNote extends StatelessWidget {
  final DateTime day;
  final AdaptiveStore? store;

  const SkipDayNote({super.key, required this.day, this.store});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: AdaptiveStore.skipped,
    builder: (context, skipped, _) {
      if (!skipped.contains(_key(day))) return const SizedBox.shrink();
      final palette = paletteOf(context);
      return Semantics(
        identifier: 'skip-day-note',
        button: true,
        label: 'Left out of expenditure. Undo',
        onTap: () => toggleSkippedDay(day, store: store),
        excludeSemantics: true,
        child: InkWell(
          onTap: () => toggleSkippedDay(day, store: store),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Dimens.spacing20,
                vertical: Dimens.spacing12,
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Left out of expenditure · '),
                    TextSpan(
                      text: 'Undo',
                      style: TextStyle(
                        color: textAccent(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
              ),
            ),
          ),
        ),
      );
    },
  );
}
