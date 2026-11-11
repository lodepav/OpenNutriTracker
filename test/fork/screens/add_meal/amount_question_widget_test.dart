import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_portion_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_photo_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_text_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/dish/dish_breakdown_rows.dart';
import 'package:opennutritracker/fork/dish/dish_strings.dart';
import 'package:opennutritracker/fork/screens/add_meal/bulk_add_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

/// [kcal100] per 100 g; [portions] for a counted food.
MealEntity _meal(
  String name, {
  double kcal100 = 100,
  List<MealPortionEntity> portions = const [],
}) => MealEntity(
  code: name,
  name: name,
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: portions.isEmpty ? null : portions.first.gramWeight,
  servingUnit: portions.isEmpty ? null : 'g',
  servingSize: portions.isEmpty ? null : portions.first.label,
  source: MealSourceEntity.fdc,
  portions: portions,
  nutriments: MealNutrimentsEntity(
    energyKcal100: kcal100,
    carbohydrates100: 0,
    fat100: 0,
    proteins100: 0,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  ),
);

/// Rice 100 kcal and chicken 200 kcal per 100 g, so chicken's 100 g
/// outweighs rice's 160 g; bread counted in slices of 32 g.
final _foods = {
  'rice': _meal('Rice'),
  'chicken': _meal('Chicken breast', kcal100: 200),
  'salad': _meal('Salad', kcal100: 20),
  'bread': _meal(
    'Bread',
    kcal100: 250,
    portions: const [
      MealPortionEntity(label: '1 slice', gramWeight: 32, localized: true),
    ],
  ),
};

