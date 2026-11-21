import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_portion_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_photo_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_text_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/search_products_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/fork/leftovers/meal_groups.dart';
import 'package:opennutritracker/fork/screens/add_meal/bulk_add_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../helpers/test_l10n.dart';
import '../../helpers/ux_checks.dart';

/// The review's controls from the G2 critique: Find again, the Other match
/// list's energy, a visible Leave out, and why Log is disabled.

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

class _FakeSearch implements SearchProductsUseCase {
  final Map<String, List<MealEntity>> results;
  var searches = 0;

  _FakeSearch(this.results);

  @override
  Future<SearchProductsResult> searchOFFProductsByString(
    String searchString, {
    bool skipRemote = false,
  }) async {
    searches++;
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

MealEntity _food(
  String name, {
  double kcal100 = 100,
  double? serving,
  List<MealPortionEntity> portions = const [],
}) => MealEntity(
  portions: portions,
  code: name,
  name: name,
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: serving,
  servingUnit: null,
  servingSize: null,
  source: MealSourceEntity.off,
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

final _getIt = GetIt.instance;
late _FakeSearch _search;

Future<void> _register(Map<String, List<MealEntity>> results) async {
  await _getIt.reset();
  _search = _FakeSearch(results);
  final storage = AiCredentialStorage(_EmptyStorage());
  _getIt
    ..registerLazySingleton<AiCredentialStorage>(() => storage)
    ..registerFactory<BulkAddBloc>(
      () => BulkAddBloc(
        ResolveParsedMealsUseCase(_search),
        ReadMealTextUseCase(
          storage,
          (_) => throw StateError('must not be built without a key'),
        ),
        ReadMealPhotoUseCase(
          storage,
          (_) => throw StateError('must not be built without a key'),
        ),
      ),
    );
}

Widget _app() => ChangeNotifierProvider<EnergyUnitProvider>(
  create: (_) => EnergyUnitProvider(usesKilojoules: false),
  child: MaterialApp(
    // the app's theme, so a target's size is the one a phone shows
    theme: buildAppTheme(AppPalette.light),
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
                IntakeTypeEntity.breakfast,
                DateTime(2026, 8, 10),
                false,
              ),
            ),
            builder: (_) => const BulkAddScreen(),
          ),
  ),
);

final _findButton = find.bySemanticsIdentifier('bulk-add-parse');
final _submit = find.bySemanticsIdentifier('bulk-add-submit');
const _replaceTitle = 'Replace your edited foods?';

