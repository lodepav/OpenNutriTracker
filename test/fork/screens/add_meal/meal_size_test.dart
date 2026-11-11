import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_photo_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_text_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/dish/break_down_dish_usecase.dart';
import 'package:opennutritracker/fork/dish/dish_breakdown_rows.dart';
import 'package:opennutritracker/fork/dish/dish_strings.dart';
import 'package:opennutritracker/fork/screens/add_meal/bulk_add_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

/// 100 kcal per 100 g, so a row's grams are its kcal.
MealEntity _meal(String name) => MealEntity(
  code: name,
  name: name,
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: null,
  servingSize: null,
  source: MealSourceEntity.fdc,
  nutriments: const MealNutrimentsEntity(
    energyKcal100: 100,
    carbohydrates100: 0,
    fat100: 0,
    proteins100: 0,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  ),
);

ResolvedMealItem _resolved(ParsedMealItem item) => ResolvedMealItem(
  parsed: item,
  candidates: [_meal(item.query)],
  selectedIndex: 0,
  confidence: 1,
);

class _Resolver implements ResolveParsedMealsUseCase {
  @override
  Future<List<ResolvedMealItem>> resolve(
    List<ParsedMealItem> items, {
    bool fromPhoto = false,
  }) async => [for (final item in items) _resolved(item)];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Answers with [items], or waits on [gate] while it is set.
class _PhotoReader implements ReadMealPhotoUseCase {
  List<ParsedMealItem> items = const [];
  Completer<void>? gate;

