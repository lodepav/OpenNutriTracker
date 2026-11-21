import 'package:flutter/material.dart';
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
import 'package:opennutritracker/features/edit_meal/presentation/bloc/edit_meal_bloc.dart';
import 'package:opennutritracker/features/edit_meal/presentation/edit_meal_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

// S426: the editor's Scaffold reaches under the system bars, so they take its
// colour. S428: a name without a letter is an error on the field itself.

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

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    tester.view.padding = const FakeViewPadding(top: 63, bottom: 126);
    tester.view.viewPadding = const FakeViewPadding(top: 63, bottom: 126);
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
                MealEntity.empty(),
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

  testWidgets('the editor reaches under the status and navigation bars', (
    tester,
  ) async {
    await pump(tester);
    final scaffold = tester.getRect(find.byType(Scaffold).first);
    expect(scaffold.top, 0);
    expect(scaffold.bottom, 2340 / 2.625);
  });

  testWidgets('a name without a letter is an error on the Food name field', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.widgetWithText(TextFormField, 'Food name'), '123');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final field = find.widgetWithText(TextFormField, 'Food name');
    expect(
      find.descendant(
        of: field,
        matching: find.text('Food name must contain at least one letter'),
      ),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);

    await tester.enterText(field, '123 apples');
    await tester.pump();
    expect(find.text('Food name must contain at least one letter'), findsNothing);
  });
}
