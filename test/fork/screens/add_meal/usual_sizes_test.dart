import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
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

/// The memory in a list; [gate], while set, holds its reading back.
class _Memory implements PhotoMealMemoryStore {
  final kept = <PhotoMealRecord>[];
  Completer<void>? gate;

  @override
  Future<List<PhotoMealRecord>> records({DateTime? now}) async {
    await gate?.future;
    return [...kept];
  }

  @override
  Future<void> add(PhotoMealRecord record, {DateTime? now}) async =>
      kept.add(record);
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

/// The dinner the user corrected a week ago, kept before sizes were: more
/// rice and chicken than the photo shows, and no salad.
PhotoMealRecord _dinner() {
  final day = DateTime(_today.year, _today.month, _today.day - 7);
  PhotoMealFood food(String name, double grams) =>
      PhotoMealFood(key: name, name: name, amount: grams, kcal: grams);
  return PhotoMealRecord(
    day: day,
    loggedAt: day.add(const Duration(hours: 19)),
    slot: 'dinner',
    foods: [food('rice', 300), food('chicken', 200)],
    kcal: 500,
    corrected: true,
  );
}

/// A dinner logged [daysAgo] days ago at [size] against the photo, the
/// rice at [rice] times the rest: the photo's 150 g rice and 100 g
/// chicken. Not corrected, so never offered as earlier amounts.
PhotoMealRecord _sized(int daysAgo, {double size = 0.8, double rice = 0.7}) {
  final day = DateTime(_today.year, _today.month, _today.day - daysAgo);
  PhotoMealFood food(String name, double grams, double photo) => PhotoMealFood(
    key: name,
    name: name,
    amount: grams,
    kcal: grams,
    photoAmount: photo,
  );
  return PhotoMealRecord(
    day: day,
    loggedAt: day.add(const Duration(hours: 19)),
    slot: 'dinner',
    foods: [
      food('rice', 150 * size * rice, 150),
      food('chicken', 100 * size, 100),
    ],
    kcal: 0,
    corrected: false,
    size: size,
  );
}

/// [count] such dinners.
void _keepSized(int count) {
  for (var i = 1; i <= count; i++) {
    _memory.kept.add(_sized(i));
  }
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

List<String> _amounts() => [
  for (final row in (_bloc.state as BulkAddLoadedState).rows) row.amountText,
];

Finder _chip(double factor) =>
    find.byKey(ValueKey('bulk-add-meal-size-$factor'));

final _use = find.byKey(const ValueKey('bulk-add-history-use'));
final _undo = find.byKey(const ValueKey('bulk-add-history-undo'));
final _line = find.byKey(const ValueKey('bulk-add-usual-sizes'));
final _usePhoto = find.byKey(const ValueKey('bulk-add-usual-photo'));
final _useUsual = find.byKey(const ValueKey('bulk-add-usual-return'));

const _said = 'Sized the way you usually correct: rice ×0.7 · whole meal ×0.8';

String _chipText(WidgetTester tester, double factor) =>
    (tester.widget<ChoiceChip>(_chip(factor)).label as Text).data!;

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

  testWidgets('after 3 like corrections the amounts arrive sized, the line '
      'says how, and 1× reads "Your usual"', (tester) async {
    final semantics = tester.ensureSemantics();
    _keepSized(3);
    await _open(tester);
    await _readPhoto(tester);

    // rice 150 × 0.8 × 0.7, chicken 100 × 0.8, salad 80 × 0.8
    expect(_amounts(), ['84', '80', '64']);
    final rows = (_bloc.state as BulkAddLoadedState).rows;
    expect(rows.any((row) => row.amountEditedByUser), isFalse);
    expect(find.text(_said), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Sized the way you usually correct: rice 0.7 times, '
        'whole meal 0.8 times',
      ),
      findsOneWidget,
    );
    expect(tester.getSize(_usePhoto).height, greaterThanOrEqualTo(48));
    // above the Size
    expect(
      tester.getTopLeft(_line).dy,
      lessThan(tester.getTopLeft(find.text(DishStrings.mealSize)).dy),
    );
    expect(_chipText(tester, 1.0), DishStrings.yourUsual);
    expect(tester.widget<ChoiceChip>(_chip(1.0)).selected, isTrue);
    expect(
      tester.getSemantics(_chip(0.8)),
      isSemantics(label: '0.8 times your usual amounts'),
    );
    expect(find.text(DishStrings.setByYou), findsNothing);
    semantics.dispose();
  });

