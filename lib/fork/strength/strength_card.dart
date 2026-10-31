import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_ui.dart'
    show refreshGoals;
import 'package:opennutritracker/fork/adaptive/goal_plan_card.dart'
    show savePace;
import 'package:opennutritracker/fork/strength/strength_signal.dart';
import 'package:opennutritracker/fork/strength/strength_suggestion.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';

const _answeredKey = 'strengthAnswered';

/// "-0.35 kg/week": a suggestion's step is finer than a weight change's text.
String _paceText(double kgPerWeek, BodyWeightUnit unit) {
  final kg = unit == BodyWeightUnit.kg;
  final shown = kg ? kgPerWeek : kgPerWeek * 2.20462;
  return '${shown > 0 ? '+' : ''}${shown.toStringAsFixed(2)} '
      '${kg ? 'kg' : 'lb'}/week';
}

/// Home's card for what Go Hevier reports about strength (seam S183, D29): a
/// calorie change to apply or put off. Nothing changes unless the user applies
/// it, and an Undo takes it back. Shows nothing while there is nothing to say.
class StrengthCard extends StatefulWidget {
  final BodyWeightUnit unit;
  final VoidCallback onApplied;

  /// Tests swap these.
  final Future<StrengthSignal?> Function() read;
  final Future<double> Function()? rate;
  final AdaptiveStore? store;
  final Future<bool> Function(double kgPerWeek, ProfileStamp startedOn) setPace;
  final Future<void> Function() refresh;

  const StrengthCard({
    super.key,
    required this.unit,
    required this.onApplied,
    this.read = readStrengthSignal,
    this.rate,
    this.store,
    this.setPace = savePace,
    this.refresh = refreshGoals,
  });

  @override
  State<StrengthCard> createState() => _StrengthCardState();
}

class _StrengthCardState extends State<StrengthCard> {
  AdaptiveStore get _store => widget.store ?? AdaptiveStore();
  StrengthSuggestion? _suggestion;
  StrengthSignal? _signal;
  DateTime? _readAt;
  bool _loading = false;
  bool _again = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(StrengthCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Home rebuilds after the app resumes or the profile (its goal) changes.
    _load();
  }

  Future<double> _currentRate() async =>
      await widget.rate?.call() ??
      goalRateKgPerWeek(await locator<GetUserUsecase>().getUserData());

  /// Go Hevier's report, asked for at most once a minute as Home rebuilds
  /// often, and asking can start its process.
  Future<StrengthSignal?> _currentSignal(DateTime now) async {
    final readAt = _readAt;
    if (readAt == null || now.difference(readAt).inSeconds >= 60) {
      _signal = await widget.read();
      _readAt = now;
    }
    return _signal;
  }

  /// One read at a time, and one more if Home rebuilt during it.
  Future<void> _load() async {
    if (_loading) {
      _again = true;
      return;
    }
    _loading = true;
    try {
      do {
        _again = false;
        final now = DateTime.now();
        final suggestion = suggestFromStrength(
          await _currentSignal(now),
          rate: await _currentRate(),
          now: now,
          answered: StrengthAnswered.decode(await _store.readKey(_answeredKey)),
        );
        if (!mounted) return;
        setState(() => _suggestion = suggestion);
      } while (_again);
    } catch (_) {
      // Home goes on without it; the next rebuild tries again.
    } finally {
      _loading = false;
    }
  }

  Future<void> _answered(StrengthSuggestion suggestion) async {
    setState(() => _suggestion = null);
    await _store.writeKey(
      _answeredKey,
      StrengthAnswered(suggestion.signal.key, DateTime.now()).encode(),
    );
  }

  /// [targetAfter] is a fixed target's text once applied, in the display unit.
  Future<void> _apply(StrengthSuggestion suggestion, String targetAfter) async {
    final messenger = ScaffoldMessenger.of(context);
    final startedOn = ProfileStamp.now();
    final Future<bool> Function() undo;
    final String done;
    final settings = AdaptiveStore.settings.value;
    if (settings.fixedTarget) {
      final before = settings.fixedKcal;
      final kcal = before + suggestion.kcalPerDay;
      done = 'Target is now $targetAfter.';
      await _store.save(settings.copyWith(fixedKcal: kcal));
      await widget.refresh();
      undo = () async {
        await _store.save(
          AdaptiveStore.settings.value.copyWith(fixedKcal: before),
        );
        await widget.refresh();
        return true;
      };
    } else {
      if (!await widget.setPace(suggestion.toRate, startedOn)) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Not changed: the profile changed.')),
        );
        return;
      }
      done = 'Pace is now ${_paceText(suggestion.toRate, widget.unit)}.';
      undo = () => widget.setPace(suggestion.fromRate, startedOn);
    }
    await _answered(suggestion);
    widget.onApplied();
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        // An action keeps a bar up until dismissed: this one goes.
        persist: false,
        content: Text(done),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            final undone = await undo();
            widget.onApplied();
            if (!undone) {
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Not undone: the profile changed.'),
                ),
              );
            }
          },
        ),
      ),
    );
  }

  /// What applying would do, in the terms of how the target is set.
  String _proposal(BuildContext context, StrengthSuggestion suggestion) {
    final kcal = energyText(context, suggestion.kcalPerDay.toDouble());
    final settings = AdaptiveStore.settings.value;
    if (settings.fixedTarget) {
      return settings.fixedMacros != null
          ? 'Your target comes from the macros you set: about $kcal more a day '
                'would be the change to make there.'
          : 'This raises your fixed target by $kcal a day, to '
                '${energyText(context, settings.fixedKcal + suggestion.kcalPerDay)}.';
    }
    final pace =
        'This moves your pace from '
        '${_paceText(suggestion.fromRate, widget.unit)} to '
        '${_paceText(suggestion.toRate, widget.unit)}, about $kcal more a day';
    return settings.adaptiveTarget
        ? '$pace. A check-in then updates your target.'
        : '$pace.';
  }

  @override
  Widget build(BuildContext context) {
    final suggestion = _suggestion;
    if (suggestion == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final settings = AdaptiveStore.settings.value;
    final canApply = !(settings.fixedTarget && settings.fixedMacros != null);
    final note = suggestion.trainedLess;
    final targetAfter = energyText(
      context,
      settings.fixedKcal + suggestion.kcalPerDay,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Strength from Go Hevier', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(suggestion.message),
            if (note != null) ...[const SizedBox(height: 8), Text(note)],
            const SizedBox(height: 8),
            Text(
              _proposal(context, suggestion),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                Semantics(
                  identifier: 'strength-not-now',
                  child: TextButton(
                    onPressed: () => _answered(suggestion),
                    child: const Text('Not now'),
                  ),
                ),
                if (canApply)
                  Semantics(
                    identifier: 'strength-apply',
                    child: FilledButton(
                      onPressed: () => _apply(suggestion, targetAfter),
                      child: const Text('Apply'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