class _Resolver implements ResolveParsedMealsUseCase {
  @override
  Future<List<ResolvedMealItem>> resolve(
    List<ParsedMealItem> items, {
    bool fromPhoto = false,
  }) async => [
    for (final item in items)
      ResolvedMealItem(
        parsed: item,
        candidates: [_foods[item.query] ?? _meal(item.query)],
        selectedIndex: 0,
        confidence: 1,
      ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PhotoReader implements ReadMealPhotoUseCase {
  List<ParsedMealItem> items = const [];
  final notes = <String?>[];

  @override
  Future<MealPhotoReadResult> read(
    MealPhoto photo, {
    String? localeCode,
    String? note,
  }) async {
    notes.add(note);
    return MealPhotoRead(MealTextParseResult(items: items, errors: const []));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TextReader implements ReadMealTextUseCase {
  @override
  Future<MealTextReading> read(String input, {String? localeCode}) async =>
      const MealTextReading(
        MealTextParseResult(
          items: [
            ParsedMealItem(query: 'rice', quantity: 160, unit: 'g'),
            ParsedMealItem(query: 'chicken', quantity: 100, unit: 'g'),
          ],
          errors: [],
        ),
        usedModel: true,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MapStorage implements FlutterSecureStorage {
  final Map<String, String> values;

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
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

final _getIt = GetIt.instance;
late BulkAddBloc _bloc;
late _PhotoReader _reader;

Widget _app({String? sharedPhotoPath}) =>
    ChangeNotifierProvider<EnergyUnitProvider>(
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
        onGenerateRoute: (settings) =>
            settings.name == NavigationOptions.mainRoute
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
                    sharedPhotoPath: sharedPhotoPath,
                  ),
                ),
                builder: (_) => const BulkAddScreen(),
              ),
      ),
    );

const _rice = ParsedMealItem(query: 'rice', quantity: 160, unit: 'g');
const _chicken = ParsedMealItem(query: 'chicken', quantity: 100, unit: 'g');

/// With a photo model set up when [photos], so a shared photo can be sent
/// with a note.
Future<void> _register({bool photos = false}) async {
  await _getIt.reset();
  _reader = _PhotoReader();
  _bloc = BulkAddBloc(_Resolver(), _TextReader(), _reader);
  _getIt
    ..registerLazySingleton<AiCredentialStorage>(
      () => AiCredentialStorage(
        _MapStorage(
          photos
              ? {
                  'AiApiKeyTag.openrouter': 'sk-or-test',
                  'AiAssistEnabledTag': 'true',
                  'AiProviderTag': 'openrouter',
                }
              : {},
        ),
      ),
    )
    ..registerSingleton<BulkAddBloc>(_bloc);
}

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await _register();
  await tester.pumpWidget(_app());
  tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/bulk');
  await tester.pumpAndSettle();
}

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

Finder _question(int row) =>
    find.byKey(ValueKey('bulk-add-amount-question-$row'));

Finder _choice(int row, int i) =>
    find.byKey(ValueKey('bulk-add-amount-choice-$row-$i'));

List<String> _labels(WidgetTester tester, int row) => [
  for (var i = 0; _choice(row, i).evaluate().isNotEmpty; i++)
    (tester.widget<ChoiceChip>(_choice(row, i)).label as Text).data!,
];

int? _selected(WidgetTester tester, int row) {
  for (var i = 0; _choice(row, i).evaluate().isNotEmpty; i++) {
    if (tester.widget<ChoiceChip>(_choice(row, i)).selected) return i;
  }
  return null;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _size(double factor) =>
    find.byKey(ValueKey('bulk-add-meal-size-$factor'));

BulkAddRow _row(int index) => (_bloc.state as BulkAddLoadedState).rows[index];

void main() {
  setUpAll(() async {
    // the photo sheet reads the keep-photos flag from Hive, opened here
    // outside fake time
    Hive.init((await Directory.systemTemp.createTemp('amount_q')).path);
    final flags = await Hive.openBox<bool>('fork_flags', bytes: Uint8List(0));
    await flags.put('keepMealPhotos', false);
  });

  setUp(() async {
    final before = forkDayTotals;
    forkDayTotals = (_) async => (
      eaten: (kcal: 1000.0, carbs: 100.0, fat: 40.0, protein: 60.0),
      goal: (kcal: 2400.0, carbs: 260.0, fat: 80.0, protein: 150.0),
    );
    addTearDown(() => forkDayTotals = before);
  });

  tearDown(() async => _getIt.reset());

  testWidgets('asked on the row with the most energy only, the estimate '
      'chosen', (tester) async {
    await _open(tester);
    await _readPhoto(tester);
    expect(_question(1), findsOneWidget);
    expect(_question(0), findsNothing);
    expect(find.text('How much chicken breast was it?'), findsOneWidget);
    expect(_labels(tester, 1), ['50 g', '75 g', '100 g', '150 g']);
    expect(_selected(tester, 1), 2);
  });

  testWidgets('another chip sets the amount as the user\'s; a size then '
      'leaves it, "Set by you"', (tester) async {
    final semantics = tester.ensureSemantics();
    await _open(tester);
    await _readPhoto(tester);
    await _tap(tester, _choice(1, 3));
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('bulk-add-unit-1')),
              matching: find.byType(Text),
            ),
          )
          .data,
      '150 g',
    );
    expect(_row(1).amountText, '150');
    expect(_row(1).amountEditedByUser, isTrue);
    expect(_selected(tester, 1), 3);
    expect(find.text(DishStrings.amountAnswered), findsOneWidget);
    expect(find.text('How much chicken breast was it?'), findsNothing);
    expect(
      tester.takeAnnouncements().map((a) => a.message),
      contains('150 grams. Meal now 460 kcal'),
    );

    await _tap(tester, _size(0.6));
    expect(_row(0).amountText, '96');
    expect(_row(1).amountText, '150');
    expect(find.byKey(const ValueKey('bulk-add-set-by-you-1')), findsOneWidget);

    // a mis-tap corrected with one more
    await _tap(tester, _choice(1, 1));
    expect(_row(1).amountText, '75');
    expect(_selected(tester, 1), 1);
    semantics.dispose();
  });

  testWidgets('the chosen chip confirms the amount unchanged, and pins it', (
    tester,
  ) async {
    await _open(tester);
    await _readPhoto(tester);
    await _tap(tester, _choice(1, 2));
    expect(_row(1).amountText, '100');
    expect(find.text(DishStrings.amountAnswered), findsOneWidget);
    await _tap(tester, _size(1.4));
    expect(_row(0).amountText, '224');
    expect(_row(1).amountText, '100');
    expect(find.byKey(const ValueKey('bulk-add-set-by-you-1')), findsOneWidget);
  });

