import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/repository/recipe_repository.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/profile_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_profiles_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/share_qr_dialog.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/home/domain/entity/shared_meal_payload.dart';
import 'package:opennutritracker/fork/copy/diary_selection.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../helpers/test_l10n.dart';

// 2.7.0's share a single food, on the Diary's selection bar.

final _day = DateTime(2026, 11, 9);

class _Recipes extends Fake implements RecipeRepository {}

class _Profiles extends Fake implements GetProfilesUsecase {
  final int count;

  _Profiles(this.count);

  @override
  List<ProfileEntity> getProfiles() => [
    for (var i = 0; i < count; i++)
      ProfileEntity(id: 'p$i', name: 'P$i', createdAt: _day, boxSuffix: '$i'),
  ];
}

IntakeEntity _intake(String name) => IntakeEntity(
  id: name,
  unit: 'g',
  amount: 100,
  type: IntakeTypeEntity.lunch,
  meal: MealEntity(
    code: name,
    name: name,
    url: null,
    mealQuantity: null,
    mealUnit: 'g',
    servingQuantity: null,
    servingUnit: null,
    servingSize: null,
    nutriments: MealNutrimentsEntity(
      energyKcal100: 100,
      carbohydrates100: 20,
      fat100: 10,
      proteins100: 5,
      sugars100: null,
      saturatedFat100: null,
      fiber100: null,
    ),
    source: MealSourceEntity.custom,
  ),
  dateTime: _day,
);

List<String?> _names(String code) => [
  for (final item in SharedMealPayload.fromJsonString(code).items) item.name,
];

Future<DiarySelection> _pump(
  WidgetTester tester,
  List<IntakeEntity> picked, {
  int profiles = 1,
}) async {
  locator
    ..registerSingleton<RecipeRepository>(_Recipes())
    ..registerSingleton<GetProfilesUsecase>(_Profiles(profiles));
  addTearDown(locator.reset);
  final selection = DiarySelection()..toggleAll(picked);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [S.delegate],
      supportedLocales: S.supportedLocales,
      home: Scaffold(
        bottomNavigationBar: DiarySelectionBar(
          selection: selection,
          day: _day,
          onDelete: (_, _) {},
          onEdit: (_, _) {},
        ),
      ),
    ),
  );
  return selection;
}

void main() {
  testWidgets('one food shares as a food, and the selection ends', (
    tester,
  ) async {
    final selection = await _pump(tester, [_intake('Rice')]);
    await tester.tap(find.byKey(const Key('fork-selection-share')));
    await tester.pumpAndSettle();

    final dialog = tester.widget<ShareQrDialog>(find.byType(ShareQrDialog));
    expect(dialog.title, l10nEn.shareFoodLabel);
    expect(dialog.fileBaseName, 'food_qr');
    expect(_names(dialog.code), ['Rice']);
    expect(dialog.onCopyToProfile, isNull);
    expect(selection.active, isFalse);
  });

  testWidgets('several foods share as a meal; another profile can take it', (
    tester,
  ) async {
    await _pump(tester, [_intake('Rice'), _intake('Beans')], profiles: 2);
    await tester.tap(find.byKey(const Key('fork-selection-share')));
    await tester.pumpAndSettle();

    final dialog = tester.widget<ShareQrDialog>(find.byType(ShareQrDialog));
    expect(dialog.title, l10nEn.shareMealLabel);
    expect(dialog.fileBaseName, 'meal_qr');
    expect(_names(dialog.code), ['Rice', 'Beans']);
    expect(dialog.onCopyToProfile, isNotNull);
  });
}
