import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/off_const.dart';
import 'package:opennutritracker/features/add_meal/data/dto/sp/sp_const.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/food_sources_screen.dart';
import 'package:opennutritracker/fork/settings/food_databases_view.dart';
import 'package:opennutritracker/generated/l10n.dart';

class _GetConfig extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async => const ConfigEntity(
    true,
    true,
    false,
    AppThemeEntity.system,
    foodSourceToggles: {'bls': false},
  );
}

class _AddConfig extends Fake implements AddConfigUsecase {
  final saved = <Map<String, bool>>[];

  @override
  Future<void> setConfigFoodSourceToggles(Map<String, bool> toggles) async =>
      saved.add(Map.of(toggles));
}

bool _on(WidgetTester tester, String code) => tester
    .widget<SwitchListTile>(
      find.descendant(
        of: find.bySemanticsIdentifier('food-source-$code'),
        matching: find.byType(SwitchListTile),
      ),
    )
    .value;

void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1080, 2400);
    addTearDown(view.reset);
  });

  test('every database Settings offers has a tag, a name and its foods', () {
    expect(
      foodDatabases.keys.toSet(),
      SPConst.settingsSelectableFoodSources.toSet(),
    );
  });

  testWidgets('Open Food Facts is always on, the others have a switch', (
    tester,
  ) async {
    final opened = <String>[];
    final toggled = <(String, bool)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FoodDatabasesView(
            toggles: const {'fdc_branded': false},
            onToggle: (code, on) => toggled.add((code, on)),
            onOpenSite: opened.add,
          ),
        ),
      ),
    );
    expect(find.text('always'), findsOneWidget);
    expect(
      find.descendant(
        of: find.bySemanticsIdentifier('food-source-off'),
        matching: find.byType(Switch),
      ),
      findsNothing,
    );
    for (final code in SPConst.settingsSelectableFoodSources) {
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('food-source-$code'),
          matching: find.text(foodDatabases[code]!.tag),
        ),
        findsOneWidget,
      );
      // A database missing from the toggles is on.
      expect(_on(tester, code), code != 'fdc_branded', reason: code);
    }

    await tester.tap(find.text('USDA Branded'));
    expect(toggled, [('fdc_branded', true)]);

    await tester.tap(find.widgetWithText(TextButton, OFFConst.offSourceName));
    expect(opened, [OFFConst.offWebsiteUrl]);
  });

  testWidgets('the screen reads the switches and saves a change', (
    tester,
  ) async {
    final add = _AddConfig();
    locator
      ..registerSingleton<GetConfigUsecase>(_GetConfig())
      ..registerSingleton<AddConfigUsecase>(add);
    addTearDown(locator.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.supportedLocales,
        home: const FoodSourcesScreen(),
      ),
    );
    await tester.pumpAndSettle();
    expect(_on(tester, 'bls'), isFalse);
    expect(_on(tester, 'fdc_foundation'), isTrue);

    await tester.tap(find.text('Bundeslebensmittelschlüssel'));
    await tester.pumpAndSettle();
    expect(_on(tester, 'bls'), isTrue);
    expect(add.saved, [
      {'bls': true},
    ]);
  });
}
