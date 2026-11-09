// Fork cases moved out of test/unit_test/bulk_add_bloc_test.dart (they test the fork's changes).

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_text_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_photo_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_text_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_portion_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/search_products_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';

MealEntity meal(
  String name, {
  double? servingQuantity,
  String? servingUnit,
  String? servingSize,
  String? mealUnit,
  List<MealPortionEntity> portions = const [],
}) => MealEntity(
  code: name,
  name: name,
  url: null,
  mealQuantity: null,
  mealUnit: mealUnit,
  servingQuantity: servingQuantity,
  servingUnit: servingUnit,
  servingSize: servingSize,
  portions: portions,
  source: MealSourceEntity.off,
  nutriments: MealNutrimentsEntity.empty(),
);

class _FakeSearch implements SearchProductsUseCase {
  final Map<String, List<MealEntity>> results;
  _FakeSearch(this.results);

  @override
  Future<SearchProductsResult> searchOFFProductsByString(
    String searchString, {
    bool skipRemote = false,
  }) async {
    return SearchProductsResult(
      meals: results[searchString] ?? const [],
      remoteSourceEmpty: false,
    );
  }

  @override
  Future<SearchProductsResult> searchFDCFoodByString(
    String searchString, {
    bool skipRemote = false,
    bool forResolution = false,
  }) async => const SearchProductsResult(meals: [], remoteSourceEmpty: false);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// No credential stored, so the use case always takes the parser path —
/// these tests are about the bloc, not about which reader produced the items.
ReadMealTextUseCase parserOnlyReader() => ReadMealTextUseCase(
  AiCredentialStorage(_EmptyStorage()),
  (_) => throw StateError('must not be built without a key'),
);

/// Same idea for photos: no credential, so the use case reports the feature
/// unavailable without ever building an interpreter.
ReadMealPhotoUseCase photoReaderWithoutKey() => ReadMealPhotoUseCase(
  AiCredentialStorage(_EmptyStorage()),
  (_) => throw StateError('must not be built without a key'),
);

/// A key *is* stored here, so the use case really builds an interpreter and
/// really takes the model path — which is the only way to exercise what
/// happens when that path fails.
ReadMealTextUseCase readerFailingWith(MealInterpreterException failure) {
  return ReadMealTextUseCase(
    AiCredentialStorage(
      _MapStorage({
        'AiApiKeyTag.anthropic': 'sk-test',
        'AiAssistEnabledTag': 'true',
      }),
    ),
    (_) => _AlwaysFailsInterpreter(failure),
  );
}

class _AlwaysFailsInterpreter implements MealTextInterpreter {
  final MealInterpreterException failure;

  _AlwaysFailsInterpreter(this.failure);

  @override
  Future<MealTextParseResult> interpret(String input, {String? localeCode}) =>
      throw failure;
}

/// A model that answers with exactly these items. The sibling of
/// [readerFailingWith]: a key is stored, so the use case really takes the
/// model path rather than falling back to the parser.
ReadMealTextUseCase readerReturning(List<ParsedMealItem> items) =>
    ReadMealTextUseCase(
      AiCredentialStorage(
        _MapStorage({
          'AiApiKeyTag.anthropic': 'sk-test',
          'AiAssistEnabledTag': 'true',
        }),
      ),
      (_) => _FixedInterpreter(items),
    );

class _FixedInterpreter implements MealTextInterpreter {
  final List<ParsedMealItem> items;

  _FixedInterpreter(this.items);

