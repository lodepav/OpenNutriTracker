// One nutrient order for the goals overview, the editor and the Nutrients
// list (the 2026-11-21 round 2 G6 critique, ngoals.png, ngedit.png, nvis.png).
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/diary/presentation/widgets/daily_nutrient_panel.dart';
import 'package:opennutritracker/fork/report/nutrient_explorer.dart';
import 'package:opennutritracker/fork/report/nutrient_order.dart';

void main() {
  test('the order holds every nutrient of upstream\'s panel once', () {
    expect(nutrientOrder.toSet(), NutrientPanelKeys.all.toSet());
    expect(nutrientOrder, hasLength(NutrientPanelKeys.all.length));
  });

  test('every nutrient with a goal of its own has a place in it', () {
    for (final n in explorerNutrients.where((n) => n.marksMiss)) {
      expect(nutrientRank(n), lessThan(nutrientOrder.length), reason: n.label);
    }
    final energy = explorerNutrients.first;
    expect(nutrientRank(energy), nutrientOrder.length);
  });
}
