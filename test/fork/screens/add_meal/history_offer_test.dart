import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
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
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/fork/bulk/photo_meal_memory.dart';
import 'package:opennutritracker/fork/bulk/photo_meal_memory_store.dart';
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

class _Resolver implements ResolveParsedMealsUseCase {
  @override
  Future<List<ResolvedMealItem>> resolve(
    List<ParsedMealItem> items, {
    bool fromPhoto = false,
  }) async => [
    for (final item in items)
      ResolvedMealItem(
        parsed: item,
        candidates: [_meal(item.query)],
        selectedIndex: 0,
        confidence: 1,
      ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PhotoReader implements ReadMealPhotoUseCase {
  List<ParsedMealItem> items = const [];

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

class _TextReader implements ReadMealTextUseCase {
  @override
  Future<MealTextReading> read(String input, {String? localeCode}) async =>
      const MealTextReading(
        MealTextParseResult(items: [_rice, _chicken], errors: []),
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

/// The memory in a list.
class _Memory implements PhotoMealMemoryStore {
  final kept = <PhotoMealRecord>[];

  @override
  Future<List<PhotoMealRecord>> records({DateTime? now}) async => [...kept];

  @override
  Future<void> add(PhotoMealRecord record, {DateTime? now}) async =>
      kept.add(record);

  @override
  Future<void> clear() async => kept.clear();
}

/// A memory whose box cannot be opened.
class _BrokenMemory implements PhotoMealMemoryStore {
  @override
  Future<List<PhotoMealRecord>> records({DateTime? now}) =>
      Future.error(StateError('no box'));

  @override
  Future<void> add(PhotoMealRecord record, {DateTime? now}) =>
      Future.error(StateError('no box'));

  @override
  Future<void> clear() => Future.error(StateError('no box'));
}

class _MealDetailBloc extends Fake implements MealDetailBloc {
  static var written = 0;

  @override
  Future<IntakeEntity?> addIntake(
    BuildContext context,
    String unit,
    String amountText,
    IntakeTypeEntity intakeTypeEntity,
    MealEntity meal,
    DateTime day,
  ) async => IntakeEntity(
    id: 'intake-${++written}',
    unit: unit,
    amount: double.parse(amountText),
    type: intakeTypeEntity,
    meal: meal,
    dateTime: day,
  );
}

class _HomeBloc extends Fake implements HomeBloc {
  @override
  void add(HomeEvent event) {}
}

class _DiaryBloc extends Fake implements DiaryBloc {
  @override
  void add(DiaryEvent event) {}
}

class _CalendarDayBloc extends Fake implements CalendarDayBloc {
  @override
  void add(CalendarDayEvent event) {}
}

final _getIt = GetIt.instance;
late BulkAddBloc _bloc;
late _PhotoReader _reader;
late _Memory _memory;

final _today = DateUtils.dateOnly(DateTime.now());

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
                IntakeTypeEntity.dinner,
                _today,
                false,
              ),
            ),
            builder: (_) => const BulkAddScreen(),
          ),
  ),
);

const _rice = ParsedMealItem(query: 'rice', quantity: 150, unit: 'g');
const _chicken = ParsedMealItem(query: 'chicken', quantity: 100, unit: 'g');
const _salad = ParsedMealItem(query: 'salad', quantity: 80, unit: 'g');

/// The dinner the user corrected [daysAgo] days ago: more rice and chicken
/// than the photo shows, and no salad.
PhotoMealRecord _dinner({int daysAgo = 7, bool corrected = true}) {
  final day = DateTime(_today.year, _today.month, _today.day - daysAgo);
  PhotoMealFood food(String name, double grams) =>
      PhotoMealFood(key: name, name: name, amount: grams, kcal: grams);
  return PhotoMealRecord(
    day: day,
    loggedAt: day.add(const Duration(hours: 19)),
    slot: 'dinner',
    foods: [food('rice', 300), food('chicken', 200)],
    kcal: 500,
    corrected: corrected,
  );
}

Future<void> _register() async {
  await _getIt.reset();
  _reader = _PhotoReader();
  _bloc = BulkAddBloc(_Resolver(), _TextReader(), _reader);
  _getIt
    ..registerLazySingleton<AiCredentialStorage>(
      () => AiCredentialStorage(_EmptyStorage()),
    )
    ..registerSingleton<BulkAddBloc>(_bloc)
    ..registerFactory<MealDetailBloc>(_MealDetailBloc.new)
    ..registerFactory<HomeBloc>(_HomeBloc.new)
    ..registerFactory<DiaryBloc>(_DiaryBloc.new)
    ..registerFactory<CalendarDayBloc>(_CalendarDayBloc.new);
}

Future<void> _open(WidgetTester tester, {double textScale = 1}) async {
  if (textScale == 1) {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
  } else {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
  }
  addTearDown(tester.view.reset);
  await _register();
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: _app(),
    ),
  );
  tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/bulk');
  await tester.pumpAndSettle();
}

