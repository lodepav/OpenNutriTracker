// The review screen driven with a photo's read, for the widget tests of
// D48 and D49; as amount_question_widget_test.dart drives it.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
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
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_photo_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_text_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/screens/add_meal/bulk_add_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

/// [kcal100] per 100 g; [serving] the table's serving in grams.
MealEntity reviewFood(String name, {double kcal100 = 100, double? serving}) =>
    MealEntity(
      code: name,
      name: name,
      url: null,
      mealQuantity: null,
      mealUnit: 'g',
      servingQuantity: serving,
      servingUnit: serving == null ? null : 'g',
      servingSize: serving == null ? null : '1 cup',
      source: MealSourceEntity.fdc,
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

/// The foods the resolver matches, by the model's words; another word
/// matches a food of its own name.
final reviewFoods = <String, MealEntity>{};

class _Resolver implements ResolveParsedMealsUseCase {
  @override
  Future<List<ResolvedMealItem>> resolve(
    List<ParsedMealItem> items, {
    bool fromPhoto = false,
  }) async => [
    for (final item in items)
      ResolvedMealItem(
        parsed: item,
        candidates: [reviewFoods[item.query] ?? reviewFood(item.query)],
        selectedIndex: 0,
        confidence: 1,
      ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ReviewPhotoReader implements ReadMealPhotoUseCase {
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
            ParsedMealItem(query: 'salad', quantity: 400, unit: 'g'),
            ParsedMealItem(query: 'egg, fried', quantity: 100, unit: 'g'),
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
late BulkAddBloc reviewBloc;
late ReviewPhotoReader reviewReader;

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

/// With a photo model set up when [photos], so a shared photo can be sent
/// with a note.
Future<void> _register({bool photos = false}) async {
  await _getIt.reset();
  reviewReader = ReviewPhotoReader();
  reviewBloc = BulkAddBloc(_Resolver(), _TextReader(), reviewReader);
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
    ..registerSingleton<BulkAddBloc>(reviewBloc);
}

/// A new bloc for the screen's next visit, as the app's factory gives one;
/// the screen closes its bloc as it leaves.
void renewReviewBloc() {
  reviewBloc = BulkAddBloc(_Resolver(), _TextReader(), reviewReader);
  _getIt
    ..unregister<BulkAddBloc>()
    ..registerSingleton<BulkAddBloc>(reviewBloc);
}

/// Hive for the photo sheet's keep-photos flag, and today's totals; call
/// from `main`.
void setUpReviewHarness(String name) {
  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp(name)).path);
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
}

void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The screen open, nothing read yet.
Future<void> openReview(WidgetTester tester) async {
  _tallView(tester);
  await _register();
  await tester.pumpWidget(_app());
  tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/bulk');
  await tester.pumpAndSettle();
}

/// A photo read as [items], with no note.
Future<void> readReviewPhoto(
  WidgetTester tester,
  List<ParsedMealItem> items,
) async {
  reviewReader.items = items;
  reviewBloc.add(
    ReadMealPhotoEvent(
      photo: MealPhoto(bytes: Uint8List.fromList([1]), mediaType: 'image/webp'),
      usesImperialUnits: false,
    ),
  );
  await tester.pumpAndSettle();
}

/// The screen open with a shared photo waiting by the box, to be sent with
/// what is typed there as its note.
Future<void> openWithStagedPhoto(WidgetTester tester) async {
  await _register(photos: true);
  final shared = (await tester.runAsync(() async {
    final dir = await Directory.systemTemp.createTemp('review_shared');
    return File('${dir.path}/shared.png')
      ..writeAsBytesSync(base64Decode(_onePixelPng));
  }))!;
  _tallView(tester);
  await tester.pumpWidget(_app(sharedPhotoPath: shared.path));
  await tester.pumpAndSettle();
  tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/bulk');
  final readShared = find.text('Use the shared photo');
  await settleUntil(tester, () => readShared.evaluate().isNotEmpty);
  await tester.tap(readShared);
  final staged = find.bySemanticsIdentifier('bulk-add-photo-staged');
  await settleUntil(tester, () => staged.evaluate().isNotEmpty);
}

/// Pumps with real time between, until [done].
Future<void> settleUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();
  }
}

/// The waiting photo sent, read as [items].
Future<void> sendStagedPhoto(
  WidgetTester tester,
  List<ParsedMealItem> items,
) async {
  reviewReader.items = items;
  await tester.tap(find.bySemanticsIdentifier('bulk-add-parse'));
  await tester.pumpAndSettle();
}

Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder mealSize(double factor) =>
    find.byKey(ValueKey('bulk-add-meal-size-$factor'));

BulkAddRow reviewRow(int index) =>
    (reviewBloc.state as BulkAddLoadedState).rows[index];

List<BulkAddRow> reviewRows() => (reviewBloc.state as BulkAddLoadedState).rows;
