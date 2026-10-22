import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_photo_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_text_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/dish/break_down_dish_usecase.dart';
import 'package:opennutritracker/fork/dish/dish_breakdown_controller.dart';
import 'package:opennutritracker/fork/dish/dish_breakdown_rows.dart';

MealEntity _meal(String name) => MealEntity(
  code: name,
  name: name,
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: 'g',
  servingSize: null,
  nutriments: MealNutrimentsEntity.empty(),
  source: MealSourceEntity.fdc,
);

/// Finds what the table holds: only the ingredients, never the dish.
class _Resolver implements ResolveParsedMealsUseCase {
  static const table = {
    'cheese, sulguni',
    'wheat flour, white',
    'egg, whole, raw',
  };

  @override
  Future<List<ResolvedMealItem>> resolve(List<ParsedMealItem> items) async => [
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

class _PhotoReader implements ReadMealPhotoUseCase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late BulkAddBloc bloc;
  late List<String> asked;

  Future<DishBreakdown?> breakDown(String dish) async {
    asked.add(dish);
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
      breakDown: (dish) async => null,
      modelConfigured: () async => true,
    );
    bloc.add(const ParseBulkTextEvent(text: 'x', usesImperialUnits: false));
    final state = await settle();

    expect(state.rows.map(controller.canBreakDown), [true, false]);
    controller.dispose();
  });

  test('a failed call leaves the row and reports it', () async {
    final controller = DishBreakdownController(
      bloc,
      breakDown: (dish) async => throw const MealInterpreterException('down'),
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
}
