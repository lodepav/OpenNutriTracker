import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_weight_log_usecase.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_ui.dart';
import 'package:opennutritracker/fork/adaptive/auto_check_in.dart';
import 'package:opennutritracker/fork/adaptive/expenditure.dart';
import 'package:opennutritracker/fork/adaptive/partial_days.dart';
import 'package:opennutritracker/fork/layout/home_layout.dart';
import 'package:opennutritracker/fork/layout/layout_store.dart';

final _today = DateTime(2026, 10, 22);

/// The day [_TrackedDays] logs at half, five days back.
final _halfDay = DateTime(2026, 10, 17);

class _User extends Fake implements GetUserUsecase {
  @override
  Future<UserEntity> getUserData() async => UserEntity(
    birthday: DateTime(1990, 1, 1),
    heightCM: 180,
    weightKG: 90,
    gender: UserGenderEntity.male,
    goal: UserWeightGoalEntity.loseWeight,
    pal: UserPALEntity.active,
    weeklyWeightGoalKg: -0.5,
    targetWeightKg: 80,
  );
}

class _Weights extends Fake implements GetWeightLogUsecase {
  @override
  Future<List<WeightLogEntity>> getAllEntries() async => [
    for (var d = 59; d >= 0; d -= 2)
      WeightLogEntity(
        date: DateTime(_today.year, _today.month, _today.day - d),
        weightKg: 90 - 0.5 * (59 - d) / 7,
      ),
  ];
}

/// 60 days at 2,000 kcal, the days [halfBack] back (by default
/// [_halfDay]) at 1,000 and today, still being eaten, at 400.
class _TrackedDays extends Fake implements GetTrackedDayUsecase {
  final Set<int> halfBack;

  /// While set and not completed, the days are not read yet.
  Completer<void>? gate;

  _TrackedDays([this.halfBack = const {5}]);

  @override
  Future<List<TrackedDayEntity>> getTrackedDaysByRange(
    DateTime start,
    DateTime end,
  ) async {
    await gate?.future;
    return [
      for (var d = 0; d < 60; d++)
        TrackedDayEntity(
          day: DateTime(_today.year, _today.month, _today.day - d),
          calorieGoal: 2000,
          caloriesTracked: d == 0
              ? 400
              : halfBack.contains(d)
              ? 1000
              : 2000,
        ),
    ];
  }
}

class _MemoryStore extends AdaptiveStore {
  final records = <CheckInRecord>[];
  final keys = <String, Object?>{};

  /// While set and not completed, a day left out is not saved yet.
  Completer<void>? saveGate;

  @override
  Future<Object?> readKey(String key) async => keys[key];

  @override
  Future<void> writeKey(String key, Object? value) async => keys[key] = value;

  @override
  Future<List<CheckInRecord>> history() async => records;

  @override
  Future<void> addCheckIn(CheckInRecord record) async => records.add(record);

  @override
  Future<void> setSkipped(DateTime day, bool skipped) async {
    await saveGate?.future;
    AdaptiveStore.skipped.value = {
      ...AdaptiveStore.skipped.value.where((d) => d != day),
      if (skipped) day,
    };
  }

  @override
  Future<void> setWhole(DateTime day, bool isWhole) async =>
      AdaptiveStore.whole.value = {...AdaptiveStore.whole.value, day};
}

/// [n] days at [kcal], with [others] by index in their place.
List<AdaptiveDay> _days(
  int n, {
  double kcal = 2000,
  Map<int, double?> others = const {},
}) => [
  for (var i = 0; i < n; i++)
    AdaptiveDay(intakeKcal: others.containsKey(i) ? others[i] : kcal),
];

