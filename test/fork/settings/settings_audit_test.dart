// The Settings audit's findings, each pinned where it was seen.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/probe_ai_endpoint_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/run_ai_endpoint_probe_usecase.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/fork/backup/auto_backup_ui.dart';
import 'package:opennutritracker/fork/display/contrast.dart';
import 'package:opennutritracker/fork/history/history_file.dart';
import 'package:opennutritracker/fork/history/history_import.dart';
import 'package:opennutritracker/fork/history/table_reader.dart';
import 'package:opennutritracker/fork/layout/width_cap.dart';
import 'package:opennutritracker/fork/screens/settings/settings_screen.dart';
import 'package:opennutritracker/fork/settings/accent_view.dart';
import 'package:opennutritracker/fork/settings/food_databases_view.dart';
import 'package:opennutritracker/fork/settings/settings_index.dart';
import 'package:opennutritracker/fork/update/update_notice.dart';
import 'package:opennutritracker/fork/update/updater.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../helpers/test_l10n.dart';

class _FakeSettingsBloc extends Fake implements SettingsBloc {
  _FakeSettingsBloc(this.state);

  @override
  final SettingsState state;

  @override
  Stream<SettingsState> get stream => const Stream<SettingsState>.empty();

  @override
  void add(SettingsEvent event) {}
}

class _FakeProfileBloc extends Fake implements ProfileBloc {}

class _FakeHomeBloc extends Fake implements HomeBloc {
  @override
  void add(HomeEvent event) {}
}

class _FakeDiaryBloc extends Fake implements DiaryBloc {
  @override
  void add(DiaryEvent event) {}
}

class _FakeCalendarDayBloc extends Fake implements CalendarDayBloc {
  @override
  void add(CalendarDayEvent event) {}
}