  testWidgets('nothing with 2', (tester) async {
    _keepSized(2);
    await _open(tester);
    await _readPhoto(tester);
    expect(_amounts(), ['150', '100', '80']);
    expect(_line, findsNothing);
    expect(_chipText(tester, 1.0), DishStrings.asShown);
  });

  testWidgets('the sizes scale from the usual amounts', (tester) async {
    _keepSized(3);
    await _open(tester);
    await _readPhoto(tester);
    await _tap(tester, _chip(1.2));
    expect(_amounts(), ['101', '96', '77']);
    await _tap(tester, _chip(1.0));
    expect(_amounts(), ['84', '80', '64']);
  });

  testWidgets('the Size\'s hint says the sizes change the usual amounts, '
      'and a size over the usual whole-meal size what it comes to', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    _keepSized(3);
    await _open(tester);
    await _readPhoto(tester);
    final hint = find.byKey(const ValueKey('bulk-add-meal-size-hint'));
    expect(tester.widget<Text>(hint).data, DishStrings.sizesChangeUsual);

    await _tap(tester, _chip(0.8));
    expect(
      tester.widget<Text>(hint).data,
      '×0.8 of your usual · ×0.64 of the photo',
    );
    expect(
      tester.getSemantics(hint),
      isSemantics(
        label: "0.8 times your usual, 0.64 times the photo's amounts",
      ),
    );

    // the photo's amounts used: the hint as without usual sizes
    await _tap(tester, _usePhoto);
    expect(tester.widget<Text>(hint).data, DishStrings.sizeScalesUnset);
    semantics.dispose();
  });

  testWidgets('"Use the photo\'s amounts" puts them back, said, and the '
      'usual sizes can come back', (tester) async {
    final semantics = tester.ensureSemantics();
    _keepSized(3);
    await _open(tester);
    await _readPhoto(tester);
    await _tap(tester, _chip(1.2));
    tester.takeAnnouncements();

    await _tap(tester, _usePhoto);
    expect(_amounts(), ['150', '100', '80']);
    expect(find.text(DishStrings.usingPhotoAmounts), findsOneWidget);
    expect(_chipText(tester, 1.0), DishStrings.asShown);
    expect(tester.widget<ChoiceChip>(_chip(1.0)).selected, isTrue);
    expect(
      tester.takeAnnouncements().map((a) => a.message),
      contains('Meal now 330 kcal'),
    );
    final rows = (_bloc.state as BulkAddLoadedState).rows;
    expect(rows.any((row) => row.amountEditedByUser), isFalse);
    await _tap(tester, _chip(0.8));
    expect(_amounts(), ['120', '80', '64']);

    await _tap(tester, _useUsual);
    expect(_amounts(), ['101', '96', '77']);
    expect(tester.widget<ChoiceChip>(_chip(1.2)).selected, isTrue);
    expect(find.text(_said), findsOneWidget);
    expect(_chipText(tester, 1.0), DishStrings.yourUsual);
    semantics.dispose();
  });

  testWidgets('a row the user set stays as set, both ways', (tester) async {
    _keepSized(3);
    await _open(tester);
    await _readPhoto(tester);
    await _tap(tester, find.byKey(const ValueKey('bulk-add-more-1')));
    final set = _amounts()[1];
    expect(set, isNot('80'));

    await _tap(tester, _usePhoto);
    expect(_amounts(), ['150', set, '80']);
    await _tap(tester, _useUsual);
    expect(_amounts(), ['84', set, '64']);
  });

  testWidgets('a row the user set before the memory was read is left alone', (
    tester,
  ) async {
    _keepSized(3);
    final gate = _memory.gate = Completer<void>();
    await _open(tester);
    await _readPhoto(tester);
    await _tap(tester, find.byKey(const ValueKey('bulk-add-more-1')));
    final set = _amounts()[1];
    expect(set, isNot('100'));

    gate.complete();
    await tester.pumpAndSettle();
    expect(_amounts(), ['84', set, '64']);
    expect(find.text(_said), findsOneWidget);
  });

  testWidgets('the amount question asks around the usual amount', (
    tester,
  ) async {
    _keepSized(3);
    await _open(tester);
    await _readPhoto(tester);
    final chosen = find.descendant(
      of: find.byKey(const ValueKey('bulk-add-amount-question-0')),
      matching: find.byWidgetPredicate(
        (w) => w is ChoiceChip && w.selected,
        description: 'the chosen answer',
      ),
    );
    expect(((tester.widget<ChoiceChip>(chosen)).label as Text).data, '84 g');
  });

  testWidgets('the earlier amounts taken over the usual sizes: the line '
      'goes, the other foods go back to the photo\'s, and Undo brings the '
      'usual sizes back', (tester) async {
    _memory.kept.add(_dinner());
    _keepSized(3);
    await _open(tester);
    await _readPhoto(tester);
    expect(_amounts(), ['84', '80', '64']);
    expect(_line, findsOneWidget);
    // rice 300 and chicken 200 then, the salad at the photo's 80
    expect(find.text('Your amounts then: 580 kcal'), findsOneWidget);

    await _tap(tester, _use);
    expect(_amounts(), ['300', '200', '80']);
    expect(_line, findsNothing);
    expect(_chipText(tester, 1.0), DishStrings.yourAmounts);
    await _tap(tester, _chip(0.8));
    expect(_amounts(), ['240', '160', '64']);

    await _tap(tester, _undo);
    expect(_amounts(), ['84', '80', '64']);
    expect(find.text(_said), findsOneWidget);
    expect(_chipText(tester, 1.0), DishStrings.yourUsual);
  });

  group('Log keeps the photo\'s amounts and the size', () {
    // as in history_offer_test: the meal's group box never opens here
    setUp(() {
      Hive.init(Directory.systemTemp.createTempSync('usual_sizes').path);
    });

    testWidgets('as the photo showed it: the size 1', (tester) async {
      await _open(tester);
      await _readPhoto(tester);
      await _log(tester);
      final record = _memory.kept.single;
      expect(record.size, 1);
      expect(record.foods.map((f) => f.photoAmount), [150, 100, 80]);
      expect(record.foods.map((f) => f.amount), [150, 100, 80]);
    });

    testWidgets('with the usual sizes: the whole meal\'s, not corrected', (
      tester,
    ) async {
      _keepSized(3);
      await _open(tester);
      await _readPhoto(tester);
      await _log(tester);
      final record = _memory.kept.last;
      expect(record.size, closeTo(0.8, 1e-9));
      expect(record.foods.map((f) => f.photoAmount), [150, 100, 80]);
      expect(record.foods.map((f) => f.amount), [84, 80, 64]);
      expect(record.corrected, isFalse);
    });

    testWidgets('with the usual sizes and a Size: the two together', (
      tester,
    ) async {
      _keepSized(3);
      await _open(tester);
      await _readPhoto(tester);
      await _tap(tester, _chip(1.2));
      await _log(tester);
      expect(_memory.kept.last.size, closeTo(0.96, 1e-9));
      expect(_memory.kept.last.corrected, isTrue);
    });

    testWidgets('with the photo\'s amounts used: the Size alone', (
      tester,
    ) async {
      _keepSized(3);
      await _open(tester);
      await _readPhoto(tester);
      await _tap(tester, _usePhoto);
      await _tap(tester, _chip(0.6));
      await _log(tester);
      expect(_memory.kept.last.size, closeTo(0.6, 1e-9));
      expect(_memory.kept.last.foods.map((f) => f.amount), [90, 60, 48]);
    });

    testWidgets('none for a row whose unit the user changed, nor for a '
        'food left out', (tester) async {
      await _open(tester);
      await _readPhoto(tester);
      _bloc
        ..add(const ChangeRowUnitEvent(1, 'oz'))
        ..add(const ToggleRowSkippedEvent(2));
      await tester.pumpAndSettle();
      await _log(tester);
      final record = _memory.kept.single;
      expect(record.foods.map((f) => f.key), ['rice', 'chicken']);
      expect(record.foods.map((f) => f.photoAmount), [150, null]);
    });
  });
}
