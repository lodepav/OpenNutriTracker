// Fork cases moved out of test/features/edit_meal/presentation/edit_meal_save_previous_meal_test.dart (they test the fork's changes).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
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

import '../../../../../helpers/test_l10n.dart';

/// Editing a custom meal hands the library the meal as it was before the
/// edit, so the save replaces that entry even when the edit changed what the
/// meal is found by — its barcode, or its name when it has none (#1403).
/// `custom_meal_data_source_test.dart` covers what the library does with it.
void main() {
  final getIt = GetIt.instance;
  late _RecordingCustomMealDataSource dataSource;
  late _RecordingIntakeRepository intakeRepository;

  setUp(() {
    dataSource = _RecordingCustomMealDataSource();
    intakeRepository = _RecordingIntakeRepository();
    getIt.registerFactory<EditMealBloc>(
      () => EditMealBloc(
        _FakeGetConfigUsecase(),
        dataSource,
        _FakeConfigRepository(),
        _FakeFavouriteMealRepository(),
        intakeRepository,
      ),
    );
  });

  tearDown(() async {
    await getIt.reset();
  });

  MealEntity customMeal({required String? code, required String name}) =>
      MealEntity(
        code: code,
        name: name,
        url: null,
        mealQuantity: '100',
        mealUnit: 'gml',
        servingQuantity: 100,
        servingUnit: 'gml',
        servingSize: '',
        nutriments: const MealNutrimentsEntity(
          energyKcal100: 370,
          carbohydrates100: 60,
          fat100: 7,
          proteins100: 13,
          sugars100: null,
          saturatedFat100: null,
          fiber100: null,
        ),
        source: MealSourceEntity.custom,
      );

  /// Opens the editor the way the custom meal list does (`editOnly`).
  Future<void> pumpEditor(WidgetTester tester, MealEntity meal) async {
    dataSource.library.add(MealDBO.fromMealEntity(meal));
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<EnergyUnitProvider>(
        create: (_) => EnergyUnitProvider(),
        child: MaterialApp(
          localizationsDelegates: const [S.delegate],
          supportedLocales: S.supportedLocales,
          onGenerateInitialRoutes: (_) => [
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('custom meals')),
            ),
            MaterialPageRoute<void>(
              settings: RouteSettings(
                arguments: EditMealScreenArguments(
                  DateTime(2026, 10, 18),
                  meal,
                  IntakeTypeEntity.breakfast,
                  false,
                  editOnly: true,
                ),
              ),
              builder: (_) => const EditMealScreen(),
            ),
          ],
          // Without a route factory MaterialApp builds no Navigator at all.
          onGenerateRoute: (_) => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, l10nEn.buttonSaveLabel));
    await tester.pumpAndSettle();
  }

  // the label card's "Per" is the form's mode
  testWidgets('per 100 g opens the label rows, and the rarer ones save too', (
    tester,
  ) async {
    await pumpEditor(tester, customMeal(code: 'uuid-oats', name: 'Oats'));
    expect(find.text('Per serving'), findsOneWidget);
    expect(find.text('Saturated fat'), findsNothing);

    await tester.tap(find.text('Per serving'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Per 100').last);
    await tester.pumpAndSettle();
    expect(find.text('Saturated fat'), findsOneWidget);
    expect(find.text('Calcium'), findsNothing);

    Finder field(String name) => find.descendant(
      of: find.ancestor(of: find.text(name), matching: find.byType(Row)).first,
      matching: find.byType(TextField),
    );
    await tester.enterText(field('Saturated fat'), '2');
    await tester.tap(find.byKey(const Key('facts-more')));
    await tester.pumpAndSettle();
    await tester.enterText(field('Calcium'), '120');
    await save(tester);

    expect(dataSource.saves, hasLength(1));
    final saved = dataSource.saves.single.$1.nutriments;
    expect(saved.saturatedFat100, 2);
    expect(saved.calcium100, 120);
    expect(saved.carbohydrates100, 60);
  });

  testWidgets('Back asks once typed in; Cancel stays, Discard leaves', (
    tester,
  ) async {
    await pumpEditor(tester, customMeal(code: 'uuid-oats', name: 'Oats'));
    await tester.enterText(
      find.widgetWithText(TextFormField, l10nEn.mealNameLabel),
      'Oats, rolled',
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text(l10nEn.discardChangesTitle), findsOneWidget);

    await tester.tap(find.text(l10nEn.dialogCancelLabel));
    await tester.pumpAndSettle();
    expect(find.text('custom meals'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10nEn.discardChangesConfirmLabel));
    await tester.pumpAndSettle();
    expect(find.text('custom meals'), findsOneWidget);
    expect(dataSource.saves, isEmpty);
  });

  testWidgets('Back does not ask once the text is as it was', (tester) async {
    await pumpEditor(tester, customMeal(code: 'uuid-oats', name: 'Oats'));
    await tester.enterText(
      find.widgetWithText(TextFormField, l10nEn.mealNameLabel),
      'Oats, rolled',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, l10nEn.mealNameLabel),
      'Oats',
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text(l10nEn.discardChangesTitle), findsNothing);
    expect(find.text('custom meals'), findsOneWidget);
    expect(dataSource.saves, isEmpty);
  });
}

class _RecordingCustomMealDataSource implements CustomMealDataSource {
  final saves = <(MealDBO, MealDBO?)>[];
  final library = <MealDBO>[];

  @override
  List<MealDBO> getAllCustomMeals() => library;

  /// When set, every save waits for it, standing in for a slow disk write.
  Completer<void>? gate;

  @override
  Future<void> saveCustomMeal(MealDBO mealDBO, {MealDBO? previous}) async {
    saves.add((mealDBO, previous));
    await gate?.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _RecordingIntakeRepository implements IntakeRepository {
  final moves = <(String, MealDBO)>[];

  @override
  Future<int> moveCustomMealInEveryProfile({
    required String fromMealKey,
    required MealDBO toMeal,
  }) async {
    moves.add((fromMealKey, toMeal));
    return 0;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeGetConfigUsecase implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      const ConfigEntity(true, true, false, AppThemeEntity.system);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeConfigRepository implements ConfigRepository {
  @override
  Future<String?> getCustomMealFormMode() async =>
      CustomMealFormMode.simple.name;

  // the test switches the mode
  @override
  Future<void> setCustomMealFormMode(String mode) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

/// #1307 moves a favourite along with the edit; nothing is starred here.
class _FakeFavouriteMealRepository implements FavouriteMealRepository {
  @override
  Future<void> moveFavourite(MealEntity previous, MealEntity updated) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}
