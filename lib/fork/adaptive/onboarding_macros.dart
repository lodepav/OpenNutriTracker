import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/utils/calc/calorie_goal_calc.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/macro_program.dart';
import 'package:opennutritracker/fork/goal/onboarding_goal.dart';

/// Onboarding's protein and fat (seams S88, S89): chosen on the goal page,
/// held here, and written with the rest of onboarding when it completes,
/// as the page's other choices are.
abstract final class OnboardingMacros {
  static final pending = ValueNotifier<MacroProgram?>(null);

  /// The overview page's energy: a fixed target set on the goal page, or
  /// [user]'s at the pace of a goal planned there, which is what Start will
  /// set; else null for upstream's formula.
  static double? overviewKcal([UserEntity? user]) {
    final settings = AdaptiveStore.settings.value;
    if (settings.fixedTarget) return settings.fixedTargetKcal;
    final plan = OnboardingGoal.pending.value;
    if (plan == null || user == null) return null;
    return CalorieGoalCalc.getTdee(user) +
        CalorieGoalCalc.getKcalGoalAdjustment(
          user.goal,
          weeklyWeightGoalKg: plan.paceOn(DateTime.now()),
        );
  }

  /// The overview page's grams, as the app will set them: a fixed
  /// target's own grams, the program chosen at the target's energy, or
  /// upstream's [split] of [formulaKcal] scaled to a fixed target; null to
  /// keep upstream's.
  static FixedMacros? overview(
    UserEntity? user,
    double? formulaKcal, {
    FixedMacros? split,
  }) {
    final settings = AdaptiveStore.settings.value;
    if (settings.fixedTarget && settings.fixedMacros != null) {
      return settings.fixedMacros;
    }
    final kcal = overviewKcal(user) ?? formulaKcal;
    final program = pending.value;
    if (program != null && user != null && kcal != null) {
      return program.macrosFor(
        kcal: kcal,
        weightKg: user.weightKG,
        bodyFatPercent: bodyFatPercent(user),
      );
    }
    if (overviewKcal(user) case final fixed?
        when split != null && formulaKcal != null && formulaKcal > 0) {
      final f = fixed / formulaKcal;
      return FixedMacros(
        proteinG: split.proteinG * f,
        carbsG: split.carbsG * f,
        fatG: split.fatG * f,
      );
    }
    return null;
  }

  /// Into the active profile, which onboarding has just set up; nothing
  /// when none was chosen, so upstream's percentages stay.
  static Future<void> save([AdaptiveStore? store]) async {
    final program = pending.value;
    if (program == null) return;
    final target = store ?? AdaptiveStore();
    final settings = await target.read();
    await target.save(settings.copyWith(macroProgram: () => program));
    pending.value = null;
  }
}
