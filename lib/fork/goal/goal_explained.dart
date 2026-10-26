import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/kcal_goal_breakdown_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_ui.dart';
import 'package:opennutritracker/fork/adaptive/check_in_history.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Seam S134: "How your goal is calculated" after the canvas's picks:
/// A's card with today's goal, B's three numbered steps from what you burn
/// to today's goal, each with its math on demand, then A's rows to the
/// inputs, the full equations (upstream's page) and, while it sets the
/// goal, the adaptive check-ins.
class GoalExplainedBody extends StatelessWidget {
  final KcalGoalBreakdownEntity breakdown;

  /// S17's note on a fixed or adaptive target; not in onboarding.
  final bool showTargetNote;
  final VoidCallback onInputs;
  final VoidCallback onEquations;

  const GoalExplainedBody({
    super.key,
    required this.breakdown,
    required this.showTargetNote,
    required this.onInputs,
    required this.onEquations,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final b = breakdown;
    final settings = AdaptiveStore.settings.value;
    // With a fixed or adaptive target the formula is not today's goal;
    // S17's note above says what is.
    // A weekday shift moves today's goal off the formula's, too.
    final formulaIsGoal =
        !showTargetNote ||
        (!settings.fixedTarget &&
            !settings.adaptiveTarget &&
            settings.weekdayOffsets[DateTime.now().weekday - 1] == 0);
    final adjustment = b.effectiveAdjustmentKcal + b.manualKcalAdjustment;
    final rate = b.weeklyWeightGoalKg;
    final inputs = [
      '${b.age} y',
      '${b.heightCM.toStringAsFixed(0)} ${l10n.cmLabel}',
      '${b.weightKG.toStringAsFixed(1)} ${l10n.kgLabel}',
      b.palCategory.getName(context),
    ].join(' · ');
    return ListView(
      padding: const EdgeInsets.all(Dimens.spacing16),
      children: [
        if (showTargetNote) const AdaptiveGoalNote(),
        AppCard(
          padding: const EdgeInsets.all(Dimens.spacing16),
          child: _GoalTop(
            label: formulaIsGoal ? "Today's goal" : "The formula's goal",
            kcal: b.totalKcalGoal,
            caption: [
              b.goal.getName(context),
              if (rate != null)
                l10n.weeklyWeightGoalKgPerWeek(rate.toStringAsFixed(2)),
            ].join(' · '),
          ),
        ),
        const SizedBox(height: Dimens.spacing16),
        GoalStep(
          number: 1,
          title: 'What you burn',
          value: energyText(context, b.tdeeKcal),
          text:
              'From your age, height, weight and how active you are '
              '(activity level ${b.palValue.toStringAsFixed(2)}), by the '
              'IOM equations.',
          math: [
            _MathRow(
              l10n.kcalGoalInfoPalRowLabel,
              b.palValue.toStringAsFixed(2),
            ),
            if (b.paMaleFormula case final pa?)
              _MathRow(
                b.usesAveragedReference
                    ? '${l10n.kcalGoalInfoPaRowLabel} · ${l10n.kcalGoalInfoMaleReferenceLabel}'
                    : l10n.kcalGoalInfoPaRowLabel,
                pa.toStringAsFixed(2),
              ),
            if (b.paFemaleFormula case final pa?)
              _MathRow(
                b.usesAveragedReference
                    ? '${l10n.kcalGoalInfoPaRowLabel} · ${l10n.kcalGoalInfoFemaleReferenceLabel}'
                    : l10n.kcalGoalInfoPaRowLabel,
                pa.toStringAsFixed(2),
              ),
            _MathRow(
              l10n.kcalGoalInfoTdeeResultLabel,
              energyText(context, b.tdeeKcal),
              bold: true,
            ),
          ],
        ),
        GoalStep(
          number: 2,
          title: 'Your weight goal',
          value: signedEnergy(context, adjustment),
          text: rate != null
              ? '${b.goal.getName(context)}, '
                    '${l10n.weeklyWeightGoalKgPerWeek(rate.toStringAsFixed(2))}: '
                    'about ${usesKj(context) ? '32,200 kJ' : '7,700 kcal'} per kg, '
                    'spread over 7 days.'
              : '${b.goal.getName(context)}: a fixed daily adjustment.',
          math: [
            _MathRow(
              l10n.kcalGoalInfoBaseAdjustmentLabel,
              signedEnergy(context, b.baseAdjustmentKcal),
            ),
            if (b.taperChangedAdjustment) ...[
              _MathNote(l10n.kcalGoalInfoTaperNote),
              _MathRow(
                l10n.kcalGoalInfoAppliedAdjustmentLabel,
                signedEnergy(context, b.effectiveAdjustmentKcal),
              ),
            ],
            if (b.manualKcalAdjustment != 0)
              _MathRow(
                usesKj(context)
                    ? l10n.settingsKjAdjustmentLabel
                    : l10n.settingsKcalAdjustmentLabel,
                signedEnergy(context, b.manualKcalAdjustment),
              ),
          ],
        ),
        GoalStep(
          number: 3,
          title: 'Today',
          value: signedEnergy(context, b.activityKcal),
          text: 'Activity you logged today is added back.',
          last: true,
          math: [
            _MathNote(l10n.kcalGoalInfoActivityExplanation),
            _MathRow(l10n.activityLabel, signedEnergy(context, b.activityKcal)),
          ],
        ),
        const SizedBox(height: Dimens.spacing8),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                title: Text(l10n.kcalGoalInfoInputsSection),
                subtitle: Text(inputs),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: onInputs,
              ),
              ListTile(
                key: const Key('goal-equations'),
                title: const Text('The equations'),
                subtitle: const Text('IOM 2005, with each number filled in'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: onEquations,
              ),
              if (showTargetNote && settings.adaptiveTarget)
                ListTile(
                  title: const Text('Adaptive expenditure'),
                  subtitle: const Text('From your weigh-ins and logs'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          CheckInHistoryScreen(store: AdaptiveStore()),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// [kcal] with its sign, a true minus for what is taken away.
String signedEnergy(BuildContext context, double kcal) {
  final text = energyText(context, kcal.abs());
  return kcal < 0 ? '−$text' : '+$text';
}

class _GoalTop extends StatelessWidget {
  final String label;
  final double kcal;
  final String caption;

  const _GoalTop({
    required this.label,
    required this.kcal,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return MergeSemantics(
      child: Column(
        children: [
          Text(label, style: muted),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${energyValue(context, kcal)}',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(text: ' ${energyUnit(context)}', style: muted),
              ],
            ),
          ),
          Text(caption, style: muted, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// One numbered step: its number on a line down to the next, then a card
/// with what it is, its amount, a sentence on it and its math on demand.
class GoalStep extends StatefulWidget {
  final int number;
  final String title;
  final String value;
  final String text;
  final List<Widget> math;
  final bool last;

  const GoalStep({
    super.key,
    required this.number,
    required this.title,
    required this.value,
    required this.text,
    required this.math,
    this.last = false,
  });

  @override
  State<GoalStep> createState() => _GoalStepState();
}

class _GoalStepState extends State<GoalStep> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bold = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  child: Text(
                    '${widget.number}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: widget.last ? null : scheme.outlineVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Dimens.spacing12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: Dimens.spacing12),
              child: AppCard(
                padding: const EdgeInsets.fromLTRB(
                  Dimens.spacing16,
                  Dimens.spacing12,
                  Dimens.spacing16,
                  Dimens.spacing4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MergeSemantics(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              // The number is on the line beside (H8)
                              widget.title,
                              style: bold,
                            ),
                          ),
                          Text(widget.value, style: bold),
                        ],
                      ),
                    ),
                    const SizedBox(height: Dimens.spacing4),
                    Text(
                      widget.text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (_open) ...[
                      const SizedBox(height: Dimens.spacing8),
                      ...widget.math,
                    ],
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: () => setState(() => _open = !_open),
                      icon: Icon(
                        _open
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                      ),
                      label: Text(_open ? 'Hide the math' : 'Show the math'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MathRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _MathRow(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Dimens.spacing4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: Dimens.spacing8),
          Text(
            value,
            style: bold ? style?.copyWith(fontWeight: FontWeight.w700) : style,
          ),
        ],
      ),
    );
  }
}

class _MathNote extends StatelessWidget {
  final String text;

  const _MathNote(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Dimens.spacing4),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );
}
