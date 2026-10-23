import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/locale_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/theme_mode_provider.dart';
import 'package:opennutritracker/core/utils/widget/calorie_widget_writer.dart';
import 'package:opennutritracker/fork/backup/apply_restored_settings.dart';
import 'package:provider/provider.dart';

void main() {
  late _Config config;

  setUp(() {
    config = _Config();
    locator.registerSingleton<ConfigRepository>(config);
  });
  tearDown(() => locator.unregister<ConfigRepository>());

  Future<(ThemeModeProvider, EnergyUnitProvider, LocaleProvider)> run(
    WidgetTester tester,
  ) async {
    final theme = ThemeModeProvider(appTheme: AppThemeEntity.light);
    final energy = EnergyUnitProvider();
    final locale = LocaleProvider(
      locale: const Locale('de'),
      calorieWidgetStore: _NoWidget(),
    );
    late BuildContext context;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: energy),
          ChangeNotifierProvider.value(value: locale),
        ],
        child: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.runAsync(() => applyRestoredSettings(context));
    return (theme, energy, locale);
  }

  testWidgets('a restored theme, accent and kilojoules show at once', (
    tester,
  ) async {
    final (theme, energy, locale) = await run(tester);

    expect(theme.appTheme, AppThemeEntity.dark);
    expect(theme.useMaterialYou, isFalse);
    expect(theme.accentColor, 0xFF336699);
    expect(energy.usesKilojoules, isTrue);
    expect(locale.locale, const Locale('de'));
  });

  testWidgets('a restored language replaces the one shown', (tester) async {
    config.locale = 'fr';

    final (_, _, locale) = await run(tester);

    expect(locale.locale, const Locale('fr'));
    expect(config.locale, 'fr');
  });
}

class _Config extends Fake implements ConfigRepository {
  String? locale = 'de';

  @override
  Future<ConfigEntity> getConfig() async => const ConfigEntity(
    true,
    true,
    false,
    AppThemeEntity.dark,
    usesKilojoules: true,
    useMaterialYou: false,
    accentColor: 0xFF336699,
  );

  @override
  Future<String?> getSelectedLocale() async => locale;

  @override
  Future<void> setSelectedLocale(String? code) async => locale = code;

  @override
  Future<void> setLocaleSyncSeeded() async {}

  @override
  Future<void> clearLocaleSyncSeeded() async {}
}

class _NoWidget extends Fake implements CalorieWidgetStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}
