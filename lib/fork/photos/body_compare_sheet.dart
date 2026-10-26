import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_weight_log_usecase.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/fork/photos/body_compare.dart';

/// What was logged around [date], from the app's stores.
Future<BodyDay> loadBodyDay(DateTime date) async {
  final day = DateTime(date.year, date.month, date.day);
  Future<T?> orNull<T>(Future<T?> Function() read) async {
    try {
      return await read();
    } catch (_) {
      return null;
    }
  }

  final tracked = locator<GetTrackedDayUsecase>();
  return BodyDay.of(
    day,
    weights:
        await orNull(() => locator<GetWeightLogUsecase>().getAllEntries()) ??
        const [],
    measurements: await orNull(() => MeasurementStore().all()) ?? const [],
    day: await orNull(() => tracked.getTrackedDay(day)),
    dayBefore: await orNull(
      () => tracked.getTrackedDay(DateTime(day.year, day.month, day.day - 1)),
    ),
  );
}

/// Where the request goes, as Settings names it.
String aiDestination(AiProvider provider) => switch (provider) {
  AiProvider.anthropic => 'Anthropic',
  AiProvider.openrouter => 'OpenRouter',
  AiProvider.openai => 'OpenAI',
  AiProvider.ownServer => 'your own server',
};

/// Asks before anything leaves the phone: both photos and [earlier]'s and
/// [later]'s figures go to [provider]. True to send.
Future<bool> confirmBodyCompare(
  BuildContext context, {
  required AiProvider provider,
  required BodyDay earlier,
  required BodyDay later,
}) async {
  final text = Theme.of(context).textTheme;
  Widget day(String name, BodyDay d) => Padding(
    padding: const EdgeInsets.only(top: Dimens.spacing8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$name, ${d.date.year}-${d.date.month.toString().padLeft(2, '0')}-'
          '${d.date.day.toString().padLeft(2, '0')}',
          style: text.titleSmall,
        ),
        if (d.lines.isEmpty) Text('Nothing logged', style: text.bodySmall),
        for (final line in d.lines) Text(line, style: text.bodySmall),
      ],
    ),
  );
  final send = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Compare with AI'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sends both photos, side by side, and these figures to '
              '${aiDestination(provider)}. It judges how your body '
              'composition changed and how sure it is.',
            ),
            day('Earlier', earlier),
            day('Later', later),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('body-compare-send'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Send'),
        ),
      ],
    ),
  );
  return send ?? false;
}

String _fatText(BodyChange c) => switch (c) {
  BodyChange.less => 'Less body fat',
  BodyChange.more => 'More body fat',
  BodyChange.same => 'Body fat looks the same',
  BodyChange.unclear => "Body fat: can't tell",
};

String _muscleText(BodyChange c) => switch (c) {
  BodyChange.more => 'More muscle',
  BodyChange.less => 'Less muscle',
  BodyChange.same => 'Muscle looks the same',
  BodyChange.unclear => "Muscle: can't tell",
};

/// The model's comparison: its verdicts, how sure it is, what differed in
/// the photos and what it saw.
Future<void> showBodyComparison(BuildContext context, BodyComparison result) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => BodyComparisonView(result: result),
    );

class BodyComparisonView extends StatelessWidget {
  final BodyComparison result;

  const BodyComparisonView({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = paletteOf(context);
    final muted = text.bodySmall?.copyWith(color: palette.textMuted);
    Widget condition(String label, String? value) => value == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: Dimens.spacing4),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '$label: ', style: text.labelLarge),
                  TextSpan(text: value),
                ],
              ),
            ),
          );
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: EdgeInsets.fromLTRB(
          Dimens.spacing20,
          0,
          Dimens.spacing20,
          Dimens.spacing32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Text('AI comparison', style: text.titleLarge),
          const SizedBox(height: Dimens.spacing12),
          Text(_fatText(result.fat), style: text.titleMedium),
          Text(_muscleText(result.muscle), style: text.titleMedium),
          const SizedBox(height: Dimens.spacing12),
          Semantics(
            label: 'Certainty ${result.certainty} percent',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Certainty ${result.certainty}%', style: text.labelLarge),
                const SizedBox(height: Dimens.spacing4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: result.certainty / 100,
                    minHeight: 6,
                    backgroundColor: palette.surfaceMuted,
                  ),
                ),
              ],
            ),
          ),
          if (result.summary case final summary?) ...[
            const SizedBox(height: Dimens.spacing12),
            Text(summary),
          ],
          const SizedBox(height: Dimens.spacing8),
          condition('Lighting', result.lighting),
          condition('Pose', result.pose),
          if (result.signs.isNotEmpty) ...[
            const SizedBox(height: Dimens.spacing12),
            Text('What it saw', style: text.labelLarge),
            for (final sign in result.signs) Text('• $sign'),
          ],
          const SizedBox(height: Dimens.spacing16),
          Text(
            "An AI's reading of two photos, not a measurement: light, "
            'pose and water change how a body looks.',
            style: muted,
          ),
        ],
      ),
    );
  }
}
