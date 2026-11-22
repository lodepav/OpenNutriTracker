import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/data/repository/favourite_meal_repository.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/edit_meal/presentation/bloc/edit_meal_bloc.dart';
import 'package:opennutritracker/features/edit_meal/presentation/edit_meal_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

// Seam S290: a food, new or edited, asks for the food's name, not a meal's.

class _Config extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      const ConfigEntity(true, true, false, AppThemeEntity.system);
}

class _ConfigRepository extends Fake implements ConfigRepository {
  @override
  Future<String?> getCustomMealFormMode() async =>
      CustomMealFormMode.simple.name;
}

class _Library extends Fake implements CustomMealDataSource {}

class _Favourites extends Fake implements FavouriteMealRepository {}

class _Intakes extends Fake implements IntakeRepository {}

class _NoCache extends Fake implements CacheManager {}

void main() {
  final getIt = GetIt.instance;

  setUp(() {
    getIt.registerFactory<EditMealBloc>(
      () => EditMealBloc(
        _Config(),
        _Library(),
        _ConfigRepository(),
        _Favourites(),
        _Intakes(),
      ),
    );
  });

  tearDown(() => getIt.reset());

  Future<void> pumpEditor(WidgetTester tester, MealEntity meal) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<EnergyUnitProvider>(
        create: (_) => EnergyUnitProvider(),
        child: MaterialApp(
          localizationsDelegates: const [S.delegate],
          supportedLocales: S.supportedLocales,
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            settings: RouteSettings(
              arguments: EditMealScreenArguments(
                DateTime(2026, 11, 21),
                meal,
                IntakeTypeEntity.lunch,
                false,
              ),
            ),
            builder: (_) => const EditMealScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a new custom food asks for its food name', (tester) async {
    await pumpEditor(tester, MealEntity.empty());

    expect(find.text('New custom food'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Food name'), findsOneWidget);
    expect(find.text('Meal name'), findsNothing);
  });

  // crit r4 g2: the pencil says "Edit food", so the page does too
  testWidgets('editing a food names it a food', (tester) async {
    getIt.registerSingleton<CacheManager>(_NoCache());
    await pumpEditor(
      tester,
      MealEntity(
        code: 'banana',
        name: 'Banana',
        url: null,
        mealQuantity: '100',
        mealUnit: 'g',
        servingQuantity: null,
        servingUnit: 'g',
        servingSize: null,
        nutriments: MealNutrimentsEntity.empty(),
        source: MealSourceEntity.off,
      ),
    );

    expect(find.text('Edit food'), findsOneWidget);
    expect(find.text('Edit meal'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Food name'), findsOneWidget);
    expect(find.text('Meal name'), findsNothing);
  });
}