  @override
  Future<MealTextParseResult> interpret(
    String input, {
    String? localeCode,
  }) async => MealTextParseResult(items: items, errors: const []);
}

BulkAddBloc blocWithModelReply(
  Map<String, List<MealEntity>> results,
  List<ParsedMealItem> items,
) => BulkAddBloc(
  ResolveParsedMealsUseCase(_FakeSearch(results)),
  readerReturning(items),
  photoReaderWithoutKey(),
);

BulkAddBloc blocWithFailingReader(
  Map<String, List<MealEntity>> results,
  MealInterpreterException failure,
) => BulkAddBloc(
  ResolveParsedMealsUseCase(_FakeSearch(results)),
  readerFailingWith(failure),
  photoReaderWithoutKey(),
);

BulkAddBloc blocWith(
  Map<String, List<MealEntity>> results, {
  ReadMealPhotoUseCase? photoReader,
}) => BulkAddBloc(
  ResolveParsedMealsUseCase(_FakeSearch(results)),
  parserOnlyReader(),
  photoReader ?? photoReaderWithoutKey(),
);

Future<BulkAddLoadedState> parse(
  BulkAddBloc bloc,
  String text, {
  bool imperial = false,
}) async {
  bloc.add(ParseBulkTextEvent(text: text, usesImperialUnits: imperial));
  return await bloc.stream.firstWhere((s) => s is BulkAddLoadedState)
      as BulkAddLoadedState;
}

void main() {
  // S196, S204: a model's reading of typed text names foods in English, as
  // a photo's does, so a packet it did not name trails the generic row; the
  // parser's words may mean the packet.
  group('a packet the name did not ask for', () {
    final packet = MealEntity(
      code: 'packet',
      name: 'Tomato',
      brands: 'Maestri',
      url: null,
      mealQuantity: null,
      mealUnit: 'g',
      servingQuantity: null,
      servingUnit: 'g',
      servingSize: null,
      source: MealSourceEntity.off,
      nutriments: MealNutrimentsEntity.empty(),
    );
    final generic = MealEntity(
      code: 'generic',
      name: 'Tomatoes, raw',
      url: null,
      mealQuantity: null,
      mealUnit: 'g',
      servingQuantity: null,
      servingUnit: 'g',
      servingSize: null,
      source: MealSourceEntity.fdc,
      nutriments: MealNutrimentsEntity.empty(),
    );
    final results = {
      'tomato': [packet, generic],
    };

    test('trails the generic food on a model\'s read of typed text', () async {
      final bloc = blocWithModelReply(results, const [
        ParsedMealItem(query: 'tomato'),
      ]);
      final state = await parse(bloc, 'tomāts');
      expect(state.rows.single.meal?.code, 'generic');
    });

    test('keeps its place on the parser\'s read', () async {
      final state = await parse(blocWith(results), 'tomato');
      expect(state.rows.single.meal?.code, 'packet');
    });
  });

  group('a bare count (#622)', () {
    test('flags a count past what a recipe batch makes', () async {
      // A recipe's serving is a share of the batch: "14 pelmeni" against six
      // servings of pelmeni would log about 3 kg. Five tarts of a twelve-tart
      // batch are five servings, as before.
      MealEntity recipe(String name, int servings) => MealEntity(
        code: name,
        name: name,
        url: null,
        mealQuantity: '1200.0',
        mealUnit: 'g',
        servingQuantity: 1200 / servings,
        servingUnit: 'g',
        servingSize: '$servings servings',
        source: MealSourceEntity.recipe,
        nutriments: MealNutrimentsEntity.empty(),
      );
      final bloc = blocWith({
        'pelmeni': [recipe('Pelmeni', 6)],
        'tarts': [recipe('Tarts', 12)],
      });

      final state = await parse(bloc, '14 pelmeni, 5 tarts');

      expect(state.rows[0].unit, 'serving');
      expect(state.rows[0].amountNeedsCheck, isTrue);
      expect(state.rows[0].willBeLogged, isFalse);
      expect(state.rows[1].amountNeedsCheck, isFalse);
      expect(state.loggableCount, 1);
    });

    test('a count of eggs is eggs, not cups of chopped egg', () async {
      // A photo's 2 hard-boiled eggs logged 2 × "1 cup, chopped", 272 g.
      MealPortionEntity p(String label, double grams) =>
          MealPortionEntity(label: label, gramWeight: grams, localized: false);
      final bloc = blocWith({
        'hard-boiled eggs': [
          meal(
            'Egg, whole, cooked, hard-boiled',
            servingQuantity: 136,
            servingUnit: 'g',
            servingSize: '1 cup, chopped',
            portions: [
              p('1 cup, chopped', 136),
              p('1 tbsp', 8.5),
              p('1 large', 50),
            ],
          ),
        ],
        'apples': [
          meal(
            'Apples, raw',
            servingQuantity: 125,
            servingUnit: 'g',
            servingSize: '1 cup, sliced',
            portions: [
              p('1 cup, sliced', 125),
              p('1 large (3-1/4" dia)', 223),
              p('1 medium (3" dia)', 182),
              p('1 package', 400),
            ],
          ),
        ],
        'cookies': [
          meal(
            'Cookies',
            servingQuantity: 30,
            servingUnit: 'g',
            servingSize: '30 g',
            portions: [p('30 g', 30), p('1 package', 300)],
          ),
        ],
        'waffles': [
          meal(
            'Waffle',
            servingQuantity: 28,
            servingUnit: 'g',
            servingSize: '1 waffle',
            portions: [p('1 waffle', 28), p('1 large', 40)],
          ),
        ],
      });

      final state = await parse(
        bloc,
        '2 hard-boiled eggs, 2 apples, 2 cookies, 2 waffles',
      );

      expect(
        [for (final r in state.rows) r.unit],
        ['serving#2', 'serving#2', 'serving', 'serving'],
      );
      expect(state.rows.first.amountText, '2');
      expect(state.rows.first.amountNeedsCheck, isFalse);
    });
  });

  test('a garnish starts at a pinch or a spoon, not a cup', () async {
    // A photo's parsley came in at 100 g, grated parmesan at USDA's cup.
    final bloc = blocWith({
      'parsley': [meal('Parsley')],
      'parmesan': [
        meal(
          'Cheese, parmesan, grated',
          servingQuantity: 100,
          servingUnit: 'g',
          servingSize: '1 cup',
        ),
      ],
      'dill': [
        meal(
          'Dill weed, fresh',
          servingQuantity: 1,
          servingUnit: 'g',
          servingSize: '5 sprigs',
        ),
      ],
    });

    final state = await parse(bloc, 'parsley, parmesan, dill');

    expect([for (final r in state.rows) r.amountText], ['5', '10', '1']);
  });

  test('a food named with its shape is found by the food', () async {
    // A photo's "1 lemon slice" found no row; "Lemon, raw" has the slice.
    final bloc = blocWith({
      'lemon': [
        meal(
          'Lemon, raw',
          servingQuantity: 65,
          servingUnit: 'g',
          servingSize: '1 fruit',
          portions: [
            MealPortionEntity(
              label: '1 fruit',
              gramWeight: 65,
              localized: false,
            ),
            MealPortionEntity(
              label: '1 slice or wedge',
              gramWeight: 8,
              localized: false,
            ),
          ],
        ),
      ],
    });

    final row = (await parse(bloc, '1 lemon slice')).rows.single;

    expect(row.meal?.name, 'Lemon, raw');
    expect(row.resolved.parsed.query, 'lemon slice');
    expect(row.unit, 'serving#1');
  });

  test(
    'a soup with no amount and no serving starts at a bowl, croutons at a handful',
    () async {
      // A photo's borscht and chłodnik logged 100 g, a third of a bowl.
      final bloc = blocWith({
        'borscht': [meal('Beetroot soup, with apple and horseradish')],
        'stock cubes': [meal('Beef bouillon/stock/soup (stock cubes, powder)')],
        'croutons': [meal('Croutons, white bread cubes toasted in butter')],
      });

      final metric = await parse(bloc, 'borscht, stock cubes, croutons');
      expect([for (final r in metric.rows) r.amountText], ['300', '100', '15']);

      final imperial = await parse(bloc, 'borscht, croutons', imperial: true);
      expect([for (final r in imperial.rows) r.amountText], ['10.5', '0.5']);
    },
  );

  test('a slice of a food with no slice portion is its piece', () async {
    // "2 slices of pepperoni pizza" took "1 personal size pizza" on the
    // word pizza: two whole pizzas, 870 kcal against 600.
    final bloc = blocWith({
      'pepperoni pizza': [
        meal(
          'Pizza with pepperoni, from school lunch, medium crust',
          servingQuantity: 147,
          servingUnit: 'g',
          servingSize: '1 serving',
          portions: [
            MealPortionEntity(
              label: '1 personal size pizza (5-7" diameter)',
              gramWeight: 170,
              localized: false,
            ),
            MealPortionEntity(
              label: '1 piece, NFS',
              gramWeight: 147,
              localized: false,
            ),
          ],
        ),
      ],
    });

    final row = (await parse(bloc, '2 slices of pepperoni pizza')).rows.single;

    expect(row.meal?.name, startsWith('Pizza with pepperoni'));
    expect(row.unit, 'serving#1');
  });

  test(
    'a plate or bowl the read named starts there, whatever the row',
    () async {
      // "millet porridge with pumpkin" found a pumpkin porridge and logged its
      // 100 g, 74 kcal against 357; "Pasta sauce with meat" a 60 g ladle.
      final bloc = blocWith({
        'millet porridge with pumpkin': [meal('Pumpkin cream')],
        'macaroni with meat sauce': [meal('Pasta sauce with meat, meat')],
        'chicken laksa': [meal('Coconut chicken')],
        'croutons for soup': [
          meal('Croutons, white bread cubes toasted in butter'),
        ],
      });

      final metric = await parse(
        bloc,
        'millet porridge with pumpkin, macaroni with meat sauce, chicken laksa, '
        'croutons for soup',
      );
      expect(
        [for (final r in metric.rows) r.amountText],
        ['300', '300', '300', '15'],
      );
    },
  );

  test('a main dish with no amount and no serving starts at a plate', () async {
    // A photo's pilaf logged 100 g, 167 kcal against the plov's 753.
    final bloc = blocWith({
      'pilaf': [meal('Pilaf (rice, with onions and butter)')],
      'curry powder': [meal('Curry powder')],
    });

    final metric = await parse(bloc, 'pilaf, curry powder');
    expect([for (final r in metric.rows) r.amountText], ['300', '100']);

    final imperial = await parse(bloc, 'pilaf', imperial: true);
    expect(imperial.rows.single.amountText, '10.5');
  });
}

/// A keystore with nothing in it, so the read use case always takes the
/// deterministic path.
/// Holds what it is given, so a test can put the use case on the model path
/// instead of the parser one.
class _MapStorage implements FlutterSecureStorage {
  final Map<String, String> values;

  /// Seeds the agreement unless a test says otherwise.
  ///
  /// A stored credential is only usable once the user has agreed to what
  /// leaves the device (#836), so a map holding a key and no agreement is a
  /// state the app cannot reach.
  _MapStorage(Map<String, String> values)
    : values = {'AiTermsAcceptedTag': 'true', ...values};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyStorage implements FlutterSecureStorage {
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