void main() {
  group('likelyPartlyLogged', () {
    test('a day at half the usual is found, with the usual', () {
      final found = likelyPartlyLogged(_days(30, others: {12: 1000}));
      expect(found.map((f) => f.day), [12]);
      expect(found.single.usualKcal, 2000);
    });

    test('a light day at 65% is not', () {
      expect(likelyPartlyLogged(_days(30, others: {12: 1300})), isEmpty);
    });

    test('the usual is the median: a feast does not hide a half day', () {
      final found = likelyPartlyLogged(
        _days(30, others: {10: 6000, 11: 6000, 12: 1100}),
      );
      expect(found.map((f) => f.day), [12]);
    });

    test('needs a week of other logged days around it', () {
      expect(likelyPartlyLogged(_days(7, others: {3: 900})), isEmpty);
      expect(likelyPartlyLogged(_days(8, others: {3: 900})), hasLength(1));
    });

    test('a day not logged is already left out', () {
      expect(
        likelyPartlyLogged(_days(30, others: {12: null, 13: 150})),
        isEmpty,
      );
    });

    test('low days as a habit, two fasting days a week, are not slips', () {
      final fasting = _days(
        42,
        others: {
          for (var i = 0; i < 42; i++)
            if (i % 7 == 1 || i % 7 == 4) i: 600.0,
        },
      );
      expect(likelyPartlyLogged(fasting), isEmpty);
    });

    test('the usual follows the days around, not the whole history', () {
      // A cut from 3,000 to 1,900: its days are not half days of the bulk.
      final days = [..._days(40, kcal: 3000), ..._days(40, kcal: 1700)];
      expect(likelyPartlyLogged(days), isEmpty);
    });
  });

  group('the check-in asks', () {
    late _MemoryStore store;
    late AdaptiveService service;

    setUp(() {
      store = _MemoryStore();
      service = AdaptiveService(
        _User(),
        _Weights(),
        _TrackedDays(),
        store,
        () => _today.add(const Duration(hours: 9)),
      );
    });

    tearDown(() {
      AdaptiveStore.settings.value = const AdaptiveSettings();
      AdaptiveStore.skipped.value = const {};
      AdaptiveStore.whole.value = const {};
      AutoCheckIn.accepted.value = null;
      AutoCheckIn.waiting.value = null;
      LayoutStore.current(homeSectionsKey).value = (
        order: const [],
        hidden: const {},
      );
    });

    /// A week old, with no goal or settings behind it: a weekly one is due.
    CheckInRecord weekOld() => CheckInRecord(
      date: DateTime(_today.year, _today.month, _today.day - 8),
      expenditureKcal: 2600,
      proposedKcal: 2100,
      acceptedKcal: 2100,
    );

    String field(WidgetTester tester) => tester
        .widget<TextField>(find.byKey(const ValueKey('check-in-target')))
        .controller!
        .text;

    test('the half day is asked about; today, still eaten, is not', () async {
      final days = await service.partialDays();
      expect(days.map((d) => d.date), [_halfDay]);
      expect(days.single.kcal, 1000);
      expect(days.single.usualKcal, 2000);
    });

    test('a day 27 days back is asked about; 28 back, outside the '
        'window, is not', () async {
      service = AdaptiveService(
        _User(),
        _Weights(),
        _TrackedDays({27, 28}),
        store,
        () => _today.add(const Duration(hours: 9)),
      );
      expect((await service.partialDays()).map((d) => d.date), [
        DateTime(2026, 9, 25),
      ]);
    });

    test('a day kept or left out is not asked about again', () async {
      await service.keepDay(_halfDay);
      expect(await service.partialDays(), isEmpty);

      AdaptiveStore.whole.value = const {};
      await service.leaveOutDay(_halfDay);
      expect(await service.partialDays(), isEmpty);
    });

    test('leaving the day out raises the estimate', () async {
      final before = (await service.checkIn()).expenditureKcal;
      await service.leaveOutDay(_halfDay);
      expect((await service.checkIn()).expenditureKcal, greaterThan(before));
    });

    test('an automatic check-in waits for the answer', () async {
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
        autoAcceptCheckIn: true,
      );

      await AutoCheckIn.run(service);
      expect(store.records, isEmpty);

      await service.keepDay(_halfDay);
      await AutoCheckIn.run(service);
      expect(store.records, hasLength(1));
    });

    testWidgets('Home says an automatic check-in waits for the answer', (
      tester,
    ) async {
      store.records.add(weekOld());
      Future<void> pump() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AdaptiveCheckInCard(service: service, onAccepted: () {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
      );
      await pump();
      expect(find.text('Weekly check-in'), findsOneWidget);
      expect(find.textContaining('partly logged'), findsNothing);

      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
        autoAcceptCheckIn: true,
      );
      await pump();
      expect(find.text('Weekly check-in'), findsOneWidget);
      expect(
        find.text('Waiting for your answer on a day that looks partly logged.'),
        findsOneWidget,
      );

      // Answered on the check-in and back without accepting: it goes ahead.
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.tap(find.text('Weekly check-in'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Count as full day'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.textContaining('partly logged'), findsNothing);
      expect(store.records, hasLength(2));
    });

    testWidgets('Home says a first automatic check-in waits too', (
      tester,
    ) async {
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
        autoAcceptCheckIn: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveCheckInCard(service: service, onAccepted: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your first target'), findsOneWidget);
      expect(
        find.text('Waiting for your answer on a day that looks partly logged.'),
        findsOneWidget,
      );

      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.tap(find.text('Your first target'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Count as full day'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(store.records, hasLength(1));
    });

    testWidgets('a check-in due behind the banner shows once it is dismissed', (
      tester,
    ) async {
      store.records.add(weekOld());
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
        autoAcceptCheckIn: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveCheckInCard(service: service, onAccepted: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // an earlier one set, then the goal changed: another is due
      AutoCheckIn.accepted.value = (
        checkIn: await service.checkIn(),
        reason: CheckInReason.first,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();

      expect(
        find.text('Waiting for your answer on a day that looks partly logged.'),
        findsOneWidget,
      );
    });

    testWidgets('the screen shows the day and takes the answer', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: CheckInScreen(service: service)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Logged only in part?'), findsOneWidget);
      expect(find.textContaining('usually about'), findsOneWidget);
      String field() => tester
          .widget<TextField>(find.byKey(const ValueKey('check-in-target')))
          .controller!
          .text;
      final before = field();
      // typed, then moved by the answer: the new proposal replaces it
      await tester.enterText(
        find.byKey(const ValueKey('check-in-target')),
        '1234',
      );

      await tester.tap(find.text('Leave out'));
      await tester.pumpAndSettle();

      expect(find.text('Logged only in part?'), findsNothing);
      expect(AdaptiveStore.skipped.value, {_halfDay});
      // The field follows the new proposal, not the one before the answer.
      final proposed = (await service.checkIn()).proposedTargetKcal.round();
      expect(field(), isNot(before));
      expect(field(), '$proposed');
    });

    testWidgets('Leave out says so, and Undo counts the day again', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: CheckInScreen(service: service)),
      );
      await tester.pumpAndSettle();
      final before = (await service.checkIn()).proposedTargetKcal;

      await tester.tap(find.text('Leave out'));
      await tester.pumpAndSettle();
      expect(find.text('Oct 17 left out of the check-in'), findsOneWidget);
      expect(AdaptiveStore.skipped.value, {_halfDay});

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(AdaptiveStore.skipped.value, isEmpty);
      // asked again, on the check-in before the answer
      expect(find.text('Logged only in part?'), findsOneWidget);
      expect(
        (await service.checkIn()).proposedTargetKcal,
        closeTo(before, 0.01),
      );

      // Undone, the automatic check-in waits for the answer again.
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
        autoAcceptCheckIn: true,
      );
      await tester.runAsync(() => AutoCheckIn.run(service));
      expect(store.records, isEmpty);
      expect(AutoCheckIn.waiting.value, isNotNull);
    });

    testWidgets('the day is counted by "Count as full day", not "Keep"', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: CheckInScreen(service: service)),
      );
      await tester.pumpAndSettle();
      // Only the check-in's own Keep, of the target, is called that.
      expect(find.text('Keep'), findsNothing);
      expect(find.text('Count as full day'), findsOneWidget);
    });

    testWidgets('Count as full day leaves a typed target', (tester) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: CheckInScreen(service: service)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('check-in-target')),
        '1800',
      );
      await tester.tap(find.text('Count as full day'));
      await tester.pumpAndSettle();

      expect(find.text('Logged only in part?'), findsNothing);
      expect(field(tester), '1800');
    });

    testWidgets('Accept and Keep current target wait for the check-in an '
        'answer reads again', (tester) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      store.records.add(weekOld());
      final tracked = _TrackedDays();
      service = AdaptiveService(
        _User(),
        _Weights(),
        tracked,
        store,
        () => _today.add(const Duration(hours: 9)),
      );
      await tester.pumpWidget(
        MaterialApp(home: CheckInScreen(service: service)),
      );
      await tester.pumpAndSettle();
      bool enabled(String key) =>
          tester.widget<ButtonStyleButton>(find.byKey(ValueKey(key))).enabled;
      expect(enabled('check-in-accept'), isTrue);
      expect(enabled('check-in-keep'), isTrue);

      store.saveGate = Completer();
      tracked.gate = Completer();
      await tester.tap(find.text('Leave out'));
      await tester.pump();

      // saving the answer
      expect(enabled('check-in-accept'), isFalse);
      expect(enabled('check-in-keep'), isFalse);
      await tester.tap(find.text('Accept'), warnIfMissed: false);
      await tester.pump();
      expect(store.records, hasLength(1));

      // reading the check-in again
      store.saveGate!.complete();
      await tester.pump();
      expect(AdaptiveStore.skipped.value, {_halfDay});
      expect(enabled('check-in-accept'), isFalse);
      expect(enabled('check-in-keep'), isFalse);

      tracked.gate!.complete();
      tracked.gate = null;
      await tester.pumpAndSettle();
      expect(enabled('check-in-accept'), isTrue);
      expect(enabled('check-in-keep'), isTrue);
    });

    testWidgets('with the card hidden, Home says once that an automatic '
        'check-in waits, and opens it', (tester) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      store.records.add(weekOld());
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
        autoAcceptCheckIn: true,
      );
      final layout = LayoutStore.current(homeSectionsKey);
      const note =
          'A check-in is waiting for your answer on a day that looks partly '
          'logged.';
      Future<void> home() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: HomeSectionsList(sections: {'dashboard': Text('Summary')}),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await AutoCheckIn.run(service);
      expect(store.records, hasLength(1));

      // The card shown says it itself.
      await home();
      expect(find.text(note), findsNothing);

      layout.value = (order: const [], hidden: {'checkIn'});
      await home();
      expect(find.text(note), findsOneWidget);

      // Not again for the same check-in, on a resume or a new Home.
      await AutoCheckIn.run(service);
      await home();
      expect(find.text(note), findsNothing);

      store.keys.clear();
      await home();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(CheckInScreen), findsOneWidget);

      // Answered and back without accepting: it goes ahead.
      await tester.tap(find.text('Count as full day'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(store.records, hasLength(2));
    });

    testWidgets('with the card hidden, Home says a first check-in waits too', (
      tester,
    ) async {
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
        autoAcceptCheckIn: true,
      );
      LayoutStore.current(homeSectionsKey).value = (
        order: const [],
        hidden: {'checkIn'},
      );

      await AutoCheckIn.run(service);
      expect(store.records, isEmpty);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HomeSectionsList(sections: {'dashboard': Text('Summary')}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'A check-in is waiting for your answer on a day that looks partly '
          'logged.',
        ),
        findsOneWidget,
      );
    });
  });
}
