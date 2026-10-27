import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/onboarding/presentation/bloc/onboarding_bloc.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_ui.dart';
import 'package:opennutritracker/fork/adaptive/expenditure_settings_ui.dart';
import 'package:opennutritracker/fork/adaptive/macro_program.dart';
import 'package:opennutritracker/fork/adaptive/macro_program_ui.dart';

/// Onboarding's protein and fat (seams S88, S89): chosen on the goal page,
/// held here, and written with the rest of onboarding when it completes,
/// as the page's other choices are.
abstract final class OnboardingMacros {
  static final pending = ValueNotifier<MacroProgram?>(null);

  /// The overview page's energy: a fixed target set on the goal page, or
  /// null for upstream's formula.
  static double? overviewKcal() {
    final settings = AdaptiveStore.settings.value;
    return settings.fixedTarget ? settings.fixedTargetKcal : null;
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
    final kcal = overviewKcal() ?? formulaKcal;
    final program = pending.value;
    if (program != null && user != null && kcal != null) {
      return program.macrosFor(
        kcal: kcal,
        weightKg: user.weightKG,
        bodyFatPercent: bodyFatPercent(user),
      );
    }
    if (overviewKcal() case final fixed?
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

/// The goal page's row: what is chosen, and the Macros dialog to change it.
class OnboardingMacrosRow extends StatelessWidget {
  const OnboardingMacrosRow({super.key});

  @override
  Widget build(BuildContext context) {
    // As chosen on the measurements page.
    final perLb =
        locator.isRegistered<OnboardingBloc>() &&
        locator<OnboardingBloc>().userSelection.bodyWeightUnit ==
            BodyWeightUnit.lb;
    return ValueListenableBuilder(
      valueListenable: OnboardingMacros.pending,
      builder: (context, program, _) => ListTile(
        key: const ValueKey('onboarding-macros'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Protein and fat'),
        subtitle: Text(
          program?.summary(perLb: perLb) ??
              'The usual percentages. Or set protein and fat per '
                  '${perLb ? 'lb' : 'kg'}; the '
                  'rest is carbs.',
        ),
        trailing: const Icon(Icons.edit_rounded),
        onTap: () async {
          final edited = await showDialog<({MacroProgram? program})>(
            context: context,
            builder: (_) => MacroProgramDialog(program, perLb: perLb),
          );
          if (edited != null) OnboardingMacros.pending.value = edited.program;
        },
      ),
    );
  }
}

/// The goal page's row for the calorie target (formula, adaptive or
/// fixed), expenditure and check-ins and the weekday shift: the dialog
/// Settings opens, saved to the profile being set up.
class OnboardingTargetRow extends StatelessWidget {
  const OnboardingTargetRow({super.key});

  @override
  Widget build(BuildContext context) {
    final perLb =
        locator.isRegistered<OnboardingBloc>() &&
        locator<OnboardingBloc>().userSelection.bodyWeightUnit ==
            BodyWeightUnit.lb;
    return ValueListenableBuilder(
      valueListenable: AdaptiveStore.settings,
      builder: (context, settings, _) => ListTile(
        key: const ValueKey('onboarding-target'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Calorie target and expenditure'),
        subtitle: Text(
          '${targetSummary(settings)} · ${expenditureSummary(settings)}',
        ),
        trailing: const Icon(Icons.edit_rounded),
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => AdaptiveSettingsDialog(
            AdaptiveStore(),
            perLb: perLb,
            showMacros: false,
          ),
        ),
      ),
    );
  }
}
