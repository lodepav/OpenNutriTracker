import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_photo_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_text_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/dish/break_down_dish_usecase.dart';
import 'package:opennutritracker/fork/dish/dish_breakdown_controller.dart';
import 'package:opennutritracker/fork/dish/dish_breakdown_rows.dart';
import 'package:opennutritracker/fork/dish/dish_group.dart';
import 'package:opennutritracker/fork/dish/dish_recipe.dart';

MealEntity _meal(
  String name, [
  MealSourceEntity source = MealSourceEntity.fdc,
]) => MealEntity(
  code: name,
  name: name,
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: 'g',
  servingSize: null,
  nutriments: MealNutrimentsEntity.empty(),
  source: source,
);

/// Finds what the table holds: only the ingredients, never the dish.
class _Resolver implements ResolveParsedMealsUseCase {
  static const table = {
    'cheese, sulguni',
    'wheat flour, white',
    'egg, whole, raw',
  };

  @override
  Future<List<ResolvedMealItem>> resolve(
    List<ParsedMealItem> items, {
    bool fromPhoto = false,
  }) async => [
    for (final item in items)
      table.contains(item.query)
          ? ResolvedMealItem(
              parsed: item,
              candidates: [_meal(item.query)],
              selectedIndex: 0,
              confidence: 1,
            )
          : ResolvedMealItem(
              parsed: item,
              candidates: const [],
              selectedIndex: 0,
              confidence: 0,
            ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ModelReader implements ReadMealTextUseCase {
  @override
  Future<MealTextReading> read(String input, {String? localeCode}) async =>
      const MealTextReading(
        MealTextParseResult(
          items: [
            ParsedMealItem(query: 'khachapuri', quantity: 1),
            ParsedMealItem(query: 'egg, whole, raw', quantity: 2),
          ],
          errors: [],
        ),
        usedModel: true,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GramsReader implements ReadMealTextUseCase {
  @override
  Future<MealTextReading> read(String input, {String? localeCode}) async =>
      const MealTextReading(
        MealTextParseResult(
          items: [ParsedMealItem(query: 'borscht', quantity: 500, unit: 'g')],
          errors: [],
        ),
        usedModel: true,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PhotoReader implements ReadMealPhotoUseCase {
  @override
  Future<MealPhotoReadResult> read(
    MealPhoto photo, {
    String? localeCode,
    String? note,
  }) async => const MealPhotoRead(
    MealTextParseResult(
      items: [ParsedMealItem(query: 'pelmeni', quantity: 14)],
      errors: [],
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late BulkAddBloc bloc;
  late List<String> asked;
  late List<(String?, MealPhoto?)> sent;

  Future<DishBreakdown?> breakDown(
    String dish, {
    String? amount,
    MealPhoto? photo,
  }) async {
    asked.add(dish);
    sent.add((amount, photo));
    return DishBreakdown(
      dish,
      await _Resolver().resolve(const [
        ParsedMealItem(query: 'wheat flour, white', quantity: 120, unit: 'g'),
        ParsedMealItem(query: 'cheese, sulguni', quantity: 80.5, unit: 'g'),
      ]),
    );
  }

  setUp(() {
    asked = [];
    sent = [];
    bloc = BulkAddBloc(_Resolver(), _ModelReader(), _PhotoReader());
  });
  tearDown(() => bloc.close());

  Future<BulkAddLoadedState> settle() async {
    await pumpEventQueue();
    return bloc.state as BulkAddLoadedState;
  }

  test('a dish the model named and nothing matched is broken down once, '
      'in place, at the model\'s grams', () async {
    final controller = DishBreakdownController(
      bloc,
      breakDown: breakDown,
      modelConfigured: () async => true,
    );
    bloc.add(const ParseBulkTextEvent(text: 'x', usesImperialUnits: false));
    final state = await settle();

    expect(asked, ['khachapuri']);
    expect(
      [for (final r in state.rows) (r.meal?.name, r.amountText, r.unit)],
      [
        ('wheat flour, white', '120', 'g'),
        ('cheese, sulguni', '80.5', 'g'),
        ('egg, whole, raw', '2', 'g/ml'),
      ],
    );
    expect(state.rows[0].dishIngredient?.dish, 'khachapuri');
    expect(
      state.rows[0].dishIngredient?.group,
      same(state.rows[1].dishIngredient?.group),
    );
    expect(state.rows[2].dishIngredient, isNull);
    controller.dispose();
  });

  test('a row skipped while it is broken down stays one skipped row', () async {
    final gate = Completer<void>();
    final controller = DishBreakdownController(
      bloc,
      breakDown: (dish, {amount, photo}) async {
        await gate.future;
        return breakDown(dish);
      },
      modelConfigured: () async => true,
    );
    bloc.add(const ParseBulkTextEvent(text: 'x', usesImperialUnits: false));
    await settle();
    bloc.add(const ToggleRowSkippedEvent(0));
    await settle();
    gate.complete();
    final state = await settle();

    expect(state.rows, hasLength(2));
    expect(state.rows[0].skipped, isTrue);
    expect(state.rows[0].dishIngredient, isNull);
    expect(state.rows[0].willBeLogged, isFalse);
    controller.dispose();
  });

  test('a row edited while it is broken down keeps the edit', () async {
    final gate = Completer<void>();
    final controller = DishBreakdownController(
      bloc,
      breakDown: (dish, {amount, photo}) async {
        await gate.future;
        return breakDown(dish);
      },
      modelConfigured: () async => true,
    );
    bloc.add(const ParseBulkTextEvent(text: 'x', usesImperialUnits: false));
    await settle();
    bloc.add(const ChangeRowAmountEvent(0, '200'));
    await settle();
    gate.complete();
    final state = await settle();

    expect(state.rows[0].amountText, '200');
    expect(state.rows[0].dishIngredient, isNull);
    controller.dispose();
  });

  group('a dish', () {
    Future<(List<BulkAddRow>, Object)> dishOf(
      List<ParsedMealItem> ingredients, {
      ReadMealTextUseCase? reader,
    }) async {
      final dishBloc = BulkAddBloc(
        _Resolver(),
        reader ?? _ModelReader(),
        _PhotoReader(),
      );
      addTearDown(dishBloc.close);
      final controller = DishBreakdownController(
        dishBloc,
        breakDown: (dish, {amount, photo}) async =>
            DishBreakdown(dish, await _Resolver().resolve(ingredients)),
        modelConfigured: () async => true,
      );
      addTearDown(controller.dispose);
      dishBloc.add(
        const ParseBulkTextEvent(text: 'x', usesImperialUnits: false),
      );
      await pumpEventQueue();
      await pumpEventQueue();
      final rows = (dishBloc.state as BulkAddLoadedState).rows;
      return (rows, rows[0].dishIngredient!.group);
    }

    const flour = 'wheat flour, white';
    const cheese = 'cheese, sulguni';

    test('logged has a code of its own, so two are two foods', () async {
      final (rows, group) = await dishOf(const [
        ParsedMealItem(query: flour, quantity: 100, unit: 'g'),
      ]);
      final first = dishMeal(rows, group)!.code;
      expect(first, isNotEmpty);
      expect(dishMeal(rows, group)!.code, isNot(first));
    });

    test('a liquid in ml counts toward the weight it was stated at', () async {
      final (rows, group) = await dishOf(const [
        ParsedMealItem(query: flour, quantity: 100, unit: 'g'),
        ParsedMealItem(query: cheese, quantity: 300, unit: 'ml'),
      ], reader: _GramsReader());
      final members = dishMembers(rows, group);
      expect(dishPortion(rows, members), closeTo(500, 1e-9));
      final amounts = scaledAmounts(rows, portionBase(rows, members), 500)!;
      expect(amounts[members[0]], '100');
      expect(amounts[members[1]], '300');
    });

    test('a pinch scaled down stays above 0', () async {
      final (rows, group) = await dishOf(const [
        ParsedMealItem(query: flour, quantity: 1, unit: 'g'),
        ParsedMealItem(query: cheese, quantity: 349, unit: 'g'),
      ]);
      final members = dishMembers(rows, group);
      final amounts = scaledAmounts(rows, portionBase(rows, members), 100)!;
      expect(amounts[members[0]], '0.29');
      expect(amounts[members[1]], '100');
    });
  });

  test('a stated count goes with the breakdown, and its recipe has as many '
      'servings', () async {
    final photo = MealPhoto(bytes: Uint8List(1), mediaType: 'image/webp');
    final controller = DishBreakdownController(
      bloc,
      breakDown: breakDown,
      modelConfigured: () async => true,
      photo: () => photo,
    );
    bloc.add(const ParseBulkTextEvent(text: 'x', usesImperialUnits: false));
    await settle();
    // A typed read: the photo stays home.
    expect(sent, [('1', null)]);

    bloc.add(ReadMealPhotoEvent(photo: photo, usesImperialUnits: false));
    final state = await settle();
    expect(sent.last.$1, '14');
    expect(sent.last.$2, same(photo));
    final group = state.rows.first.dishIngredient!.group;
    expect(recipeFromDishGroup(state.rows, group)!.servingsCount, 14);
    controller.dispose();
  });

  test('an edit keeps the row an ingredient of its dish', () async {
    final controller = DishBreakdownController(
      bloc,
      breakDown: breakDown,
      modelConfigured: () async => true,
    );
    bloc.add(const ParseBulkTextEvent(text: 'x', usesImperialUnits: false));
    await settle();
    bloc.add(const ChangeRowAmountEvent(0, '150'));
    final state = await settle();

    expect(state.rows[0].amountText, '150');
    expect(state.rows[0].dishIngredient?.dish, 'khachapuri');
    controller.dispose();
  });

  test('no model: nothing is broken down and nothing is offered', () async {
    final controller = DishBreakdownController(
      bloc,
      breakDown: breakDown,
      modelConfigured: () async => false,
    );
    bloc.add(const ParseBulkTextEvent(text: 'x', usesImperialUnits: false));
    final state = await settle();

    expect(asked, isEmpty);
    expect(state.rows.map(controller.canBreakDown), [false, false]);
    controller.dispose();
  });

  test('offered on an unmatched row, not on a confident match or an '
      'ingredient', () async {
    final controller = DishBreakdownController(
      bloc,
      breakDown: (dish, {amount, photo}) async => null,
      modelConfigured: () async => true,
    );
    bloc.add(const ParseBulkTextEvent(text: 'x', usesImperialUnits: false));
    final state = await settle();

    expect(state.rows.map(controller.canBreakDown), [true, false]);
    controller.dispose();
  });

  test('a product matched with confidence is not offered; a weak match '
      'is', () async {
    final controller = DishBreakdownController(
      bloc,
      breakDown: (dish, {amount, photo}) async => null,
      modelConfigured: () async => true,
    );
    await pumpEventQueue();
    BulkAddRow row(double confidence) => BulkAddRow(
      resolved: ResolvedMealItem(
        parsed: const ParsedMealItem(query: 'mozzarella'),
        candidates: [
          _meal('whole milk mozzarella cheese', MealSourceEntity.off),
        ],
        selectedIndex: 0,
        confidence: confidence,
      ),
      selectedIndex: 0,
      amountText: '100',
      unit: 'g',
      fromPhoto: false,
    );

    expect(controller.canBreakDown(row(1)), isFalse);
    expect(controller.canBreakDown(row(0.1)), isTrue);
    controller.dispose();
  });

  test('a failed call leaves the row and reports it', () async {
    final controller = DishBreakdownController(
      bloc,
      breakDown: (dish, {amount, photo}) async =>
          throw const MealInterpreterException('down'),
      modelConfigured: () async => true,
    );
    bloc.add(const ParseBulkTextEvent(text: 'x', usesImperialUnits: false));
    final state = await settle();

    expect(state.rows.first.resolved.parsed.query, 'khachapuri');
    expect(
      await controller.breakDown(state.rows.first),
      DishBreakdownOutcome.failed,
    );
    controller.dispose();
  });

  test('the group saves as an unsaved one-serving recipe, as edited', () async {
    final controller = DishBreakdownController(
      bloc,
      breakDown: breakDown,
      modelConfigured: () async => true,
    );
    bloc.add(const ParseBulkTextEvent(text: 'x', usesImperialUnits: false));
    var state = await settle();
    expect(
      [
        for (var i = 0; i < state.rows.length; i++)
          isFirstOfDishGroup(state.rows, i),
      ],
      [true, false, false],
    );
    final group = state.rows.first.dishIngredient!.group;

    final recipe = recipeFromDishGroup(state.rows, group)!;
    expect(recipe.id, isEmpty, reason: 'the builder saves it as new');
    expect(recipe.name, 'Khachapuri');
    expect(recipe.servingsCount, 1);
    expect(
      [
        for (final i in recipe.ingredients)
          (i.snapshotMeal.name, i.convertedAmountG),
      ],
      [('wheat flour, white', 120.0), ('cheese, sulguni', 80.5)],
    );
    expect(recipe.totalWeightG, 200.5);

    bloc
      ..add(const ChangeRowAmountEvent(0, '150'))
      ..add(const ToggleRowSkippedEvent(1));
    state = await settle();
    expect(
      [
        for (final i in recipeFromDishGroup(state.rows, group)!.ingredients)
          i.convertedAmountG,
      ],
      [150.0],
    );

    bloc.add(const ToggleRowSkippedEvent(0));
    state = await settle();
    expect(recipeFromDishGroup(state.rows, group), isNull);
    controller.dispose();
  });

  group('statedAmount', () {
    BulkAddRow row(
      ParsedMealItem parsed, {
      String amountText = '100',
      String unit = 'g/ml',
      bool edited = false,
      bool unitChosen = false,
    }) => BulkAddRow(
      resolved: ResolvedMealItem(
        parsed: parsed,
        candidates: const [],
        selectedIndex: 0,
        confidence: 0,
      ),
      selectedIndex: 0,
      amountText: amountText,
      unit: unit,
      amountEditedByUser: edited,
      unitChosenByUser: unitChosen,
    );

    test('nothing stated: none, not the 100 g default', () {
      expect(statedAmount(row(const ParsedMealItem(query: 'borscht'))), isNull);
    });

    test('a stated amount keeps its unit; a bare count stays a count', () {
      expect(
        statedAmount(
          row(
            const ParsedMealItem(query: 'kefir', quantity: 500, unit: 'ml'),
            amountText: '500',
            unit: 'ml',
          ),
        ),
        '500 ml',
      );
      final eggs = row(
        const ParsedMealItem(query: 'olas', quantity: 3),
        amountText: '3',
      );
      expect(statedAmount(eggs), '3');
      expect(statedCount(eggs), 3);
      // Retyped, a count is still a count.
      expect(
        statedAmount(
          row(
            const ParsedMealItem(query: 'olas', quantity: 3),
            amountText: '4',
            edited: true,
          ),
        ),
        '4',
      );
    });

    test('typed over the default, the number is in the unit shown', () {
      final typed = row(
        const ParsedMealItem(query: 'plov'),
        amountText: '350,5',
        edited: true,
      );
      expect(statedAmount(typed), '350.5 g');
      expect(statedCount(typed), isNull);
      final servings = row(
        const ParsedMealItem(query: 'plov', quantity: 2),
        amountText: '2',
        unit: 'serving#1',
        unitChosen: true,
      );
      expect(statedAmount(servings), '2 servings');
      // a recipe saved from it holds two servings, not one of double
      expect(statedCount(servings), 2);
    });
  });

  group('a matched dish broken down', () {
    // "a bowl of homemade borscht": a weak match at its 350 g serving
    final borscht = MealEntity(
      code: 'borscht',
      name: 'Borscht, with beef',
      url: null,
      mealQuantity: null,
      mealUnit: 'g',
      servingQuantity: 350,
      servingUnit: 'g',
      servingSize: null,
      nutriments: MealNutrimentsEntity.empty(),
      source: MealSourceEntity.fdc,
    );

    test('keeps the weight the row showed, its ingredients as weighed for '
        'it', () async {
      final borschtBloc = BulkAddBloc(
        _WeakResolver(borscht),
        _OneReader(const ParsedMealItem(query: 'borscht')),
        _PhotoReader(),
      );
      addTearDown(borschtBloc.close);
      final amounts = <String?>[];
      final controller = DishBreakdownController(
        borschtBloc,
        // a soup's solids, its water left out: less than the bowl
        breakDown: (dish, {amount, photo}) async {
          amounts.add(amount);
          return DishBreakdown(
            dish,
            await _Resolver().resolve(const [
              ParsedMealItem(
                query: 'wheat flour, white',
                quantity: 120,
                unit: 'g',
              ),
              ParsedMealItem(
                query: 'cheese, sulguni',
                quantity: 80.5,
                unit: 'g',
              ),
            ]),
          );
        },
        modelConfigured: () async => true,
      );
      addTearDown(controller.dispose);
      borschtBloc.add(
        const ParseBulkTextEvent(text: 'x', usesImperialUnits: false),
      );
      await pumpEventQueue();
      final row = (borschtBloc.state as BulkAddLoadedState).rows.single;
      expect(row.amountText, '350');
      expect(controller.canBreakDown(row), isTrue);

      await controller.breakDown(row);
      await pumpEventQueue();
      final rows = (borschtBloc.state as BulkAddLoadedState).rows;
      expect(amounts, ['350 g']);
      final group = rows.first.dishIngredient!.group;
      final members = dishMembers(rows, group);
      // the ingredients as the model weighed them, not scaled up to it
      expect([for (final i in members) rows[i].amountText], ['120', '80.5']);
      expect(dishPortion(rows, members), closeTo(350, 1e-9));
      expect(
        double.parse(dishMeal(rows, group)!.mealQuantity!),
        closeTo(350, 1e-6),
      );
    });
  });

  group('a food of a read dish that nothing matched', () {
    final plate = Object();
    DishIngredientItem food(String query, double grams) => DishIngredientItem(
      query: query,
      quantity: grams,
      unit: 'g',
      dish: 'mixed plate',
      group: plate,
    );

    Future<(BulkAddBloc, List<(String, String?)>)> read(
      List<ParsedMealItem> ingredients,
    ) async {
      final plateBloc = BulkAddBloc(
        _Resolver(),
        _ModelReader(),
        _ItemsPhotoReader([
          food('egg, whole, raw', 100),
          food('bell pepper, battered, fried', 80),
        ]),
      );
      addTearDown(plateBloc.close);
      final asked = <(String, String?)>[];
      final controller = DishBreakdownController(
        plateBloc,
        breakDown: (dish, {amount, photo}) async {
          asked.add((dish, amount));
          return DishBreakdown(dish, await _Resolver().resolve(ingredients));
        },
        modelConfigured: () async => true,
      );
      addTearDown(controller.dispose);
      plateBloc.add(
        ReadMealPhotoEvent(
          photo: MealPhoto(bytes: Uint8List(1), mediaType: 'image/webp'),
          usesImperialUnits: false,
        ),
      );
      await pumpEventQueue();
      await pumpEventQueue();
      return (plateBloc, asked);
    }

    test('is broken down once, its ingredients joining the dish', () async {
      final (plateBloc, asked) = await read(const [
        ParsedMealItem(query: 'wheat flour, white', quantity: 20, unit: 'g'),
        ParsedMealItem(query: 'cheese, sulguni', quantity: 55, unit: 'g'),
      ]);
      expect(asked, [('bell pepper, battered, fried', '80 g')]);
      final rows = (plateBloc.state as BulkAddLoadedState).rows;
      expect(
        [for (final r in rows) r.meal?.name],
        ['egg, whole, raw', 'wheat flour, white', 'cheese, sulguni'],
      );
      // one dish still, as the Diary holds it: no dish inside a dish
      expect(dishMembers(rows, plate), [0, 1, 2]);
      expect(rows[1].dishIngredient!.dish, 'mixed plate');
    });

    test('an ingredient a breakdown wrote that nothing matched is not broken '
        'down again', () async {
      final (plateBloc, asked) = await read(const [
        ParsedMealItem(query: 'sumac', quantity: 2, unit: 'g'),
      ]);
      await pumpEventQueue();
      expect(asked, hasLength(1));
      final rows = (plateBloc.state as BulkAddLoadedState).rows;
      expect(rows.last.isResolved, isFalse);
      expect(rows.last.dishIngredient!.group, same(plate));
    });
  });
}

/// Finds [meal] for anything, weakly.
class _WeakResolver implements ResolveParsedMealsUseCase {
  final MealEntity meal;

  _WeakResolver(this.meal);

  @override
  Future<List<ResolvedMealItem>> resolve(
    List<ParsedMealItem> items, {
    bool fromPhoto = false,
  }) async => [
    for (final item in items)
      ResolvedMealItem(
        parsed: item,
        candidates: [meal],
        selectedIndex: 0,
        confidence: 0.1,
      ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OneReader implements ReadMealTextUseCase {
  final ParsedMealItem item;

  _OneReader(this.item);

  @override
  Future<MealTextReading> read(String input, {String? localeCode}) async =>
      MealTextReading(
        MealTextParseResult(items: [item], errors: const []),
        usedModel: true,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ItemsPhotoReader implements ReadMealPhotoUseCase {
  final List<ParsedMealItem> items;

  _ItemsPhotoReader(this.items);

  @override
  Future<MealPhotoReadResult> read(
    MealPhoto photo, {
    String? localeCode,
    String? note,
  }) async =>
      MealPhotoRead(MealTextParseResult(items: items, errors: const []));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
