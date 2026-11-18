import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/meal_type_suggester.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/copy/copy_entries.dart';
import 'package:opennutritracker/fork/copy/repeat_meal_card.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../fixture/meal_entity_fixtures.dart';

const _shares = {
  ConfigEntity.mealKeyBreakfast: 25,
  ConfigEntity.mealKeyLunch: 25,
  ConfigEntity.mealKeyDinner: 25,
  ConfigEntity.mealKeySnack: 25,
};

class _Config extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async => _Settings();
}

class _Settings extends Fake implements ConfigEntity {
  @override
  bool get usesImperialFoodUnits => false;
  @override
  Map<String, int> get mealKcalSharesPct => _shares;
}

class _Copier extends Fake implements CopyEntries {
  final List<IntakeEntity> yesterday;
  final asked = <DateTime>[];
  final placed = <(List<IntakeEntity>, IntakeTypeEntity?)>[];

  _Copier(this.yesterday);

  @override
  Future<List<IntakeEntity>> intakesOf(DateTime day) async {
    asked.add(day);
    return yesterday;
  }

  @override
  Future<Placed?> placeIntakes(
    List<IntakeEntity> intakes,
    CopyMoment moment, {
    IntakeTypeEntity? type,
    DateTime? movedFrom,
  }) async {
    placed.add((intakes, type));
    return (day: DateTime(2026, 11, 1), written: intakes);
  }
}

/// What a history import writes for a day's totals.
MealEntity _totals(String code) => MealEntity(
  code: code,
  name: 'Day logged in MacroFactor',
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: 'g',
  servingSize: null,
  nutriments: MealNutrimentsEntity.empty(),
  source: MealSourceEntity.custom,
);

IntakeEntity _intake(String id, IntakeTypeEntity type, {String? code}) =>
    IntakeEntity(
      id: id,
      unit: 'g',
      amount: 100,
      type: type,
      meal: code == null ? MealEntityFixtures.mealOne : _totals(code),
      dateTime: DateTime(2026, 10, 31, 12),
    );

/// A meal other than [meal].
IntakeTypeEntity _other(IntakeTypeEntity meal) =>
    IntakeTypeEntity.values[(meal.index + 1) % 4];

void main() {
  final meal = MealTypeSuggester.suggestFromTime(
    DateTime.now(),
    mealSharesPct: _shares,
  );

  setUp(() => GetIt.instance.registerSingleton<GetConfigUsecase>(_Config()));
  tearDown(GetIt.instance.reset);

  Future<void> pump(
    WidgetTester tester,
    _Copier copier, {
    List<IntakeEntity> today = const [],
    DateTime? day,
    Stream<Object?>? homeLoads,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: RepeatMealCard(
            day: day ?? DateTime(2026, 11, 1),
            today: today,
            copier: copier,
            homeLoads: homeLoads,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final log = find.byKey(const ValueKey('home-repeat-meal-log'));

  testWidgets('offers yesterday\'s meal of this time and logs only that', (
    tester,
  ) async {
    final same = _intake('a', meal);
    final copier = _Copier([same, _intake('b', _other(meal))]);
    await pump(tester, copier);

    expect(copier.asked.first, DateTime(2026, 10, 31));
    expect(find.textContaining('as yesterday'), findsOneWidget);
    expect(find.textContaining('1 food'), findsOneWidget);
    // Home's one card surface (AppCard), as its other sections
    expect(find.byType(AppCard), findsOneWidget);
    expect(find.byType(Card), findsNothing);

    await tester.tap(log);
    await tester.pumpAndSettle();
    expect(copier.placed.single.$1, [same]);
    expect(copier.placed.single.$2, meal);
    expect(find.text('Undo'), findsOneWidget);
  });

  testWidgets('a rebuild of Home reads yesterday once; a Home load or a new '
      'day reads it again', (tester) async {
    final copier = _Copier([_intake('a', meal)]);
    final loads = StreamController<Object?>.broadcast();
    addTearDown(loads.close);
    await pump(tester, copier, homeLoads: loads.stream);
    // the same figures, as a drag on Home rebuilds it
    await pump(tester, copier, today: [], homeLoads: loads.stream);
    expect(copier.asked, hasLength(1));

    // Yesterday may have changed on the Diary.
    loads.add(null);
    await tester.pumpAndSettle();
    expect(copier.asked, hasLength(2));

    await pump(
      tester,
      copier,
      day: DateTime(2026, 11, 2),
      homeLoads: loads.stream,
    );
    expect(copier.asked.last, DateTime(2026, 11, 1));
  });

  testWidgets('not once something is logged to that meal today', (
    tester,
  ) async {
    await pump(
      tester,
      _Copier([_intake('a', meal)]),
      today: [_intake('t', meal)],
    );
    expect(log, findsNothing);
  });

  testWidgets('another meal logged today does not hide it', (tester) async {
    await pump(
      tester,
      _Copier([_intake('a', meal)]),
      today: [_intake('t', _other(meal))],
    );
    expect(log, findsOneWidget);
  });

  testWidgets('never a day\'s imported totals, as if they were a food', (
    tester,
  ) async {
    await pump(tester, _Copier([_intake('h', meal, code: 'history-day')]));
    expect(log, findsNothing);
  });

  testWidgets('not when yesterday had nothing for that meal', (tester) async {
    await pump(tester, _Copier([_intake('a', _other(meal))]));
    expect(log, findsNothing);
  });
}
