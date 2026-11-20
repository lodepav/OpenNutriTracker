import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';

import 'photo_review_harness.dart';

void main() {
  setUpReviewHarness('dish_name_row');

  setUp(() {
    reviewFoods
      ..clear()
      ..addAll({
        'plov': MealEntity(
          code: 'plov',
          name: 'Plov, chicken (chicken pilaf, pilau, palov)',
          url: null,
          mealQuantity: null,
          mealUnit: 'g',
          servingQuantity: null,
          servingUnit: null,
          servingSize: null,
          source: MealSourceEntity.custom,
          backendSource: 'fork_dishes',
          nutriments: MealNutrimentsEntity.empty(),
        ),
      });
  });

  testWidgets('a home dish\'s row shows its name without the other names', (
    tester,
  ) async {
    await openReview(tester);
    await readReviewPhoto(tester, const [
      ParsedMealItem(query: 'plov', quantity: 300, unit: 'g'),
    ]);
    expect(find.text('Plov, chicken'), findsOneWidget);
    expect(find.textContaining('pilaf'), findsNothing);
  });
}
