import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/probe_ai_endpoint_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/run_ai_endpoint_probe_usecase.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:opennutritracker/features/settings/settings_screen.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/fork/settings/settings_index.dart';

import '../../helpers/test_l10n.dart';
import '../a11y/nested_buttons.dart';

// Seam S129: Settings as MacroFactor's, a page for each section, and every
// row of the old list on one of them.

/// A loaded settings screen without the config box behind it.
///
/// The screen only ever reads the state and posts `LoadSettingsEvent`, so a
/// bloc that answers with one fixed loaded state renders exactly what the
/// real one renders — and skips Hive, `package_info`, and the cache size
/// read, none of which are what these tests are about.
class _FakeSettingsBloc extends Fake implements SettingsBloc {
  @override
  SettingsState get state =>
      const SettingsLoadedState('1.0.0', false, AppThemeEntity.system, false);

  @override
  Stream<SettingsState> get stream => const Stream<SettingsState>.empty();

  @override
  void add(SettingsEvent event) {}

  /// Held open by the tests, so a reload sent before the flag is stored
  /// shows up. Made on the call, inside the test's fake-async zone; one
  /// made in setUp would complete outside it.
  Completer<void>? mealMacrosSaved;

  @override
  Future<void> setShowMealMacros(bool showMealMacros) =>
      (mealMacrosSaved = Completer<void>()).future;
}

/// The screen resolves these in `initState` and only calls them from
/// controls no test here touches.
class _FakeProfileBloc extends Fake implements ProfileBloc {}

class _FakeHomeBloc extends Fake implements HomeBloc {
  @override
  void add(HomeEvent event) {}
}

class _FakeDiaryBloc extends Fake implements DiaryBloc {
  final List<DiaryEvent> added = [];

  @override
  void add(DiaryEvent event) => added.add(event);
}

class _FakeCalendarDayBloc extends Fake implements CalendarDayBloc {
  @override
  void add(CalendarDayEvent event) {}
}

class _FakeTrendsBloc extends Fake implements TrendsBloc {
  @override
  void add(TrendsEvent event) {}
}

/// Nothing is configured, which is the state a user arrives in from a
/// rejected key or a refused destination.
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

/// The runner is real; only the thing that would talk to a server is not.
/// Nothing here presses the check, so it is never asked anything.
class _FakeProber extends Fake implements AiEndpointProber {}

void _register() {
  final getIt = GetIt.instance;
  getIt.registerSingleton<SettingsBloc>(_FakeSettingsBloc());
  getIt.registerSingleton<ProfileBloc>(_FakeProfileBloc());
  getIt.registerSingleton<HomeBloc>(_FakeHomeBloc());
  getIt.registerSingleton<DiaryBloc>(_FakeDiaryBloc());
  getIt.registerSingleton<CalendarDayBloc>(_FakeCalendarDayBloc());
  getIt.registerSingleton<TrendsBloc>(_FakeTrendsBloc());
  final credentials = AiCredentialStorage(_EmptyStorage());
  getIt.registerSingleton<AiCredentialStorage>(credentials);
  getIt.registerSingleton<AiEndpointProbeRunner>(
    AiEndpointProbeRunner(credentials, _FakeProber()),
  );
}

