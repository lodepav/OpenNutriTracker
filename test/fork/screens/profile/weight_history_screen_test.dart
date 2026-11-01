// Fork-owned copy of test/features/profile/presentation/weight_history_screen_test.dart (D23); upstream's later changes to it
// are ported by hand: fork/tools/upstream-copies.sh.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/data/repository/user_repository.dart';
import 'package:opennutritracker/core/data/repository/weight_log_repository.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_weight_log_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_weight_log_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_weight_log_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/screens/profile/weight_history_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
import '../../../helpers/fake_reload_blocs.dart';
import '../../helpers/recording_profile_bloc.dart';
import '../../../helpers/test_l10n.dart';

class _FakeGetWeightLogUsecase extends Fake implements GetWeightLogUsecase {
  final List<WeightLogEntity> _entries;

  _FakeGetWeightLogUsecase(this._entries);

  @override
  Future<List<WeightLogEntity>> getAllEntries() async => List.of(_entries);

  @override
  Future<List<WeightLogEntity>> getEntriesInRange(
    DateTime from,
    DateTime to,
  ) async {
    return _entries
        .where((e) => !e.date.isBefore(from) && !e.date.isAfter(to))
        .toList();
  }
}

class _FakeAddWeightLogUsecase extends Fake implements AddWeightLogUsecase {
  final added = <WeightLogEntity>[];

  @override
  Future<void> addEntry(WeightLogEntity entry) async => added.add(entry);
}

class _FakeDeleteWeightLogUsecase extends Fake
    implements DeleteWeightLogUsecase {
  final deleted = <WeightLogEntity>[];

  @override
  Future<void> deleteEntry(WeightLogEntity entry) async => deleted.add(entry);
}

class _FakeConfigRepository extends Fake implements ConfigRepository {
  @override
  Future<ConfigEntity> getConfig() async {
    return ConfigEntity(false, false, false, AppThemeEntity.system);
  }
}

class _FakeGetUserUsecase extends Fake implements GetUserUsecase {
  _FakeGetUserUsecase(this.weightKg);

  final double weightKg;

  @override
  Future<UserEntity> getUserData() async => UserEntity(
    birthday: DateTime(1990, 6, 15),
    heightCM: 165,
    weightKG: weightKg,
    gender: UserGenderEntity.female,
    goal: UserWeightGoalEntity.maintainWeight,
    pal: UserPALEntity.sedentary,
  );
}

DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// The log as stored: one row a day, by the day it is filed under.
class _MemoryLog extends Fake implements WeightLogRepository {
  final rows = <DateTime, WeightLogEntity>{};

  void file(DateTime day, double kg, {DateTime? shownAs, String? note}) =>
      rows[day] = WeightLogEntity(
        date: shownAs ?? day,
        weightKg: kg,
        note: note,
        filedDay: day,
      );

  @override
  Future<void> addEntry(WeightLogEntity entry) async => file(
    _dayOf(entry.date),
    entry.weightKg,
    shownAs: entry.date,
    note: entry.note,
  );

  @override
  Future<void> deleteEntry(DateTime date) async => rows.remove(_dayOf(date));

  @override
  Future<List<WeightLogEntity>> getAllEntries() async => rows.values.toList();
}

class _MemoryUsers extends Fake implements UserRepository {
  _MemoryUsers(double weightKg)
    : user = UserEntity(
        birthday: DateTime(1990, 6, 15),
        heightCM: 165,
        weightKG: weightKg,
        gender: UserGenderEntity.female,
        goal: UserWeightGoalEntity.maintainWeight,
        pal: UserPALEntity.sedentary,
      );

  UserEntity user;

  @override
  Future<UserEntity> getUserData() async => user;

  @override
  Future<void> updateUserData(UserEntity userEntity) async => user = userEntity;
}

class _LiveGetWeightLogUsecase extends Fake implements GetWeightLogUsecase {
  _LiveGetWeightLogUsecase(this.log);