Future<void> _parse(
  WidgetTester tester,
  String text, {
  Size size = const Size(800, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app());
  tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/bulk');
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, text);
  await tester.pump();
  await tester.tap(_findButton);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

String _submitText(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(of: _submit, matching: find.byType(Text)))
    .map((t) => t.data)
    .join(' ');

void main() {
  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('review_controls')).path);
    await Hive.openBox<Map>(MealGroupStore.boxName, bytes: Uint8List(0));
    await Hive.openBox<dynamic>('photo_disclosure_seen', bytes: Uint8List(0));
    final flags = await Hive.openBox<bool>('fork_flags', bytes: Uint8List(0));
    await flags.put('keepMealPhotos', false);
  });

  setUp(() {
    final before = forkDayTotals;
    forkDayTotals = (_) async => (
      eaten: (kcal: 0.0, carbs: 0.0, fat: 0.0, protein: 0.0),
      goal: (kcal: 2000.0, carbs: 250.0, fat: 70.0, protein: 120.0),
    );
    addTearDown(() => forkDayTotals = before);
  });

  tearDown(() async => _getIt.reset());

  group('Find again', () {
    testWidgets('once rows exist Find foods steps back as Find again', (
      tester,
    ) async {
      await _register({
        'toast': [_food('Toast')],
      });
      await _parse(tester, '100g toast');

      expect(
        find.descendant(of: _findButton, matching: find.text('Find again')),
        findsOneWidget,
      );
      expect(find.text(l10nEn.bulkAddParseLabel), findsNothing);
    });

    testWidgets('untouched rows are found again without asking', (
      tester,
    ) async {
      await _register({
        'toast': [_food('Toast')],
      });
      await _parse(tester, '100g toast');
      final before = _search.searches;

      await _tap(tester, _findButton);

      expect(find.text(_replaceTitle), findsNothing);
      expect(_search.searches, greaterThan(before));
    });

    testWidgets('a row left out asks first, and Cancel keeps it', (
      tester,
    ) async {
      await _register({
        'toast': [_food('Toast')],
        'milk': [_food('Milk')],
      });
      await _parse(tester, '100g toast, 200g milk');
      await _tap(tester, find.byKey(const ValueKey('bulk-add-leave-out-1')));
      final before = _search.searches;

      await _tap(tester, _findButton);
      expect(find.text(_replaceTitle), findsOneWidget);
      expect(find.text('Your changes to 1 food will be lost.'), findsOneWidget);
      await _tap(tester, find.text(l10nEn.dialogCancelLabel));

      expect(_search.searches, before);
      expect(find.byKey(const ValueKey('bulk-add-put-back-1')), findsOneWidget);

      await _tap(tester, _findButton);
      await _tap(tester, find.text('Replace'));
      expect(_search.searches, greaterThan(before));
      expect(find.byKey(const ValueKey('bulk-add-put-back-1')), findsNothing);
    });

    testWidgets('an edited amount and another match count as changes', (
      tester,
    ) async {
      await _register({
        'toast': [_food('Toast'), _food('Toast, wholemeal', kcal100: 250)],
        'milk': [_food('Milk')],
      });
      await _parse(tester, '100g toast, 200g milk');
      await _tap(tester, find.byKey(const ValueKey('bulk-add-more-1')));
      await _tap(tester, find.text('Toast'));
      await _tap(tester, find.byKey(const ValueKey('bulk-add-other-match')));
      await _tap(tester, find.text('Toast, wholemeal').last);

      await _tap(tester, _findButton);
      expect(
        find.text('Your changes to 2 foods will be lost.'),
        findsOneWidget,
      );
    });
  });

  group('closing a sheet or dialog leaves the keyboard down', () {
    // the note field's own EditableText: focused means the keyboard is up
    bool noteFocused(WidgetTester tester) => tester
        .widget<EditableText>(
          find.descendant(
            of: find.bySemanticsIdentifier('bulk-add-input'),
            matching: find.byType(EditableText),
          ),
        )
        .focusNode
        .hasFocus;

    testWidgets('the amount sheet\'s Done', (tester) async {
      await _register({
        'toast': [_food('Toast')],
      });
      await _parse(tester, '100g toast');
      expect(noteFocused(tester), isFalse);

      await _tap(tester, find.text('Toast'));
      await _tap(tester, find.byKey(const ValueKey('bulk-add-amount-done')));

      expect(noteFocused(tester), isFalse);
    });

    testWidgets('the amount sheet opened from a focused note', (tester) async {
      await _register({
        'toast': [_food('Toast')],
      });
      await _parse(tester, '100g toast');
      await _tap(tester, find.bySemanticsIdentifier('bulk-add-input'));
      expect(noteFocused(tester), isTrue);

      await _tap(tester, find.text('Toast'));
      await _tap(tester, find.byKey(const ValueKey('bulk-add-amount-done')));

      expect(noteFocused(tester), isFalse);
    });

    testWidgets('Other match', (tester) async {
      await _register({
        'toast': [_food('Toast'), _food('French toast')],
      });
      await _parse(tester, '100g toast');

      await _tap(tester, find.text('Toast'));
      await _tap(tester, find.byKey(const ValueKey('bulk-add-other-match')));
      await _tap(tester, find.text('French toast').last);

      expect(noteFocused(tester), isFalse);
    });

    testWidgets('Find again\'s Cancel', (tester) async {
      await _register({
        'toast': [_food('Toast')],
      });
      await _parse(tester, '100g toast');
      await _tap(tester, find.byKey(const ValueKey('bulk-add-leave-out-0')));

      await _tap(tester, _findButton);
      await _tap(tester, find.text(l10nEn.dialogCancelLabel));

      expect(noteFocused(tester), isFalse);
    });

    testWidgets('Back\'s discard Cancel', (tester) async {
      await _register({
        'toast': [_food('Toast')],
      });
      await _parse(tester, '100g toast');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await _tap(tester, find.text(l10nEn.dialogCancelLabel));

      expect(noteFocused(tester), isFalse);
    });
  });

  testWidgets('Find again is outlined, so Log stays the one filled button', (
    tester,
  ) async {
    await _register({
      'toast': [_food('Toast')],
    });
    await _parse(tester, '100g toast');

    expect(
      find.descendant(of: _findButton, matching: find.byType(OutlinedButton)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _findButton, matching: find.byType(FilledButton)),
      findsNothing,
    );
  });

  testWidgets('Other match shows each candidate\'s energy per 100 g', (
    tester,
  ) async {
    await _register({
      'toast': [_food('Toast', kcal100: 265), _food('French toast')],
    });
    await _parse(tester, '100g toast');
    await _tap(tester, find.text('Toast'));
    await _tap(tester, find.byKey(const ValueKey('bulk-add-other-match')));

    final list = find.bySemanticsIdentifier('bulk-add-candidate-list');
    expect(
      find.descendant(of: list, matching: find.text('265 kcal per 100 g')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: list, matching: find.text('100 kcal per 100 g')),
      findsOneWidget,
    );
  });

  testWidgets('each row has a 48 dp Leave out that leaves it out, with Undo', (
    tester,
  ) async {
    await _register({
      'toast': [_food('Toast')],
    });
    await _parse(tester, '100g toast');
    final button = find.byKey(const ValueKey('bulk-add-leave-out-0'));

    expect(find.byTooltip('Leave out'), findsOneWidget);
    final size = tester.getSize(button);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));

    await _tap(tester, button);
    expect(find.byKey(const ValueKey('bulk-add-put-back-0')), findsOneWidget);
    expect(find.text('Left out: Toast'), findsOneWidget);
    expect(button, findsNothing, reason: 'a left-out row offers Put back');
  });

  group('the disabled Log says why', () {
    testWidgets('one row held for a unit check', (tester) async {
      await _register({
        'eggs': [_food('Egg')],
      });
      await _parse(tester, '2 eggs');

      expect(_submitText(tester), 'Check 1 row to log');
    });

    testWidgets('two rows held', (tester) async {
      await _register({
        'eggs': [_food('Egg')],
        'apples': [_food('Apple')],
      });
      await _parse(tester, '2 eggs, 2 apples');

      expect(_submitText(tester), 'Check 2 rows to log');
    });

    testWidgets('with a ready row, the count of ready rows stays', (
      tester,
    ) async {
      await _register({
        'toast': [_food('Toast')],
        'eggs': [_food('Egg')],
      });
      await _parse(tester, '100g toast, 2 eggs');

      expect(_submitText(tester), startsWith('Log 1 item'));
    });

    testWidgets('all left out stays Log 0 items', (tester) async {
      await _register({
        'toast': [_food('Toast')],
      });
      await _parse(tester, '100g toast');
      await _tap(tester, find.byKey(const ValueKey('bulk-add-leave-out-0')));

      expect(_submitText(tester), 'Log 0 items');
    });
  });

  group('Check the unit (crit r3 P2)', () {
    testWidgets('Keep clears the check and changes nothing', (tester) async {
      await _register({
        'eggs': [_food('Egg', kcal100: 150)],
      });
      await _parse(tester, '2 eggs');
      expect(find.text(l10nEn.bulkAddCheckAmountLabel), findsOneWidget);
      expect(_submitText(tester), 'Check 1 row to log');
      final amount = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('bulk-add-unit-0')),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data)
          .join();

      await _tap(tester, find.text('Egg'));
      final keep = find.byKey(const ValueKey('bulk-add-keep-unit'));
      expect(
        find.descendant(of: keep, matching: find.text('Keep 2 g')),
        findsOneWidget,
      );
      await _tap(tester, keep);

      expect(find.byKey(const ValueKey('bulk-add-amount-done')), findsNothing);
      expect(find.text(l10nEn.bulkAddCheckAmountLabel), findsNothing);
      expect(_submitText(tester), startsWith('Log 1 item'));
      expect(
        tester
            .widgetList<Text>(
              find.descendant(
                of: find.byKey(const ValueKey('bulk-add-unit-0')),
                matching: find.byType(Text),
              ),
            )
            .map((t) => t.data)
            .join(),
        amount,
      );
    });

    testWidgets('a row with no check offers no Keep', (tester) async {
      await _register({
        'toast': [_food('Toast')],
      });
      await _parse(tester, '100g toast');

      await _tap(tester, find.text('Toast'));
      expect(find.byKey(const ValueKey('bulk-add-keep-unit')), findsNothing);
    });

    testWidgets('a flagged food\'s own portions are chips', (tester) async {
      final egg = _food(
        'Egg',
        portions: const [
          MealPortionEntity(label: '1 large', gramWeight: 50, localized: true),
        ],
      );
      await _register({
        'eggs': [egg],
      });
      await _parse(tester, '2 eggs');
      expect(find.text(l10nEn.bulkAddCheckAmountLabel), findsOneWidget);

      await _tap(tester, find.text('Egg'));
      expect(find.textContaining('large'), findsWidgets);
    });
  });

  // an overflow fails the test as an uncaught layout error
  testWidgets('at 200% on a narrow phone the new labels show in full', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _register({
      'eggs': [_food('Egg'), _food('Egg, boiled', kcal100: 155)],
      'apples': [_food('Apple')],
    });
    await _parse(tester, '2 eggs, 2 apples', size: const Size(360, 2400));

    expect(_submitText(tester), 'Check 2 rows to log');
    // only the new labels: the test font cuts some older lines here
    expect(cutText(tester), isNot(contains('Check 2 rows to log')));
    // not expectAccessible: the dictation chip's 40 dp predates this (P3)
    final semantics = tester.ensureSemantics();
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    semantics.dispose();

    await _tap(tester, find.text('Egg'));
    await _tap(tester, find.byKey(const ValueKey('bulk-add-other-match')));
    expect(find.text('155 kcal per 100 g'), findsOneWidget);
    expect(cutText(tester), isNot(contains('155 kcal per 100 g')));
  });
}