Widget _app({SettingsSection? section}) => MaterialApp(
  localizationsDelegates: const [
    S.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: S.supportedLocales,
  home: SettingsScreen(section: section),
);

/// What each page must hold, by the row's text.
Map<SettingsSection, List<String>> _rows() => {
  SettingsSection.goals: [
    l10nEn.settingsKcalGoalInfoLabel,
    l10nEn.settingsKcalAdjustmentLabel,
    'Trend and calorie target',
    l10nEn.settingsMacroSplitLabel,
    l10nEn.settingsPerMealKcalShareLabel,
    l10nEn.settingsNutrientGoalsLabel,
    l10nEn.settingsDayStartLabel,
  ],
  SettingsSection.units: [
    l10nEn.settingsFoodUnitsLabel,
    l10nEn.settingsHeightUnitsLabel,
    l10nEn.settingsBodyWeightUnitLabel,
    l10nEn.settingsEnergyUnitLabel,
    l10nEn.settingsDefaultToRawFoodUnitsLabel,
  ],
  SettingsSection.reminders: [
    l10nEn.settingsNotificationsLabel,
    'Weigh-in and check-in reminders',
  ],
  SettingsSection.food: [
    'Search sources',
    l10nEn.settingsAiAssistLabel,
    'Open Food Facts account',
  ],
  SettingsSection.data: [
    'Automatic backup',
    'Bring data in',
    'Take data out',
    'Import history',
    l10nEn.importCustomFoodDataLabel,
    l10nEn.exportImportAppDataLabel,
    'Export diary as CSV',
    'Profiles',
    l10nEn.manageProfilesLabel,
    l10nEn.clearOffCacheLabel,
    l10nEn.settingsDeleteAllDataLabel,
  ],
  SettingsSection.appearance: [
    l10nEn.settingsThemeLabel,
    l10nEn.settingsAccentColourTitle,
    l10nEn.settingsLanguageLabel,
    l10nEn.settingsShowActivityTracking,
    l10nEn.settingsShowMealMacros,
    l10nEn.settingsShowMicronutrientsLabel,
    l10nEn.settingsNutrientsLabel,
    'Macro order',
    'Diary by the hour',
  ],
  SettingsSection.about: [
    l10nEn.settingsPrivacySettings,
    l10nEn.settingsDisclaimerLabel,
    l10nEn.settingsSourcesLabel,
    l10nEn.settingsReportErrorLabel,
    'Updates',
    'About OpenBite',
  ],
};

void main() {
  setUp(_register);
  tearDown(() => locator.reset());

  test('a path in a text names a section there is', () {
    final titles = {for (final s in SettingsSection.values) s.title};
    final paths = RegExp(r'Settings → ([^→.]+?)(?: →|\.)').allMatches(
      [
            File('lib/l10n/intl_en.arb').readAsStringSync(),
            File('lib/fork/update/update_notice.dart').readAsStringSync(),
            File('lib/fork/backup/auto_backup_ui.dart').readAsStringSync(),
          ]
          .expand((f) => f.split('\n'))
          // Comments name screens loosely; only what is shown counts.
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n'),
    );
    expect(paths, isNotEmpty);
    for (final m in paths) {
      expect(titles, contains(m.group(1)!.trim()), reason: m.group(0));
    }
  });

  test('a search needs every word, in the name or its section', () {
    const entries = <SettingsEntry>[
      (label: 'Energy unit', section: SettingsSection.units, also: 'kJ'),
      (label: 'Theme', section: SettingsSection.appearance, also: ''),
    ];
    expect(matchingSettings(entries, ''), isEmpty);
    expect(matchingSettings(entries, '  '), isEmpty);
    expect(matchingSettings(entries, 'ENERGY'), [entries.first]);
    expect(matchingSettings(entries, 'units energy'), [entries.first]);
    expect(matchingSettings(entries, 'energy theme'), isEmpty);
    expect(matchingSettings(entries, 'appear'), [entries.last]);
    expect(matchingSettings(entries, 'kj'), [entries.first]);
  });

  testWidgets('a row is its own button, not inside its card\'s first', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    for (final section in SettingsSection.values) {
      await tester.pumpWidget(_app(section: section));
      await tester.pumpAndSettle();
      expect(tapsInTaps(tester), isEmpty, reason: section.name);
    }
    handle.dispose();
  });

  testWidgets('Theme says which is set', (tester) async {
    await tester.pumpWidget(_app(section: SettingsSection.appearance));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, l10nEn.settingsThemeLabel),
        matching: find.text(l10nEn.settingsThemeSystemDefaultLabel),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the plain route lists the sections, each with a summary', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    for (final section in SettingsSection.values) {
      expect(
        find.bySemanticsIdentifier('settings-section-${section.name}'),
        findsOneWidget,
        reason: section.name,
      );
    }
    expect(find.text('kg · kcal · metric'), findsOneWidget);
    expect(find.textContaining('OpenBite 1.0.0'), findsOneWidget);
    // No row of a section is on the list itself.
    expect(find.text(l10nEn.settingsEnergyUnitLabel), findsNothing);
  });

  for (final MapEntry(key: section, value: rows) in _rows().entries) {
    testWidgets('${section.name}: its rows and no other', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_app(section: section));
      await tester.pumpAndSettle();
      expect(find.text(section.title), findsWidgets);
      for (final row in rows) {
        expect(find.text(row), findsWidgets, reason: row);
      }
      for (final other in _rows().entries.where((e) => e.key != section)) {
        for (final row in other.value) {
          expect(
            find.text(row),
            findsNothing,
            reason: '$row on ${section.name}',
          );
        }
      }
    });
  }

  testWidgets('data: the backup, then what comes in, goes out, starts over', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(section: SettingsSection.data));
    await tester.pumpAndSettle();
    double top(String text) => tester.getTopLeft(find.text(text).first).dy;
    final order = [
      'Automatic backup',
      'Bring data in',
      'Import history',
      'Take data out',
      'Export diary as CSV',
      'Start over',
      l10nEn.clearOffCacheLabel,
      l10nEn.settingsDeleteAllDataLabel,
    ];
    for (var i = 1; i < order.length; i++) {
      expect(top(order[i - 1]) < top(order[i]), isTrue, reason: order[i]);
    }
    // The page's own title is the only heading for the section.
    expect(find.text(l10nEn.settingsCategoryData), findsOneWidget);
  });

  testWidgets('a section opens its page', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('settings-section-units'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsIdentifier('settings-energy-unit'), findsOneWidget);
    expect(find.bySemanticsIdentifier('settings-search'), findsNothing);
  });

  testWidgets('the search finds a row and opens its section', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('settings-search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'nothing like it');
    await tester.pumpAndSettle();
    expect(find.text('No setting by that name'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'energy u');
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10nEn.settingsEnergyUnitLabel));
    await tester.pumpAndSettle();
    expect(find.bySemanticsIdentifier('settings-energy-unit'), findsOneWidget);
    // The search went: back is the list of sections.
    Navigator.of(tester.element(find.byType(SettingsScreen).last)).pop();
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier('settings-section-units'),
      findsOneWidget,
    );
  });

  testWidgets('what people come to change is in the first card', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    final first = find.byType(AppCard).first;
    for (final section in SettingsSection.values) {
      expect(
        find.descendant(
          of: first,
          matching: find.bySemanticsIdentifier(
            'settings-section-${section.name}',
          ),
        ),
        section.index < 4 ? findsOneWidget : findsNothing,
        reason: section.name,
      );
    }
  });

  testWidgets('embedded, every section is there, as before', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 6000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(child: SettingsScreen(embedded: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final row in _rows().values.expand((rows) => rows)) {
      expect(find.text(row), findsWidgets, reason: row);
    }
  });
}