  final _MemoryLog log;

  @override
  Future<List<WeightLogEntity>> getAllEntries() => log.getAllEntries();
}

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: S.supportedLocales,
    home: child,
  );
}

Widget _buildScreen(
  List<WeightLogEntity> entries, {
  _FakeDeleteWeightLogUsecase? deleteUsecase,
  _FakeAddWeightLogUsecase? addUsecase,
}) {
  return WeightHistoryScreen(
    getUsecase: _FakeGetWeightLogUsecase(entries),
    addUsecase: addUsecase ?? _FakeAddWeightLogUsecase(),
    deleteUsecase: deleteUsecase ?? _FakeDeleteWeightLogUsecase(),
    configRepository: _FakeConfigRepository(),
  );
}

// a weigh-in is swiped left to delete it.
Future<void> _swipe(WidgetTester tester, Finder row) async {
  await tester.ensureVisible(row);
  await tester.drag(row, const Offset(-600, 0));
}

void main() {
  group('WeightHistoryScreen chart', () {
    testWidgets('shows the empty-state copy when there are no entries', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(_buildScreen(const [])));
      await tester.pumpAndSettle();

      // 0 entries: the global "no readings yet" message is shown, no chart.
      expect(find.text(l10nEn.weightHistoryNoEntries), findsOneWidget);
      expect(find.byType(LineChart), findsNothing);
    });

    testWidgets('shows the chart empty-state when there is only one entry', (
      tester,
    ) async {
      final today = DateTime.now();
      final entries = [
        WeightLogEntity(
          date: DateTime(today.year, today.month, today.day),
          weightKg: 72.0,
        ),
      ];

      await tester.pumpWidget(_wrap(_buildScreen(entries)));
      await tester.pumpAndSettle();

      // 1 entry: the list shows the row, the chart slot shows the nudge.
      expect(
        find.byKey(const Key('weightHistoryChartEmptyState')),
        findsOneWidget,
      );
      expect(find.text(l10nEn.weightHistoryChartEmptyState), findsOneWidget);
      expect(find.byType(LineChart), findsNothing);
    });

    testWidgets('renders the chart when there are three entries', (
      tester,
    ) async {
      final today = DateTime.now();
      DateTime day(int daysAgo) {
        final d = today.subtract(Duration(days: daysAgo));
        return DateTime(d.year, d.month, d.day);
      }

      final entries = [
        WeightLogEntity(date: day(0), weightKg: 71.0),
        WeightLogEntity(date: day(7), weightKg: 71.5),
        WeightLogEntity(date: day(14), weightKg: 72.0),
      ];

      await tester.pumpWidget(_wrap(_buildScreen(entries)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('weightHistoryChart')), findsOneWidget);
      expect(find.byType(LineChart), findsOneWidget);
      expect(
        find.byKey(const Key('weightHistoryChartEmptyState')),
        findsNothing,
      );
    });

    testWidgets('default 30d hides an older point (showing empty state), '
        'selecting 60d shows chart, and selecting All shows chart '
        'with very old history', (tester) async {
      final today = DateTime.now();
      DateTime day(int daysAgo) {
        final d = today.subtract(Duration(days: daysAgo));
        return DateTime(d.year, d.month, d.day);
      }

      final entries = [
        WeightLogEntity(date: day(0), weightKg: 70.0),
        WeightLogEntity(date: day(45), weightKg: 71.0),
        WeightLogEntity(date: day(200), weightKg: 72.0),
      ];

      await tester.pumpWidget(_wrap(_buildScreen(entries)));
      await tester.pumpAndSettle();

      // Default selected is 30d: only 1 point (today) is in window, so chart shows empty state.
      expect(
        find.byKey(const Key('weightHistoryChartEmptyState')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('weightHistoryChart')), findsNothing);

      // Tap 60d segment: should now include the 45-day-old point, showing the chart.
      final button60 = find.text('90 d'); //: 30/90 d, 1 y, All
      expect(button60, findsOneWidget);
      await tester.tap(button60);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('weightHistoryChart')), findsOneWidget);
      expect(
        find.byKey(const Key('weightHistoryChartEmptyState')),
        findsNothing,
      );

      // Tap All segment: should show chart for all history including 200-day-old point.
      final buttonAll = find.text('All');
      expect(buttonAll, findsOneWidget);
      await tester.tap(buttonAll);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('weightHistoryChart')), findsOneWidget);
      expect(
        find.byKey(const Key('weightHistoryChartEmptyState')),
        findsNothing,
      );
    });
  });

  testWidgets('deleting an entry reloads Trends so its weight card drops '
      'the reading (#1359)', (tester) async {
    final recorder = ReloadRecorder()
      ..register()
      ..registerProfile();
    addTearDown(locator.reset);
    final today = DateTime.now();
    final entries = [
      WeightLogEntity(
        date: DateTime(today.year, today.month, today.day),
        weightKg: 72.0,
      ),
    ];

    await tester.pumpWidget(_wrap(_buildScreen(entries)));
    await tester.pumpAndSettle();

    await _swipe(tester, find.text('Today'));
    await tester.pumpAndSettle();

    expect(recorder.trendsReloaded, isTrue);
  });

  group('Add entry (#1367)', () {
    Future<String?> prefilled(
      WidgetTester tester,
      List<WeightLogEntity> entries, {
      double? profileKg,
    }) async {
      await tester.pumpWidget(
        _wrap(
          WeightHistoryScreen(
            getUsecase: _FakeGetWeightLogUsecase(entries),
            addUsecase: _FakeAddWeightLogUsecase(),
            deleteUsecase: _FakeDeleteWeightLogUsecase(),
            configRepository: _FakeConfigRepository(),
            getUserUsecase: profileKg == null
                ? null
                : _FakeGetUserUsecase(profileKg),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('weight-history-add'));
      await tester.pumpAndSettle();
      return tester
          .widget<TextField>(
            find.descendant(
              of: find.bySemanticsIdentifier('weight-history-weight-input'),
              matching: find.byType(TextField),
            ),
          )
          .controller
          ?.text;
    }

    testWidgets('starts from the profile weight, not a made-up 70 kg', (
      tester,
    ) async {
      expect(await prefilled(tester, const [], profileKg: 65), '65');
    });

    testWidgets('prefers the profile weight to an older reading', (
      tester,
    ) async {
      final entries = [
        WeightLogEntity(date: DateTime(2026, 1, 1), weightKg: 72),
      ];
      expect(await prefilled(tester, entries, profileKg: 65), '65');
    });

    testWidgets('falls back to the latest reading without a profile', (
      tester,
    ) async {
      final entries = [
        WeightLogEntity(date: DateTime(2026, 1, 1), weightKg: 72),
      ];
      expect(await prefilled(tester, entries), '72');
    });
  });

  testWidgets('deleting a row hands over that row, filed day and all, '
      'when its date shows a neighbouring day (#1418)', (tester) async {
    ReloadRecorder()
      ..register()
      ..registerProfile();
    addTearDown(locator.reset);
    final deleteUsecase = _FakeDeleteWeightLogUsecase();
    // A time-zone change moved the 10 March row's date onto 11 March, so
    // both rows show 11 March; only the filed day tells them apart.
    final entries = [
      WeightLogEntity(
        date: DateTime(2026, 3, 11),
        weightKg: 80.0,
        filedDay: DateTime(2026, 3, 10),
      ),
      WeightLogEntity(
        date: DateTime(2026, 3, 11),
        weightKg: 81.0,
        filedDay: DateTime(2026, 3, 11),
      ),
    ];

    await tester.pumpWidget(
      _wrap(_buildScreen(entries, deleteUsecase: deleteUsecase)),
    );
    await tester.pumpAndSettle();

    // swiped away, not a bin
    await _swipe(tester, find.text('80 ${l10nEn.kgLabel}'));
    await tester.pumpAndSettle();

    expect(deleteUsecase.deleted, hasLength(1));
    expect(deleteUsecase.deleted.single.weightKg, 80.0);
    expect(deleteUsecase.deleted.single.filedDay, DateTime(2026, 3, 10));
  });

  testWidgets('a delete says which weigh-in, and can be undone', (
    tester,
  ) async {
    final reloads = ReloadRecorder()
      ..register()
      ..registerProfile();
    addTearDown(locator.reset);
    final addUsecase = _FakeAddWeightLogUsecase();
    final entry = WeightLogEntity(date: DateTime(2026, 3, 11), weightKg: 80);
    await tester.pumpWidget(
      _wrap(_buildScreen([entry], addUsecase: addUsecase)),
    );
    await tester.pumpAndSettle();

    await _swipe(tester, find.text('Mar 11, 2026'));
    await tester.pumpAndSettle();
    // Home and the profile show the weight the delete left.
    expect(reloads.log, containsAll(['LoadProfileEvent', 'updateHomePage']));
    reloads.log.clear();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(addUsecase.added.single.weightKg, 80);
    expect(reloads.log, containsAll(['LoadProfileEvent', 'updateHomePage']));
  });

  testWidgets('Undo of a delete files it under its own day', (tester) async {
    ReloadRecorder()
      ..register()
      ..registerProfile();
    addTearDown(locator.reset);
    final addUsecase = _FakeAddWeightLogUsecase();
    final entry = WeightLogEntity(
      date: DateTime(2026, 3, 10),
      weightKg: 80,
      filedDay: DateTime(2026, 3, 11),
    );
    await tester.pumpWidget(
      _wrap(_buildScreen([entry], addUsecase: addUsecase)),
    );
    await tester.pumpAndSettle();

    await _swipe(tester, find.text('Mar 10, 2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(addUsecase.added.single.date, DateTime(2026, 3, 11));
  });

  // a tap opens a weigh-in in the dialog, its
  // weight and note filled in; saved on its day, it is not deleted
  testWidgets('a tapped weigh-in opens to edit, filled in', (tester) async {
    ReloadRecorder()
      ..register()
      ..registerProfile();
    addTearDown(locator.reset);
    final addUsecase = _FakeAddWeightLogUsecase();
    final deleteUsecase = _FakeDeleteWeightLogUsecase();
    final entry = WeightLogEntity(
      date: DateTime(2026, 3, 11),
      weightKg: 80,
      note: 'after the run',
    );
    await tester.pumpWidget(
      _wrap(
        _buildScreen(
          [entry],
          addUsecase: addUsecase,
          deleteUsecase: deleteUsecase,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mar 11, 2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('weigh-in-edit'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'after the run'), findsOneWidget);
    await tester.tap(find.text(l10nEn.dialogOKLabel));
    await tester.pumpAndSettle();

    expect(addUsecase.added.single.weightKg, 80);
    expect(addUsecase.added.single.date, DateTime(2026, 3, 11));
    expect(addUsecase.added.single.note, 'after the run');
    expect(deleteUsecase.deleted, isEmpty);
  });

  testWidgets("an added weigh-in reloads Home and the profile, as today's "
      'sets the weight', (tester) async {
    final reloads = ReloadRecorder()
      ..register()
      ..registerProfile();
    addTearDown(locator.reset);
    final addUsecase = _FakeAddWeightLogUsecase();
    await tester.pumpWidget(
      _wrap(_buildScreen(const [], addUsecase: addUsecase)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('weight-history-add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10nEn.dialogOKLabel));
    await tester.pumpAndSettle();

    expect(addUsecase.added, hasLength(1));
    expect(reloads.log, containsAll(['LoadProfileEvent', 'updateHomePage']));
  });

  testWidgets('the Weigh in shortcut opens the dialog once, not again '
      'after the save', (tester) async {
    ReloadRecorder()
      ..register()
      ..registerProfile();
    addTearDown(locator.reset);
    final addUsecase = _FakeAddWeightLogUsecase();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.supportedLocales,
        onGenerateRoute: (settings) => MaterialPageRoute(
          settings: RouteSettings(
            name: settings.name,
            arguments: const WeighInOnOpen(),
          ),
          builder: (_) => _buildScreen(const [], addUsecase: addUsecase),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10nEn.dialogOKLabel), findsOneWidget);
    await tester.tap(find.text(l10nEn.dialogOKLabel));
    await tester.pumpAndSettle();

    expect(addUsecase.added, hasLength(1));
    expect(find.text(l10nEn.dialogOKLabel), findsNothing);
  });

  testWidgets("the delete's Undo goes after a while, not onto every screen", (
    tester,
  ) async {
    ReloadRecorder()
      ..register()
      ..registerProfile();
    addTearDown(locator.reset);
    final entry = WeightLogEntity(date: DateTime(2026, 3, 11), weightKg: 80);
    await tester.pumpWidget(_wrap(_buildScreen([entry])));
    await tester.pumpAndSettle();
    await _swipe(tester, find.text('Mar 11, 2026'));
    await tester.pumpAndSettle();
    expect(find.text('Weigh-in deleted'), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('Weigh-in deleted'), findsNothing);
  });

  group('saved over the log itself', () {
    final now = DateTime.now();
    final today = _dayOf(now);
    DateTime daysAgo(int days) => DateTime(now.year, now.month, now.day - days);

    late _MemoryLog log;
    late _MemoryUsers users;

    setUp(() {
      log = _MemoryLog();
      users = _MemoryUsers(60);
    });

    Future<void> open(WidgetTester tester) async {
      ReloadRecorder()
        ..register()
        ..registerProfile();
      addTearDown(locator.reset);
      await tester.pumpWidget(
        _wrap(
          WeightHistoryScreen(
            getUsecase: _LiveGetWeightLogUsecase(log),
            addUsecase: AddWeightLogUsecase(log, users),
            deleteUsecase: DeleteWeightLogUsecase(log, users),
            configRepository: _FakeConfigRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> edit(WidgetTester tester, String rowDate) async {
      await tester.tap(find.text(rowDate));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('weigh-in-edit'));
      await tester.pumpAndSettle();
    }

    Future<void> pickDay(WidgetTester tester, DateTime day) async {
      await tester.tap(find.text(l10nEn.weightHistoryDateLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Switch to input'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.byType(TextField),
        ),
        '${day.month}/${day.day}/${day.year}',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.text('OK'),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> save(WidgetTester tester) async {
      await tester.tap(find.text(l10nEn.dialogOKLabel));
      await tester.pumpAndSettle();
    }

    testWidgets("today's weigh-in moved back stays the profile weight when "
        'it is still the newest', (tester) async {
      log
        ..file(daysAgo(3), 80)
        ..file(today, 82);
      users.user.weightKG = 82;
      await open(tester);

      await edit(tester, 'Today');
      await pickDay(tester, daysAgo(1));
      await save(tester);

      expect(log.rows.keys, unorderedEquals([daysAgo(3), daysAgo(1)]));
      expect(log.rows[daysAgo(1)]!.weightKg, 82);
      expect(users.user.weightKG, 82);
    });

    testWidgets('an edit after a time-zone change leaves no second row', (
      tester,
    ) async {
      // Filed on the 10th, it shows the 11th; the dialog opens on the 11th.
      log.file(DateTime(2026, 3, 10), 80, shownAs: DateTime(2026, 3, 11));
      await open(tester);

      await edit(tester, 'Mar 11, 2026');
      await save(tester);

      // Its date left alone, it stays in its own row.
      expect(log.rows.keys, [DateTime(2026, 3, 10)]);
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets('an edit after a time-zone change leaves the next row alone', (
      tester,
    ) async {
      log.file(DateTime(2026, 3, 11), 80, shownAs: DateTime(2026, 3, 10));
      log.file(DateTime(2026, 3, 10), 70, shownAs: DateTime(2026, 3, 9));
      await open(tester);

      await edit(tester, 'Mar 10, 2026');
      await save(tester);

      expect(log.rows.keys.toSet(), {
        DateTime(2026, 3, 10),
        DateTime(2026, 3, 11),
      });
      expect(log.rows[DateTime(2026, 3, 10)]!.weightKg, 70);
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets('an edit put back on the day it is filed under stays there', (
      tester,
    ) async {
      log.file(DateTime(2026, 3, 10), 80, shownAs: DateTime(2026, 3, 11));
      await open(tester);

      await edit(tester, 'Mar 11, 2026');
      await pickDay(tester, DateTime(2026, 3, 10));
      await save(tester);

      expect(log.rows.keys, [DateTime(2026, 3, 10)]);
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets("Weigh in over the day's weigh-in names it, and Undo brings "
        'it back', (tester) async {
      log.file(today, 72, note: 'after the run');
      users.user.weightKG = 72;
      await open(tester);

      await tester.tap(find.bySemanticsIdentifier('weight-history-add'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.bySemanticsIdentifier('weight-history-weight-input'),
          matching: find.byType(TextField),
        ),
        '75',
      );
      await save(tester);

      expect(log.rows[today]!.weightKg, 75);
      expect(users.user.weightKG, 75);
      expect(
        find.text("Replaced today's 72 ${l10nEn.kgLabel}"),
        findsOneWidget,
      );

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(log.rows[today]!.weightKg, 72);
      expect(log.rows[today]!.note, 'after the run');
      expect(users.user.weightKG, 72);
    });

    testWidgets('the bar for a replaced weigh-in goes after a while', (
      tester,
    ) async {
      log.file(today, 72);
      await open(tester);

      await tester.tap(find.bySemanticsIdentifier('weight-history-add'));
      await tester.pumpAndSettle();
      await save(tester);
      expect(find.text('Undo'), findsOneWidget);

      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets('a weigh-in moved onto a day with one names it, and Undo puts '
        'both back', (tester) async {
      final from = DateTime(2026, 3, 11), onto = DateTime(2026, 3, 9);
      log
        ..file(onto, 70)
        ..file(from, 71);
      await open(tester);

      await edit(tester, 'Mar 11, 2026');
      await pickDay(tester, onto);
      await save(tester);

      expect(log.rows.keys, [onto]);
      expect(log.rows[onto]!.weightKg, 71);
      expect(
        find.text("Replaced Mar 9's 70 ${l10nEn.kgLabel}"),
        findsOneWidget,
      );

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(log.rows.keys, unorderedEquals([onto, from]));
      expect(log.rows[onto]!.weightKg, 70);
      expect(log.rows[from]!.weightKg, 71);
    });

    testWidgets("today's weigh-in moved onto a taken day, undone, is the "
        'profile weight again', (tester) async {
      log
        ..file(daysAgo(1), 70)
        ..file(today, 71);
      users.user.weightKG = 71;
      await open(tester);

      await edit(tester, 'Today');
      await pickDay(tester, daysAgo(1));
      await save(tester);
      expect(users.user.weightKG, 71);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(log.rows[daysAgo(1)]!.weightKg, 70);
      expect(log.rows[today]!.weightKg, 71);
      expect(users.user.weightKG, 71);
    });

    testWidgets('a weigh-in on an empty day replaces nothing', (tester) async {
      log.file(daysAgo(1), 70);
      await open(tester);

      await tester.tap(find.bySemanticsIdentifier('weight-history-add'));
      await tester.pumpAndSettle();
      await save(tester);

      expect(log.rows.keys, unorderedEquals([daysAgo(1), today]));
      expect(find.text('Undo'), findsNothing);
    });
  });
}
