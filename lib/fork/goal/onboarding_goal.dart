import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/onboarding/domain/entity/user_goal_selection_entity.dart';
import 'package:opennutritracker/features/onboarding/presentation/bloc/onboarding_bloc.dart';
import 'package:opennutritracker/fork/goal/goal_actions.dart';
import 'package:opennutritracker/fork/goal/goal_planner.dart';
import 'package:opennutritracker/fork/goal/phase_colors.dart';
import 'package:opennutritracker/fork/goal/planner_screen.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/units/weight_text.dart';

/// Onboarding's goal (seams S88, S89): planned on the goal page, held
/// here, and started once onboarding has saved the profile.
abstract final class OnboardingGoal {
  static final pending = ValueNotifier<PhasePlan?>(null);

  /// Starts the plan in the active profile, which onboarding has just set
  /// up; nothing when none was planned.
  static Future<void> save([GoalActions? actions]) async {
    final plan = pending.value;
    if (plan == null) return;
    await (actions ?? GoalActions()).start(plan);
    pending.value = null;
  }

  /// Upstream's goal choice for [kind].
  static UserGoalSelectionEntity choiceFor(PhaseKind kind) => switch (kind) {
    PhaseKind.cut => UserGoalSelectionEntity.loseWeight,
    PhaseKind.maintain => UserGoalSelectionEntity.maintainWeight,
    PhaseKind.bulk => UserGoalSelectionEntity.gainWeigh,
  };
}

/// The goal page's row: the plan made, or the planner to make one: the
/// goal, pace, expenditure, calorie target and macros in one walk.
/// [onPlanned] selects upstream's goal to match the plan.
class OnboardingPlanRow extends StatelessWidget {
  final ValueChanged<UserGoalSelectionEntity> onPlanned;

  const OnboardingPlanRow({super.key, required this.onPlanned});

  Future<void> _open(BuildContext context) async {
    final bloc = locator<OnboardingBloc>();
    final selection = bloc.userSelection;
    // The planner reads the measurements as a profile; any goal will do.
    final chosen = selection.goal;
    selection.goal ??= UserGoalSelectionEntity.maintainWeight;
    final user = selection.toUserEntity();
    selection.goal = chosen;
    if (user == null) return;
    final setup = PlannerSetup.ofUser(
      user,
      selection.bodyWeightUnit,
      onboarding: true,
    );
    final pending = OnboardingGoal.pending.value;
    final draft = pending != null
        ? GoalDraft.of(pending, setup.nowKg)
        : GoalDraft.fresh(
            setup.nowKg,
            DateTime.now(),
            targetKg: setup.targetKg,
          );
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GoalPlannerScreen(
          setup: setup,
          draft: draft,
          onStart: (plan) async {
            OnboardingGoal.pending.value = plan;
            selection.targetWeight = plan.targetKg ?? selection.targetWeight;
            onPlanned(OnboardingGoal.choiceFor(plan.kind));
            return true;
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unit = locator.isRegistered<OnboardingBloc>()
        ? locator<OnboardingBloc>().userSelection.bodyWeightUnit
        : null;
    return ValueListenableBuilder(
      valueListenable: OnboardingGoal.pending,
      builder: (context, plan, _) {
        final target = plan?.targetKg;
        return Semantics(
          identifier: 'onboarding-plan-goal',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: plan == null
                ? const Icon(Icons.flag_rounded)
                : Icon(
                    Icons.flag_rounded,
                    color: phaseColor(context, plan.kind),
                  ),
            title: Text(plan == null ? 'Plan your goal' : 'Your plan'),
            subtitle: Text(
              plan == null
                  ? 'The pace, what you burn, the calorie target and macros, '
                        'a screen each.'
                  : '${plan.kind.label}'
                        '${target == null || unit == null ? '' : ' to ${weightText(target, unit)}'}'
                        ' · until ${intl.DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag()).format(plan.end)}',
            ),
            trailing: Icon(
              plan == null ? Icons.chevron_right_rounded : Icons.edit_rounded,
            ),
            onTap: () => _open(context),
          ),
        );
      },
    );
  }
}
