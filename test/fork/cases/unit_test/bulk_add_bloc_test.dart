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
