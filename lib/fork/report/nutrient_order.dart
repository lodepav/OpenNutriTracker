import 'package:opennutritracker/features/diary/presentation/widgets/daily_nutrient_panel.dart';
import 'package:opennutritracker/fork/report/nutrient_explorer.dart';

/// The one order the nutrient goals overview, the goals editor and the
/// Nutrients visibility list show the nutrients in. It is the editor's, which
/// upstream's tests reach by row index.
const nutrientOrder = <String>[
  NutrientPanelKeys.fiber,
  NutrientPanelKeys.saturatedFat,
  NutrientPanelKeys.sugar,
  NutrientPanelKeys.sodium,
  NutrientPanelKeys.calcium,
  NutrientPanelKeys.iron,
  NutrientPanelKeys.potassium,
  NutrientPanelKeys.magnesium,
  NutrientPanelKeys.vitaminD,
  NutrientPanelKeys.vitaminB12,
];

/// [n]'s place in [nutrientOrder]; one not in it goes last.
int nutrientRank(ExplorerNutrient n) {
  // Sugars and saturated fat have no DRI row, so no driKey.
  final key =
      n.driKey ??
      switch (n.label) {
        'Sugars' => NutrientPanelKeys.sugar,
        'Saturated fat' => NutrientPanelKeys.saturatedFat,
        _ => null,
      };
  final i = key == null ? -1 : nutrientOrder.indexOf(key);
  return i < 0 ? nutrientOrder.length : i;
}