  @override
  Future<MealPhotoReadResult> read(
    MealPhoto photo, {
    String? localeCode,
    String? note,
  }) async {
    await gate?.future;
    return MealPhotoRead(MealTextParseResult(items: items, errors: const []));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A model's reading of typed text.
class _TextReader implements ReadMealTextUseCase {
  @override
  Future<MealTextReading> read(String input, {String? localeCode}) async =>
      const MealTextReading(
        MealTextParseResult(
          items: [ParsedMealItem(query: 'rice', quantity: 150, unit: 'g')],
          errors: [],
        ),
        usedModel: true,
      );

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

final _getIt = GetIt.instance;
late BulkAddBloc _bloc;
late _PhotoReader _reader;

Widget _app() => ChangeNotifierProvider<EnergyUnitProvider>(
  create: (_) => EnergyUnitProvider(usesKilojoules: false),
  child: MaterialApp(
    localizationsDelegates: const [
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: S.supportedLocales,
    initialRoute: NavigationOptions.mainRoute,
    onGenerateRoute: (settings) => settings.name == NavigationOptions.mainRoute
        ? MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const Scaffold(body: SizedBox()),
          )
        : MaterialPageRoute<void>(
            settings: RouteSettings(
              name: settings.name,
              arguments: BulkAddScreenArguments(
                IntakeTypeEntity.lunch,
                DateTime(2026, 8, 10),
                false,
              ),
            ),
            builder: (_) => const BulkAddScreen(),
          ),
  ),
);

const _rice = ParsedMealItem(query: 'rice', quantity: 150, unit: 'g');
const _chicken = ParsedMealItem(query: 'chicken', quantity: 100, unit: 'g');

/// The screen's graph, built inside the test, where its bloc's work runs
/// in the test's fake time.
Future<void> _register() async {
  await _getIt.reset();
  _reader = _PhotoReader();
  _bloc = BulkAddBloc(_Resolver(), _TextReader(), _reader);
  _getIt
    ..registerLazySingleton<AiCredentialStorage>(
      () => AiCredentialStorage(_EmptyStorage()),
    )
    ..registerSingleton<BulkAddBloc>(_bloc);
}

/// Opens the screen, tall enough for the card and every row.
Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await _register();
  await tester.pumpWidget(_app());
  tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/bulk');
  await tester.pumpAndSettle();
}

/// The photo read again, answered with [items].
Future<void> _readPhoto(
  WidgetTester tester, [
  List<ParsedMealItem> items = const [_rice, _chicken],
]) async {
  _reader.items = items;
  _bloc.add(
    ReadMealPhotoEvent(
      photo: MealPhoto(bytes: Uint8List.fromList([1]), mediaType: 'image/webp'),
      usesImperialUnits: false,
    ),
  );
  await tester.pumpAndSettle();
}

/// A row's amount as its button shows it, not a chip of the question on
/// the meal's largest food that may read the same.
Finder _amount(String text) =>
    find.descendant(of: find.byType(OutlinedButton), matching: find.text(text));

Finder _chip(double factor) =>
    find.byKey(ValueKey('bulk-add-meal-size-$factor'));

Future<void> _tapChip(WidgetTester tester, double factor) async {
  await tester.tap(_chip(factor));
  await tester.pumpAndSettle();
}

String _mealKcal(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('bulk-add-meal-kcal'))).data!;

Future<void> _step(WidgetTester tester, int row) async {
  await tester.tap(find.byKey(ValueKey('bulk-add-more-$row')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    final before = forkDayTotals;
    forkDayTotals = (_) async => (
      eaten: (kcal: 1000.0, carbs: 100.0, fat: 40.0, protein: 60.0),
      goal: (kcal: 2400.0, carbs: 260.0, fat: 80.0, protein: 150.0),
    );
    addTearDown(() => forkDayTotals = before);
  });

  tearDown(() async => _getIt.reset());

  group('shown', () {
    testWidgets('for a photo read, with "As shown" chosen', (tester) async {
      await _open(tester);
      await _readPhoto(tester);
      expect(find.text(DishStrings.mealSize), findsOneWidget);
      for (final label in ['×0.6', '×0.8', 'As shown', '×1.2', '×1.4']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(tester.widget<ChoiceChip>(_chip(1.0)).selected, isTrue);
      expect(find.text(DishStrings.sizeScalesUnset), findsOneWidget);
    });

    testWidgets('not for typed text', (tester) async {
      await _open(tester);
      await tester.enterText(find.byType(TextField).first, 'rice');
      await tester.pump();
      await tester.tap(find.widgetWithIcon(FilledButton, Icons.search));
      await tester.pumpAndSettle();
      expect(_amount('150 g'), findsOneWidget);
      expect(find.text(DishStrings.mealSize), findsNothing);
    });

    testWidgets('not while loading, nor with no rows', (tester) async {
      await _open(tester);
      _reader.gate = Completer<void>();
      _reader.items = const [_rice];
      _bloc.add(
        ReadMealPhotoEvent(
          photo: MealPhoto(bytes: Uint8List(1), mediaType: 'image/webp'),
          usesImperialUnits: false,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(_bloc.state, isA<BulkAddLoadingState>());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(DishStrings.mealSize), findsNothing);
      _reader.gate!.complete();
      _reader.gate = null;
      await tester.pumpAndSettle();
      expect(find.text(DishStrings.mealSize), findsOneWidget);

      await _readPhoto(tester, const []);
      expect(find.text(DishStrings.mealSize), findsNothing);
    });
  });

  testWidgets('a size scales the rows, the meal and Log; "As shown" puts '
      'them back', (tester) async {
    final semantics = tester.ensureSemantics();
    await _open(tester);
    await _readPhoto(tester);
    expect(_mealKcal(tester), '250 kcal');

    await _tapChip(tester, 0.6);
    expect(_amount('90 g'), findsOneWidget);
    expect(_amount('60 g'), findsOneWidget);
    expect(_mealKcal(tester), '150 kcal');
    expect(
      find.descendant(
        of: find.widgetWithIcon(FilledButton, Icons.add_rounded),
        matching: find.textContaining('· 150 kcal'),
      ),
      findsOneWidget,
    );
    expect(tester.widget<ChoiceChip>(_chip(0.6)).selected, isTrue);
    expect(tester.widget<ChoiceChip>(_chip(1.0)).selected, isFalse);
    expect(
      tester.takeAnnouncements().map((a) => a.message),
      contains('Meal now 150 kcal'),
    );

    await _tapChip(tester, 1.4);
    expect(_amount('210 g'), findsOneWidget);
    expect(_amount('140 g'), findsOneWidget);

    await _tapChip(tester, 1.0);
    expect(_amount('150 g'), findsOneWidget);
    expect(_amount('100 g'), findsOneWidget);
    expect(_mealKcal(tester), '250 kcal');
    semantics.dispose();
  });

  testWidgets('an amount the user set stays, and says so while a size is '
      'chosen', (tester) async {
    await _open(tester);
    await _readPhoto(tester);
    await _step(tester, 0);
    expect(_amount('160 g'), findsOneWidget);

    await _tapChip(tester, 0.6);
    expect(_amount('160 g'), findsOneWidget);
    expect(_amount('60 g'), findsOneWidget);
    expect(find.byKey(const ValueKey('bulk-add-set-by-you-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('bulk-add-set-by-you-1')), findsNothing);

    await _tapChip(tester, 1.0);
    expect(find.text(DishStrings.setByYou), findsNothing);
    expect(_amount('160 g'), findsOneWidget);
  });

  testWidgets('with every amount set by the user the chips rest', (
    tester,
  ) async {
    await _open(tester);
    await _readPhoto(tester);
    await _tapChip(tester, 0.8);
    await _step(tester, 0);
    await _step(tester, 1);
    expect(find.text(DishStrings.sizeAllSet), findsOneWidget);
    expect(find.text(DishStrings.sizeScalesUnset), findsNothing);
    for (final factor in [0.6, 0.8, 1.0, 1.2, 1.4]) {
      expect(tester.widget<ChoiceChip>(_chip(factor)).onSelected, isNull);
    }
    expect(find.text(DishStrings.setByYou), findsNWidgets(2));
  });

  testWidgets('at twice the text size on a narrow phone the chips wrap, '
      'none cut off', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await _register();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: _app(),
      ),
    );
    tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/bulk');
    await tester.pumpAndSettle();
    await _readPhoto(tester);
    expect(tester.takeException(), isNull);

    final rows = <double>{};
    for (final factor in [0.6, 0.8, 1.0, 1.2, 1.4]) {
      final label = find.descendant(
        of: find.descendant(
          of: _chip(factor),
          matching: find.text(DishStrings.sizeChip(factor)),
        ),
        matching: find.byType(RichText),
      );
      expect(
        tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
        isFalse,
      );
      final chip = tester.getRect(_chip(factor));
      expect(chip.height, greaterThanOrEqualTo(48));
      rows.add(chip.top);
    }
    expect(rows.length, greaterThan(1), reason: 'the Wrap took more lines');
    for (final line in [DishStrings.sizeScalesUnset, DishStrings.mealSize]) {
      expect(
        tester.renderObject<RenderParagraph>(find.text(line)).didExceedMaxLines,
        isFalse,
      );
    }
  });

  testWidgets('"Size" is a heading; each chip says what it does and whether '
      'it is chosen', (tester) async {
    final handle = tester.ensureSemantics();
    await _open(tester);
    await _readPhoto(tester);
    expect(
      tester.getSemantics(find.text(DishStrings.mealSize)),
      isSemantics(label: 'Size', isHeader: true),
    );
    final spoken = {
      0.6: "0.6 times the photo's amounts",
      0.8: "0.8 times the photo's amounts",
      1.0: 'As shown',
      1.2: "1.2 times the photo's amounts",
      1.4: "1.4 times the photo's amounts",
    };
    for (final MapEntry(key: factor, value: label) in spoken.entries) {
      expect(
        tester.getSemantics(_chip(factor)),
        isSemantics(
          label: label,
          hasSelectedState: true,
          isSelected: factor == 1.0,
        ),
      );
    }
    await _tapChip(tester, 1.2);
    expect(tester.getSemantics(_chip(1.2)), isSemantics(isSelected: true));
    handle.dispose();
  });

  testWidgets('a new read starts "As shown", with nothing set by the user', (
    tester,
  ) async {
    await _open(tester);
    await _readPhoto(tester);
    await _step(tester, 0);
    await _tapChip(tester, 0.6);

    await _readPhoto(tester);
    expect(tester.widget<ChoiceChip>(_chip(1.0)).selected, isTrue);
    expect(_amount('150 g'), findsOneWidget);
    await _tapChip(tester, 0.8);
    expect(_amount('120 g'), findsOneWidget);
    expect(_amount('80 g'), findsOneWidget);
    expect(find.text(DishStrings.setByYou), findsNothing);
  });

  testWidgets('a breakdown keeps the size: its foods scale back with the '
      'rest, the dish\'s portion with them', (tester) async {
    await _open(tester);
    await _readPhoto(tester, const [
      ParsedMealItem(query: 'plov', quantity: 400, unit: 'g'),
      ParsedMealItem(query: 'salad', quantity: 100, unit: 'g'),
    ]);
    await _tapChip(tester, 0.8);
    expect(_amount('320 g'), findsOneWidget);

    final plov = (_bloc.state as BulkAddLoadedState).rows.first;
    // weighed for the 320 g the row shows
    _bloc.add(
      ReplaceRowWithBreakdownEvent(
        plov.resolved,
        DishBreakdown('plov', [
          _resolved(
            const ParsedMealItem(query: 'rice', quantity: 200, unit: 'g'),
          ),
          _resolved(
            const ParsedMealItem(query: 'lamb', quantity: 120, unit: 'g'),
          ),
        ]),
        asked: plov,
      ),
    );
    await tester.pumpAndSettle();
    expect(_amount('200 g'), findsOneWidget);
    expect(find.text('${DishStrings.portion} 320 g'), findsOneWidget);
    expect(tester.widget<ChoiceChip>(_chip(0.8)).selected, isTrue);
    expect(find.text(DishStrings.setByYou), findsNothing);

    await _tapChip(tester, 1.0);
    expect(_amount('250 g'), findsOneWidget);
    expect(_amount('150 g'), findsOneWidget);
    expect(_amount('100 g'), findsOneWidget);
    expect(find.text('${DishStrings.portion} 400 g'), findsOneWidget);
  });

  testWidgets("a dish's portion set by the user sets all its foods", (
    tester,
  ) async {
    final group = Object();
    DishIngredientItem food(String name, double grams) => DishIngredientItem(
      query: name,
      quantity: grams,
      unit: 'g',
      dish: 'bowl',
      group: group,
    );
    await _open(tester);
    await _readPhoto(tester, [
      food('rice', 200),
      food('chicken', 150),
      const ParsedMealItem(query: 'salad', quantity: 100, unit: 'g'),
    ]);
    await tester.tap(find.byKey(const ValueKey('bulk-add-dish-more')));
    await tester.pumpAndSettle();
    expect(find.text('${DishStrings.portion} 375 g'), findsOneWidget);

    await _tapChip(tester, 0.6);
    expect(find.text('${DishStrings.portion} 375 g'), findsOneWidget);
    expect(_amount('60 g'), findsOneWidget);
    expect(find.text(DishStrings.setByYou), findsNWidgets(2));
  });
}