  testWidgets('with a size chosen first the chips stay the photo\'s, and an '
      'answer pins the row at its amount', (tester) async {
    await _open(tester);
    await _readPhoto(tester);
    await _tap(tester, _size(0.6));
    expect(_row(1).amountText, '60');
    expect(_labels(tester, 1), ['50 g', '75 g', '100 g', '150 g']);
    expect(_selected(tester, 1), 2);

    await _tap(tester, _choice(1, 1));
    expect(_row(1).amountText, '75');
    expect(find.byKey(const ValueKey('bulk-add-set-by-you-1')), findsOneWidget);
    await _tap(tester, _size(1.2));
    expect(_row(1).amountText, '75');
    expect(_row(0).amountText, '192');
  });

  testWidgets('an amount changed another way ends the question for good', (
    tester,
  ) async {
    await _open(tester);
    await _readPhoto(tester);
    await _tap(tester, find.byKey(const ValueKey('bulk-add-more-1')));
    expect(_question(1), findsNothing);
    expect(find.byType(ChoiceChip), findsNWidgets(5)); // the Size's only
    await _tap(tester, _size(0.8));
    await _tap(tester, _size(1.0));
    expect(_question(1), findsNothing);
    expect(_question(0), findsNothing);
  });

  testWidgets('left out, it goes; put back, it is there again', (tester) async {
    await _open(tester);
    await _readPhoto(tester);
    _bloc.add(const ToggleRowSkippedEvent(1));
    await tester.pumpAndSettle();
    expect(find.textContaining('How much'), findsNothing);
    _bloc.add(const ToggleRowSkippedEvent(1));
    await tester.pumpAndSettle();
    expect(_question(1), findsOneWidget);
  });

  testWidgets('not for typed text', (tester) async {
    await _open(tester);
    await tester.enterText(find.byType(TextField).first, 'rice, chicken');
    await tester.pump();
    await tester.tap(find.widgetWithIcon(FilledButton, Icons.search));
    await tester.pumpAndSettle();
    expect(find.text('100 g'), findsOneWidget);
    expect(find.textContaining('How much'), findsNothing);
  });

  testWidgets('counts for a food counted in slices', (tester) async {
    await _open(tester);
    await _readPhoto(tester, const [
      ParsedMealItem(query: 'salad', quantity: 100, unit: 'g'),
      ParsedMealItem(query: 'bread', quantity: 2),
    ]);
    expect(_row(1).unit, 'serving');
    expect(_labels(tester, 1), ['1 slice', '2 slices', '3 slices', '4 slices']);
    expect(_selected(tester, 1), 1);
    await _tap(tester, _choice(1, 2));
    expect(_row(1).amountText, '3');
    expect(_row(1).unit, 'serving');
  });

  testWidgets('on a row in grams of a counted food, the chosen count '
      'confirms the grams unchanged and pins the row; another count sets '
      'slices', (tester) async {
    await _open(tester);
    await _readPhoto(tester, const [
      ParsedMealItem(query: 'salad', quantity: 100, unit: 'g'),
      ParsedMealItem(query: 'bread', quantity: 70, unit: 'g'),
    ]);
    expect(_row(1).unit, 'g');
    expect(_labels(tester, 1), ['1 slice', '2 slices', '3 slices', '4 slices']);
    expect(_selected(tester, 1), 1);

    await _tap(tester, _choice(1, 1));
    expect(_row(1).amountText, '70');
    expect(_row(1).unit, 'g');
    expect(_row(1).unitChosenByUser, isFalse);
    expect(find.text(DishStrings.amountAnswered), findsOneWidget);
    await _tap(tester, _size(0.6));
    expect(_row(0).amountText, '60');
    expect(_row(1).amountText, '70');
    expect(find.byKey(const ValueKey('bulk-add-set-by-you-1')), findsOneWidget);

    await _tap(tester, _choice(1, 2));
    expect(_row(1).amountText, '3');
    expect(_row(1).unit, 'serving');
  });