class _FakeTrendsBloc extends Fake implements TrendsBloc {
  @override
  void add(TrendsEvent event) {}
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

class _FakeProber extends Fake implements AiEndpointProber {}

/// A check that never answers: the row stays at "Checking…".
class _Checking extends Updater {
  @override
  Future<UpdateInfo> check() => Completer<UpdateInfo>().future;
}

void _register([SettingsLoadedState? state]) {
  final getIt = GetIt.instance;
  getIt.registerSingleton<SettingsBloc>(
    _FakeSettingsBloc(
      state ??
          const SettingsLoadedState(
            '1.0.0',
            false,
            AppThemeEntity.system,
            false,
          ),
    ),
  );
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

Widget _app({
  SettingsSection? section,
  double textScale = 1,
  ThemeData? theme,
  bool use24Hour = false,
}) => MaterialApp(
  theme: theme,
  localizationsDelegates: const [
    S.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: S.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(textScale),
      alwaysUse24HourFormat: use24Hour,
    ),
    child: child!,
  ),
  home: SettingsScreen(section: section),
);

Future<void> _phone(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  tearDown(() => locator.reset());

  testWidgets('the privacy dialog fits at 2x on a 360x640 phone', (
    tester,
  ) async {
    _register();
    // The keep-photos switch reads its flag: opened here, in memory, since
    // a first open never finishes in a widget test's fake time
    await tester.runAsync(() async {
      Hive.init((await Directory.systemTemp.createTemp('settings')).path);
      final flags = await Hive.openBox<bool>('fork_flags', bytes: Uint8List(0));
      await flags.put('keepMealPhotos', false);
    });
    addTearDown(() => tester.runAsync(Hive.close));
    await _phone(tester, const Size(360, 640));
    await tester.pumpWidget(_app(section: SettingsSection.about, textScale: 2));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10nEn.settingsPrivacySettings));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AlertDialog), findsOneWidget);
    // The last control can be scrolled to.
    await tester.scrollUntilVisible(
      find.text('Keep meal photos for 24 hours'),
      100,
      scrollable: find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Keep meal photos for 24 hours').hitTestable(), findsOne);
  });

  testWidgets('the muted section chips reach 3:1 in the dark theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppPalette.dark),
        home: Scaffold(
          body: SettingsIndex(summaries: const {}, onOpen: (_) {}),
        ),
      ),
    );
    for (final section in SettingsSection.values) {
      final icon = tester.widget<Icon>(find.byIcon(section.icon));
      final fill = section.colorIn(tester.element(find.byIcon(section.icon)));
      expect(
        contrastRatio(icon.color!, fill),
        greaterThanOrEqualTo(3),
        reason: section.name,
      );
    }
  });

  testWidgets('with nothing cached, Clear cached items looks disabled', (
    tester,
  ) async {
    _register();
    await tester.pumpWidget(_app(section: SettingsSection.food));
    await tester.pumpAndSettle();
    final row = find.widgetWithText(ListTile, l10nEn.clearOffCacheLabel);
    expect(tester.widget<ListTile>(row).enabled, isFalse);
    final disabled = Theme.of(tester.element(row)).disabledColor;
    Color? colourOf(Finder text) =>
        tester.renderObject<RenderParagraph>(text).text.style?.color;
    expect(
      colourOf(
        find.descendant(
          of: row,
          matching: find.text(l10nEn.clearOffCacheLabel),
        ),
      ),
      disabled,
    );
    expect(
      colourOf(find.descendant(of: row, matching: find.textContaining('0 B'))),
      disabled,
    );
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: row,
              matching: find.byIcon(Icons.cached_rounded),
            ),
          )
          .color,
      disabled,
    );
  });

  testWidgets('the daily reminder time follows the 12/24-hour setting', (
    tester,
  ) async {
    const state = SettingsLoadedState(
      '1.0.0',
      false,
      AppThemeEntity.system,
      false,
      notificationsEnabled: true,
      notificationHour: 20,
      notificationMinute: 5,
    );
    _register(state);
    await tester.pumpWidget(_app(section: SettingsSection.reminders));
    await tester.pumpAndSettle();
    expect(find.textContaining('8:05 PM'), findsWidgets);
    expect(find.textContaining('20:05'), findsNothing);

    // The index's summary says it the same way.
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.textContaining('8:05 PM'), findsOneWidget);

    await tester.pumpWidget(
      _app(section: SettingsSection.reminders, use24Hour: true),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('20:05'), findsWidgets);
  });

  testWidgets('each accent swatch is at least 48 dp wide on a 360 dp phone', (
    tester,
  ) async {
    await _phone(tester, const Size(360, 800));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccentColourView(
            offersWallpaper: false,
            matchesWallpaper: false,
            currentArgb: null,
            onWallpaper: (_) {},
            onColor: (_) {},
            onCustom: () {},
          ),
        ),
      ),
    );
    for (var i = 0; i < accentPresetNames.length; i++) {
      final cell = tester.getSize(
        find.bySemanticsIdentifier(
          'accent-preset-${i.toString().padLeft(2, '0')}',
        ),
      );
      expect(cell.width, greaterThanOrEqualTo(48), reason: '$i');
      expect(cell.height, greaterThanOrEqualTo(48), reason: '$i');
    }
  });

  testWidgets('with no accent picked, the row shows the theme accent', (
    tester,
  ) async {
    _register(
      const SettingsLoadedState(
        '1.0.0',
        false,
        AppThemeEntity.system,
        false,
        useMaterialYou: false,
      ),
    );
    final theme = buildAppTheme(AppPalette.light);
    await tester.pumpWidget(
      _app(section: SettingsSection.appearance, theme: theme),
    );
    await tester.pumpAndSettle();
    final row = find.widgetWithText(ListTile, l10nEn.settingsAccentColourTitle);
    final disc = tester.widget<ListTile>(row).trailing!;
    final colour =
        ((tester
                    .widget<Container>(
                      find
                          .descendant(
                            of: find.byWidget(disc),
                            matching: find.byType(Container),
                          )
                          .first,
                    )
                    .decoration)!
                as BoxDecoration)
            .color;
    expect(colour, theme.colorScheme.primary);
  });

  testWidgets('About OpenBite has the info icon, not the error one', (
    tester,
  ) async {
    _register();
    await tester.pumpWidget(_app(section: SettingsSection.about));
    await tester.pumpAndSettle();
    final row = find.widgetWithText(ListTile, 'About OpenBite');
    expect(
      find.descendant(
        of: row,
        matching: find.byIcon(Icons.info_outline_rounded),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
  });

  testWidgets('a search result lands on its row, not the top of the page', (
    tester,
  ) async {
    _register();
    await _phone(tester, const Size(360, 640));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('settings-search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'fasting');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show fasting'));
    await tester.pumpAndSettle();
    final row = find.text('Show fasting');
    expect(row, findsOneWidget);
    expect(row.hitTestable(), findsOneWidget);
  });

  for (final label in [
    'Goal planner',
    'Health Connect',
    'Export diary as CSV',
    'Show water',
  ]) {
    testWidgets('the search lands on $label', (tester) async {
      _register();
      await _phone(tester, const Size(360, 640));
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('settings-search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), label);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
      expect(find.text(label).hitTestable(), findsWidgets);
    });
  }

  testWidgets('the Updates row does nothing and says so while checking', (
    tester,
  ) async {
    VoidCallback? tap = () {};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateStatus(
            version: '0.1.0',
            updater: _Checking(),
            builder: (subtitle, onTap) {
              tap = onTap;
              return ListTile(title: Text(subtitle), onTap: onTap);
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Checking for updates'), findsOneWidget);
    expect(tap, isNull);
  });

  testWidgets('the Updates row is greyed while checking', (tester) async {
    _register();
    await tester.pumpWidget(_app(section: SettingsSection.about));
    await tester.pump();
    final row = find.widgetWithText(ListTile, 'Updates');
    expect(find.textContaining('Checking for updates'), findsOneWidget);
    expect(tester.widget<ListTile>(row).enabled, isFalse);
  });

  testWidgets('the lists keep a phone width on a tablet', (tester) async {
    _register();
    await _phone(tester, const Size(1200, 900));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(
      tester
          .getSize(find.bySemanticsIdentifier('settings-section-goals'))
          .width,
      lessThanOrEqualTo(WidthCap.maxWidth),
    );
    for (final section in SettingsSection.values) {
      await tester.pumpWidget(_app(section: section));
      await tester.pumpAndSettle();
      for (final tile in tester.widgetList(find.byType(ListTile)).take(1)) {
        expect(
          tester.getSize(find.byWidget(tile)).width,
          lessThanOrEqualTo(WidthCap.maxWidth),
          reason: section.name,
        );
      }
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccentColourView(
            offersWallpaper: false,
            matchesWallpaper: false,
            currentArgb: null,
            onWallpaper: (_) {},
            onColor: (_) {},
            onCustom: () {},
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(AppCard).first).width,
      lessThanOrEqualTo(WidthCap.maxWidth),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FoodDatabasesView(
            toggles: const {},
            onToggle: (_, _) {},
            onOpenSite: (_) {},
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(AppCard).first).width,
      lessThanOrEqualTo(WidthCap.maxWidth),
    );
    await tester.pumpWidget(const MaterialApp(home: AutoBackupScreen()));
    await tester.pump();
    expect(
      tester.getSize(find.textContaining('When you leave the app')).width,
      lessThanOrEqualTo(WidthCap.maxWidth),
    );
  });

  testWidgets('history files are read with "Reading files…" on screen', (
    tester,
  ) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('history-read'),
    );
    final file = File('${dir!.path}/weights.csv');
    final body = File('${dir.path}/body.csv');
    // Foods with a time, a weigh-in and a measurement all cross back
    await tester.runAsync(() async {
      await file.writeAsString(
        'Date,Time,Food Name,Calories (kcal),Weight (kg)\n'
        '2026-10-20,08:00,Egg,80,80\n',
      );
      await body.writeAsString('Date,Waist (cm)\n2026-10-20,93\n');
    });
    Future<({List<SheetTable> tables, HistoryFile first})?>? reading;
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('import'))),
    );
    final context = tester.element(find.text('import'));
    // Started outside the fake clock, so the isolate's answer arrives
    await tester.runAsync(() async {
      reading = HistoryImportTile.readFiles(context, [
        (name: 'weights.csv', path: file.path),
        (name: 'body.csv', path: body.path),
      ], BodyWeightUnit.kg);
    });
    await tester.pump();
    expect(find.text('Reading files…'), findsOneWidget);

    final read = await tester.runAsync(() => reading!);
    await tester.pumpAndSettle();
    expect(find.text('Reading files…'), findsNothing);
    expect(read!.tables, hasLength(2));
    expect(read.first.foods.single.name, 'Egg');
    expect(read.first.weightsKg, isNotEmpty);
    expect(read.first.measurements, isNotEmpty);
  });
}
