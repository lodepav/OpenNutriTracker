import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/onboarding/domain/entity/user_activity_selection_entity.dart';
import 'package:opennutritracker/generated/l10n.dart';
// [fork] S592 S593 fork English for stale strings
import 'package:opennutritracker/fork/onboarding/onboarding_copy.dart'
    as fork_copy;
// [/fork]

class OnboardingActivityPageBody extends StatefulWidget {
  final Function(bool active, UserActivitySelectionEntity? selectedActivity)
  setButtonContent;
  final UserActivitySelectionEntity? initialActivity;

  const OnboardingActivityPageBody({
    super.key,
    required this.setButtonContent,
    this.initialActivity,
  });

  @override
  State<OnboardingActivityPageBody> createState() =>
      _OnboardingActivityPageBodyState();
}

class _OnboardingActivityPageBodyState
    extends State<OnboardingActivityPageBody> {
  late UserActivitySelectionEntity? _selected = widget.initialActivity;

  /// Identifier suffixes are pinned to the values the UI drivers already
  /// use ('low' and 'very', not the enum's own names), so the redesign
  /// doesn't break tools/adb/walk-onboarding.sh.
  static const _identifierSuffix = {
    UserActivitySelectionEntity.sedentary: 'sedentary',
    UserActivitySelectionEntity.lowActive: 'low',
    UserActivitySelectionEntity.active: 'active',
    UserActivitySelectionEntity.veryActive: 'very',
  };

  String _title(UserActivitySelectionEntity activity) {
    switch (activity) {
      case UserActivitySelectionEntity.sedentary:
        return S.of(context).palSedentaryLabel;
      case UserActivitySelectionEntity.lowActive:
        // [fork] S592 pal-labels: sentence case, as the app's other labels
        // return S.of(context).palLowLActiveLabel;
        return fork_copy.palLowActiveLabel;
        // [/fork]
      case UserActivitySelectionEntity.active:
        return S.of(context).palActiveLabel;
      case UserActivitySelectionEntity.veryActive:
        // [fork] S592 pal-labels
        // return S.of(context).palVeryActiveLabel;
        return fork_copy.palVeryActiveLabel;
        // [/fork]
    }
  }

  String _description(UserActivitySelectionEntity activity) {
    switch (activity) {
      // [fork] S593 pal-examples: "e.g." on two of four; one form for all
      // case UserActivitySelectionEntity.sedentary:
      //   return S.of(context).palSedentaryDescriptionLabel;
      // case UserActivitySelectionEntity.lowActive:
      //   return S.of(context).palLowActiveDescriptionLabel;
      // case UserActivitySelectionEntity.active:
      //   return S.of(context).palActiveDescriptionLabel;
      // case UserActivitySelectionEntity.veryActive:
      //   return S.of(context).palVeryActiveDescriptionLabel;
      case UserActivitySelectionEntity.sedentary:
        return fork_copy.palSedentaryDescription;
      case UserActivitySelectionEntity.lowActive:
        return fork_copy.palLowActiveDescription;
      case UserActivitySelectionEntity.active:
        return fork_copy.palActiveDescription;
      case UserActivitySelectionEntity.veryActive:
        return fork_copy.palVeryActiveDescription;
      // [/fork]
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // [fork] S464 step-headings: a heading TalkBack can jump to
            Semantics(
              header: true,
              child:
            // [/fork]
            Text(
              S.of(context).activityLabel,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            ), // [fork] S464
            Text(
              S.of(context).onboardingActivityQuestionSubtitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: Dimens.spacing16),
            for (final activity in UserActivitySelectionEntity.values) ...[
              _buildActivityCard(activity),
              const SizedBox(height: Dimens.spacing12),
            ],
          ],
        ),
      ),
    );
  }

  /// One full-width choice per activity level, each carrying its own
  /// description. The descriptions used to sit behind a '?' icon beside a
  /// chip, a tap away from the choice they inform.
  Widget _buildActivityCard(UserActivitySelectionEntity activity) {
    final isSelected = _selected == activity;
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      identifier: 'onboarding-activity-${_identifierSuffix[activity]}',
      // [fork] S465 activity-checked: TalkBack says which level is chosen
      inMutuallyExclusiveGroup: true,
      checked: isSelected,
      // [/fork]
      child: AppCard(
        onTap: () => _onSelected(activity),
        color: isSelected ? colors.primaryContainer : null,
        padding: const EdgeInsets.all(Dimens.spacing16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title(activity),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: isSelected ? colors.onPrimaryContainer : null,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: Dimens.spacing4),
                  Text(
                    _description(activity),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isSelected
                          ? colors.onPrimaryContainer
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Dimens.spacing12),
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              // [fork] S335 activity-radio: outline read 1.3:1 on the card
              color: isSelected
                  ? colors.onPrimaryContainer
                  : colors.onSurfaceVariant,
              // color: isSelected ? colors.onPrimaryContainer : colors.outline,
              // [/fork]
            ),
          ],
        ),
      ),
    );
  }

  void _onSelected(UserActivitySelectionEntity activity) {
    setState(() => _selected = activity);
    widget.setButtonContent(true, activity);
  }
}
