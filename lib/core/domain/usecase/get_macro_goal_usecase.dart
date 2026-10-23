import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/utils/calc/macro_calc.dart';
// [fork] S41 fixed-macros: the fixed target's grams replace the percentages
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
// [/fork]

class GetMacroGoalUsecase {
  final ConfigRepository _configRepository;
  // [fork] S41 fixed-macros: another profile's store; null reads the active
  final AdaptiveStore? _forkAdaptive;
  // [/fork]

  GetMacroGoalUsecase(
    this._configRepository, [
    // [fork] S41 fixed-macros
    this._forkAdaptive,
    // [/fork]
  ]);

  Future<double> getCarbsGoal(double totalCalorieGoal) async {
    // [fork] S41 fixed-macros
    final fixed = await forkMacroGoal(totalCalorieGoal, _forkAdaptive);
    if (fixed != null) return fixed.carbsG;
    // [/fork]
    final config = await _configRepository.getConfig();
    final userCarbGoal = config.userCarbGoalPct;

    return MacroCalc.getTotalCarbsGoal(
      totalCalorieGoal,
      userCarbsGoal: userCarbGoal,
    );
  }

  Future<double> getFatsGoal(double totalCalorieGoal) async {
    // [fork] S41 fixed-macros
    final fixed = await forkMacroGoal(totalCalorieGoal, _forkAdaptive);
    if (fixed != null) return fixed.fatG;
    // [/fork]
    final config = await _configRepository.getConfig();
    final userFatGoal = config.userFatGoalPct;

    return MacroCalc.getTotalFatsGoal(
      totalCalorieGoal,
      userFatsGoal: userFatGoal,
    );
  }

  Future<double> getProteinsGoal(double totalCalorieGoal) async {
    // [fork] S41 fixed-macros
    final fixed = await forkMacroGoal(totalCalorieGoal, _forkAdaptive);
    if (fixed != null) return fixed.proteinG;
    // [/fork]
    final config = await _configRepository.getConfig();
    final userProteinGoal = config.userProteinGoalPct;

    return MacroCalc.getTotalProteinsGoal(
      totalCalorieGoal,
      userProteinsGoal: userProteinGoal,
    );
  }
}
