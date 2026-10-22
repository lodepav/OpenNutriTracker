import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/dish/break_down_dish_usecase.dart';

class _Credentials implements AiCredentialStorage {
  final AiSelection? selection;

  _Credentials(this.selection);

  @override
  Future<AiSelection?> readSelection() async => selection;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Api implements MealItemsApi {
  final List<ParsedMealItem> reply;
  MealContent? content;
  String? system;

  _Api(this.reply);

  @override
  Future<MealTextParseResult> requestItems({
    required MealContent content,
    required String system,
  }) async {
    this.content = content;
    this.system = system;
    // What every client does with a reply (anthropic_meal_items_api.dart).
    return validateParsedMealItems(
      reply,
      statedIn: content is MealTextContent ? content.text : null,
    );
  }
}

class _Resolver implements ResolveParsedMealsUseCase {
  @override
  Future<List<ResolvedMealItem>> resolve(List<ParsedMealItem> items) async => [
    for (final item in items)
      ResolvedMealItem(
        parsed: item,
        candidates: const [],
        selectedIndex: 0,
        confidence: 0,
      ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const selection = AiSelection(provider: AiProvider.anthropic, apiKey: 'k');
  final reply = [
    const ParsedMealItem(query: 'wheat flour', quantity: 120, unit: 'g'),
    const ParsedMealItem(query: 'mozzarella cheese', quantity: 80, unit: 'g'),
    const ParsedMealItem(query: 'egg', quantity: 50, unit: 'g'),
    const ParsedMealItem(query: 'milk', quantity: 60, unit: 'ml'),
  ];

  test('asks for one serving of the dish and resolves each ingredient '
      'with its grams kept', () async {
    final api = _Api(reply);
    final breakdown = await BreakDownDishUseCase(
      _Credentials(selection),
      (_) => api,
      _Resolver(),
    )('khachapuri adjaruli');

    expect(
      (api.content! as MealTextContent).text,
      contains('khachapuri adjaruli'),
    );
    expect(api.system, BreakDownDishUseCase.systemPrompt);
    expect(breakdown!.dish, 'khachapuri adjaruli');
    expect(
      [
        for (final i in breakdown.ingredients)
          (i.parsed.query, i.parsed.quantity, i.parsed.unit),
      ],
      [
        ('wheat flour', 120.0, 'g'),
        ('mozzarella cheese', 80.0, 'g'),
        ('egg', 50.0, 'g'),
        ('milk', 60.0, 'ml'),
      ],
    );
  });

  // The clients drop a unit the text does not state (#977). If the wording
  // stops stating one, the grams turn into bare counts: "120 wheat flour".
  test('the text sent states a unit, whatever the dish is called', () {
    for (final dish in [
      'khachapuri',
      'Pelmeņi ar krējumu',
      'pizza 4 cheeses',
      '',
    ]) {
      expect(
        textStatesAUnit(BreakDownDishUseCase.contentFor(dish)),
        isTrue,
        reason: dish,
      );
    }
  });

  test('no model configured: no breakdown, nothing sent', () async {
    final api = _Api(reply);
    expect(
      await BreakDownDishUseCase(_Credentials(null), (_) => api, _Resolver())(
        'khinkali',
      ),
      isNull,
    );
    expect(api.content, isNull);
  });

  test(
    'a failed call reaches the caller: there is no parser to fall back to',
    () {
      final useCase = BreakDownDishUseCase(
        _Credentials(selection),
        (_) => throw const MealInterpreterException('down'),
        _Resolver(),
      );
      expect(useCase('khinkali'), throwsA(isA<MealInterpreterException>()));
    },
  );

  group('preferTableRow', () {
    MealEntity meal(String name, MealSourceEntity source) => MealEntity(
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
    ResolvedMealItem item(List<MealEntity> candidates) => ResolvedMealItem(
      parsed: const ParsedMealItem(query: 'cheese, mozzarella, whole milk'),
      candidates: candidates,
      selectedIndex: 0,
      confidence: 0.9,
    );
    final product = meal('whole milk mozzarella cheese', MealSourceEntity.off);
    final row = meal('Cheese, mozzarella, whole milk', MealSourceEntity.fdc);
    final recipe = meal('Khachapuri', MealSourceEntity.recipe);

    test('a product chosen over a table row gives way to the row', () {
      expect(preferTableRow(item([product, row])).selected, row);
    });

    test('a recipe, a table row, or a product alone is kept', () {
      expect(preferTableRow(item([recipe, row])).selected, recipe);
      expect(preferTableRow(item([row, product])).selected, row);
      expect(preferTableRow(item([product])).selected, product);
      expect(preferTableRow(item([])).selected, isNull);
    });
  });
}