  testWidgets('on a dish\'s food, its portion following', (tester) async {
    final group = Object();
    DishIngredientItem food(String name, double grams) => DishIngredientItem(
      query: name,
      quantity: grams,
      unit: 'g',
      dish: 'bowl',
      group: group,
    );
    await _open(tester);
    await _readPhoto(tester, [food('rice', 160), food('chicken', 100)]);
    expect(find.text('${DishStrings.portion} 260 g'), findsOneWidget);
    expect(_question(1), findsOneWidget);
    await _tap(tester, _choice(1, 3));
    expect(find.text('${DishStrings.portion} 310 g'), findsOneWidget);
  });

  testWidgets('chips are spoken with their unit, chosen state exposed, the '
      'question read first', (tester) async {
    final handle = tester.ensureSemantics();
    await _open(tester);
    await _readPhoto(tester);
    expect(
      tester.getSemantics(_choice(1, 0)),
      isSemantics(label: '50 grams', hasSelectedState: true, isSelected: false),
    );
    expect(
      tester.getSemantics(_choice(1, 2)),
      isSemantics(label: '100 grams', hasSelectedState: true, isSelected: true),
    );
    final question = tester.getRect(
      find.text('How much chicken breast was it?'),
    );
    expect(
      question.bottom,
      lessThanOrEqualTo(tester.getRect(_choice(1, 0)).top),
    );
    handle.dispose();
  });

  testWidgets('at twice the text size on a 360 dp phone it wraps, nothing '
      'cut off', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
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
    await _readPhoto(tester, const [
      ParsedMealItem(query: 'salad', quantity: 100, unit: 'g'),
      ParsedMealItem(query: 'bread', quantity: 2),
    ]);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      _question(1),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    final tops = <double>{};
    final rects = <Rect>[];
    for (var i = 0; i < 4; i++) {
      final label = find.descendant(
        of: _choice(1, i),
        matching: find.byType(RichText),
      );
      expect(
        tester.renderObject<RenderParagraph>(label.first).didExceedMaxLines,
        isFalse,
      );
      final chip = tester.getRect(_choice(1, i));
      expect(chip.height, greaterThanOrEqualTo(48));
      expect(chip.right, lessThanOrEqualTo(360));
      tops.add(chip.top);
      rects.add(chip);
    }
    expect(tops.length, greaterThan(1), reason: 'the chips took more lines');
    // 8 dp between the rows, as between the Size's: no two targets touch
    final first = rects.where((r) => r.top == tops.first);
    final next = rects.firstWhere((r) => r.top > tops.first);
    for (final above in first) {
      expect(next.top - above.bottom, greaterThanOrEqualTo(8));
    }
    expect(
      tester
          .renderObject<RenderParagraph>(find.text('How much bread was it?'))
          .didExceedMaxLines,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('none on a weighed plate', (tester) async {
    await _register(photos: true);
    final shared = (await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('amount_q_shared');
      return File('${dir.path}/shared.png')
        ..writeAsBytesSync(base64Decode(_onePixelPng));
    }))!;
    Future<void> settleUntil(bool Function() done) async {
      for (var i = 0; i < 100 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pumpAndSettle();
      }
    }

    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(sharedPhotoPath: shared.path));
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/bulk');
    final readShared = find.text('Use the shared photo');
    await settleUntil(() => readShared.evaluate().isNotEmpty);
    await tester.tap(readShared);
    final staged = find.bySemanticsIdentifier('bulk-add-photo-staged');
    await settleUntil(() => staged.evaluate().isNotEmpty);

    _reader.items = const [_rice, _chicken];
    await tester.enterText(find.byType(TextField).first, '260 g');
    await tester.pump();
    await tester.tap(find.bySemanticsIdentifier('bulk-add-parse'));
    await tester.pumpAndSettle();
    expect(_reader.notes.last, '260 g');
    expect(find.text('100 g'), findsOneWidget);
    expect(find.textContaining('How much'), findsNothing);
  });
}