Future<void> _readPhoto(
  WidgetTester tester, [
  List<ParsedMealItem> items = const [_rice, _chicken, _salad],
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

Finder _amount(String text) =>
    find.descendant(of: find.byType(OutlinedButton), matching: find.text(text));

List<String> _amounts() => [
  for (final row in (_bloc.state as BulkAddLoadedState).rows) row.amountText,
];

Finder _chip(double factor) =>
    find.byKey(ValueKey('bulk-add-meal-size-$factor'));

final _use = find.byKey(const ValueKey('bulk-add-history-use'));
final _undo = find.byKey(const ValueKey('bulk-add-history-undo'));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _log(WidgetTester tester) async {
  await _tap(tester, find.widgetWithIcon(FilledButton, Icons.add_rounded));
}

void main() {
  setUp(() {
    final totals = forkDayTotals;
    forkDayTotals = (_) async => (
      eaten: (kcal: 1000.0, carbs: 100.0, fat: 40.0, protein: 60.0),
      goal: (kcal: 2400.0, carbs: 260.0, fat: 80.0, protein: 150.0),
    );
    final memory = forkPhotoMealMemory;
    _memory = _Memory();
    forkPhotoMealMemory = () => _memory;
    addTearDown(() {
      forkDayTotals = totals;
      forkPhotoMealMemory = memory;
    });
  });

  tearDown(() async => _getIt.reset());

  testWidgets('a photo like a corrected dinner offers its amounts: when, '
      'and what the meal comes to with them', (tester) async {
    _memory.kept.add(_dinner());
    await _open(tester);
    await _readPhoto(tester);

    final day = DateFormat.MMMEd(
      'en_US',
    ).format(DateTime(_today.year, _today.month, _today.day - 7));
    expect(find.text('Like your dinner on $day'), findsOneWidget);
    // rice 300 and chicken 200 then, the salad as the photo shows it
    expect(find.text('Your amounts then: 580 kcal'), findsOneWidget);
    expect(find.text(DishStrings.historyUse), findsOneWidget);
    // above the Size
    expect(
      tester.getTopLeft(_use).dy,
      lessThan(tester.getTopLeft(find.text(DishStrings.mealSize)).dy),
    );
    expect(tester.getSize(_use).height, greaterThanOrEqualTo(48));
  });

  testWidgets('"yesterday" and "today" where true', (tester) async {
    _memory.kept.add(_dinner(daysAgo: 1));
    await _open(tester);
    await _readPhoto(tester);
    expect(find.text('Like your dinner yesterday'), findsOneWidget);

    _memory.kept
      ..clear()
      ..add(_dinner(daysAgo: 0));
    await _readPhoto(tester);
    expect(find.text('Like your dinner today'), findsOneWidget);
  });

  testWidgets('nothing offered from a meal not corrected, nor on typed text', (
    tester,
  ) async {
    _memory.kept.add(_dinner(corrected: false));
    await _open(tester);
    await _readPhoto(tester);
    expect(find.text(DishStrings.mealSize), findsOneWidget);
    expect(_use, findsNothing);

    _memory.kept
      ..clear()
      ..add(_dinner());
    await tester.enterText(find.byType(TextField).first, 'rice and chicken');
    await tester.pump();
    await tester.tap(find.widgetWithIcon(FilledButton, Icons.search));
    await tester.pumpAndSettle();
    expect(_amount('150 g'), findsOneWidget);
    expect(_use, findsNothing);
  });

  testWidgets('one tap sets the shared rows as new bases: the others stay, '
      'none is set by the user, and the Size scales from them', (tester) async {
    final semantics = tester.ensureSemantics();
    _memory.kept.add(_dinner());
    await _open(tester);
    await _readPhoto(tester);
    await _tap(tester, _chip(1.2));
    expect(_amounts(), ['180', '120', '96']);
    tester.takeAnnouncements();

    await _tap(tester, _use);
    expect(_amounts(), ['300', '200', '96']);
    expect(tester.widget<ChoiceChip>(_chip(1.0)).selected, isTrue);
    final day = DateFormat.MMMEd(
      'en_US',
    ).format(DateTime(_today.year, _today.month, _today.day - 7));
    expect(find.text('Using your amounts from $day'), findsOneWidget);
    expect(_use, findsNothing);
    expect(
      tester.takeAnnouncements().map((a) => a.message),
      contains('Meal now 596 kcal'),
    );
    final rows = (_bloc.state as BulkAddLoadedState).rows;
    expect(rows.any((row) => row.amountEditedByUser), isFalse);

    await _tap(tester, _chip(0.8));
    expect(_amounts(), ['240', '160', '77']);
    expect(find.text(DishStrings.setByYou), findsNothing);
    semantics.dispose();
  });

  testWidgets('Undo puts back the photo\'s amounts and the size before', (
    tester,
  ) async {
    _memory.kept.add(_dinner());
    await _open(tester);
    await _readPhoto(tester);
    await _tap(tester, _chip(1.2));
    await _tap(tester, _use);
    await _tap(tester, _chip(0.6));
    expect(_amounts(), ['180', '120', '58']);

    await _tap(tester, _undo);
    expect(_amounts(), ['180', '120', '96']);
    expect(tester.widget<ChoiceChip>(_chip(1.2)).selected, isTrue);
    expect(_use, findsOneWidget);
    await _tap(tester, _chip(1.0));
    expect(_amounts(), ['150', '100', '80']);
  });

  testWidgets('a row the user set keeps its amount', (tester) async {
    _memory.kept.add(_dinner());
    await _open(tester);
    await _readPhoto(tester);
    await _tap(tester, find.byKey(const ValueKey('bulk-add-more-1')));
    expect(_amounts(), ['150', '110', '80']);
    await _tap(tester, _use);
    expect(_amounts(), ['300', '110', '80']);
  });

  testWidgets('the amount question on a row that took an amount goes, and '
      'Undo does not bring it back', (tester) async {
    _memory.kept.add(_dinner());
    await _open(tester);
    await _readPhoto(tester);
    final question = find.byKey(const ValueKey('bulk-add-amount-question-0'));
    expect(question, findsOneWidget);

    await _tap(tester, _use);
    expect(question, findsNothing);
    await _tap(tester, _undo);
    expect(question, findsNothing);
  });

  testWidgets('the offer goes once fewer than 2 of its foods are left in', (
    tester,
  ) async {
    _memory.kept.add(_dinner());
    await _open(tester);
    await _readPhoto(tester);
    expect(_use, findsOneWidget);
    _bloc.add(const ToggleRowSkippedEvent(1));
    await tester.pumpAndSettle();
    expect(_use, findsNothing);
    _bloc.add(const ToggleRowSkippedEvent(1));
    await tester.pumpAndSettle();
    expect(_use, findsOneWidget);
  });

  group('Log keeps the photo meal', () {
    // As a file run before this one in the bundle leaves it: Hive set up
    // on disk, so the meal's group goes to a box whose opening never ends
    // in a widget test's fake time. Keeping the meal must not wait on it.
    setUp(() {
      Hive.init(Directory.systemTemp.createTempSync('history_offer').path);
    });

    testWidgets('as the photo showed it: not corrected', (tester) async {
      await _open(tester);
      await _readPhoto(tester);
      await _log(tester);
      final record = _memory.kept.single;
      expect(record.corrected, isFalse);
      expect(record.slot, 'dinner');
      expect(record.day, _today);
      expect(record.foods.map((f) => f.key), ['rice', 'chicken', 'salad']);
      expect(record.foods.map((f) => f.amount), [150, 100, 80]);
      expect(record.kcal, 330);
      expect(record.dish, isNull);
    });

    testWidgets('at a size other than "As shown": corrected', (tester) async {
      await _open(tester);
      await _readPhoto(tester);
      await _tap(tester, _chip(0.8));
      await _log(tester);
      expect(_memory.kept.single.corrected, isTrue);
      expect(_memory.kept.single.foods.map((f) => f.amount), [120, 80, 64]);
    });

    testWidgets('a size chosen and put back: not corrected', (tester) async {
      await _open(tester);
      await _readPhoto(tester);
      await _tap(tester, _chip(0.8));
      await _tap(tester, _chip(1.0));
      await _log(tester);
      expect(_memory.kept.single.corrected, isFalse);
    });

    testWidgets('with an amount stepped: corrected', (tester) async {
      await _open(tester);
      await _readPhoto(tester);
      await _tap(tester, find.byKey(const ValueKey('bulk-add-more-2')));
      await _log(tester);
      expect(_memory.kept.single.corrected, isTrue);
    });

    testWidgets('the question answered with the photo\'s own amount: not '
        'corrected; with another: corrected', (tester) async {
      await _open(tester);
      await _readPhoto(tester);
      final estimate = find.byWidgetPredicate(
        (w) => w is ChoiceChip && w.selected,
        description: 'the chosen answer',
      );
      await _tap(
        tester,
        find.descendant(
          of: find.byKey(const ValueKey('bulk-add-amount-question-0')),
          matching: estimate,
        ),
      );
      await _log(tester);
      expect(_memory.kept.single.corrected, isFalse);

      await _open(tester);
      await _readPhoto(tester);
      await _tap(
        tester,
        find.byKey(const ValueKey('bulk-add-amount-choice-0-0')),
      );
      await _log(tester);
      expect(_memory.kept.last.corrected, isTrue);
    });

    testWidgets('with earlier amounts used: corrected, at those amounts', (
      tester,
    ) async {
      _memory.kept.add(_dinner());
      await _open(tester);
      await _readPhoto(tester);
      await _tap(tester, _use);
      await _log(tester);
      final record = _memory.kept.last;
      expect(record.corrected, isTrue);
      expect(record.foods.map((f) => f.amount), [300, 200, 80]);
    });

    testWidgets('a memory that fails leaves the meal logged', (tester) async {
      forkPhotoMealMemory = _BrokenMemory.new;
      await _open(tester);
      await _readPhoto(tester);
      _MealDetailBloc.written = 0;
      await _log(tester);
      expect(_MealDetailBloc.written, 3);
      expect(tester.takeException(), isNull);
    });

    testWidgets('not from typed text', (tester) async {
      await _open(tester);
      await tester.enterText(find.byType(TextField).first, 'rice and chicken');
      await tester.pump();
      await tester.tap(find.widgetWithIcon(FilledButton, Icons.search));
      await tester.pumpAndSettle();
      await _log(tester);
      expect(_memory.kept, isEmpty);
    });
  });

  testWidgets('at twice the text size on a narrow phone, nothing is cut off', (
    tester,
  ) async {
    _memory.kept.add(_dinner());
    await _open(tester, textScale: 2);
    await _readPhoto(tester);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(_use);
    await tester.pumpAndSettle();
    expect(tester.getSize(_use).height, greaterThanOrEqualTo(48));
    for (final text in [
      DishStrings.historyUse,
      'Your amounts then: 580 kcal',
    ]) {
      expect(
        tester.renderObject<RenderParagraph>(find.text(text)).didExceedMaxLines,
        isFalse,
      );
    }
    final like = find.textContaining('Like your dinner on');
    expect(
      tester.renderObject<RenderParagraph>(like).didExceedMaxLines,
      isFalse,
    );

    await _tap(tester, _use);
    expect(tester.takeException(), isNull);
    expect(
      tester
          .renderObject<RenderParagraph>(
            find.textContaining('Using your amounts from'),
          )
          .didExceedMaxLines,
      isFalse,
    );
    expect(tester.getSize(_undo).height, greaterThanOrEqualTo(48));
  });
}
