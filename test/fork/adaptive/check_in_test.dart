import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
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
import 'package:opennutritracker/fork/adaptive/check_in.dart';
import 'package:opennutritracker/fork/adaptive/expenditure.dart';
import 'package:opennutritracker/fork/adaptive/expenditure_card.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan_card.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/fork/adaptive/trend_points.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:provider/provider.dart';

final _today = DateTime(2026, 10, 22);

UserEntity _user() => UserEntity(
  birthday: DateTime(1990, 1, 1),
  heightCM: 180,
  weightKG: 90,
  gender: UserGenderEntity.male,
  goal: UserWeightGoalEntity.loseWeight,
  pal: UserPALEntity.active,
  weeklyWeightGoalKg: -0.5,
  targetWeightKg: 80,
);

class _User extends Fake implements GetUserUsecase {
  final double rate;

  _User({this.rate = -0.5});

  @override
  Future<UserEntity> getUserData() async => _user()
    ..weeklyWeightGoalKg = rate
    ..goal = rate == 0
        ? UserWeightGoalEntity.maintainWeight
        : UserWeightGoalEntity.loseWeight;
}

/// 60 days of losing 0.5 kg a week on 2,000 kcal, weighed every other day.
class _Weights extends Fake implements GetWeightLogUsecase {
  @override
  Future<List<WeightLogEntity>> getAllEntries() async => [
    for (var d = 59; d >= 0; d -= 2)
      WeightLogEntity(
        date: _today.subtract(Duration(days: d)),
        weightKg: 90 - 0.5 * (59 - d) / 7,
      ),
  ];
}

class _NoWeights extends Fake implements GetWeightLogUsecase {
  @override
  Future<List<WeightLogEntity>> getAllEntries() async => [];
}

class _TrackedDays extends Fake implements GetTrackedDayUsecase {
  @override
  Future<List<TrackedDayEntity>> getTrackedDaysByRange(
    DateTime start,
    DateTime end,
  ) async => [
    for (var d = 0; d < 60; d++)
      TrackedDayEntity(
        day: _today.subtract(Duration(days: d)),
        calorieGoal: 2000,
        caloriesTracked: 2000,
      ),
  ];
}

/// A new user: the weigh-in from onboarding, nothing logged.
class _OneWeighIn extends Fake implements GetWeightLogUsecase {
  @override
  Future<List<WeightLogEntity>> getAllEntries() async => [
    WeightLogEntity(date: _today, weightKg: 90),
  ];
}

class _NoLogs extends Fake implements GetTrackedDayUsecase {
  @override
  Future<List<TrackedDayEntity>> getTrackedDaysByRange(
    DateTime start,
    DateTime end,
  ) async => [];
}

/// The check-in on a phone's width at 200% text.
Future<void> _pumpLarge(WidgetTester tester, AdaptiveService service) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: CheckInScreen(service: service),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late Directory dir;
  late AdaptiveStore store;
  late AdaptiveService service;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('adaptive');
    Hive.init(dir.path);
    store = AdaptiveStore(() => Hive.openBox<dynamic>(AdaptiveStore.boxName));
    service = AdaptiveService(
      _User(),
      _Weights(),
      _TrackedDays(),
      store,
      () => _today.add(const Duration(hours: 9)),
    );
    AdaptiveStore.settings.value = const AdaptiveSettings();
  });

  tearDown(() async {
    AdaptiveStore.settings.value = const AdaptiveSettings();
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  group('computeCheckIn', () {
    CheckIn run({double? previous, int days = 60}) => computeCheckIn(
      CheckInInputs(
        days: [
          for (var d = 0; d < days; d++)
            AdaptiveDay(intakeKcal: 2000, weightKg: 90 - 0.5 * d / 7),
        ],
        priorKcal: 2500,
        goalRateKgPerWeek: -0.5,
        bodyFatPercent: 25,
        targetWeightKg: 80,
        previousBaseKcal: previous,
        taper: (adjustment, _) => adjustment,
      ),
    );

    test('the target is expenditure less the energy of the goal', () {
      final checkIn = run();

      // 0.5 kg/week at ~22 kg of fat (~7,000 kcal/kg) is ~500 kcal/day.
      expect(checkIn.expenditureKcal, closeTo(2500, 60));
      expect(
        checkIn.uncappedTargetKcal,
        closeTo(checkIn.expenditureKcal - 500, 30),
      );
      expect(checkIn.enoughData, isTrue);
      expect(checkIn.weekChangeKg, closeTo(-0.5, 0.05));
    });

    test('a check-in moves the expenditure under the target at most '
        '200 kcal, and the goal in full', () {
      final c = run(previous: 2000);
      expect(c.baseKcal, 2200);
      expect(
        c.proposedTargetKcal,
        closeTo(c.uncappedTargetKcal - (c.expenditureKcal - 2200), 0.01),
      );
      // The goal's energy is the whole of the gap below the base.
      expect(c.proposedTargetKcal, closeTo(2200 - 500, 30));
    });

    test('nothing holds the estimate back before the first check-in or '
        'while it calibrates', () {
      final first = run();
      expect(first.proposedTargetKcal, first.uncappedTargetKcal);
      // 20 days: 6 updates past the warm-up, under the 16 calibrating.
      final calibrating = run(previous: 1000, days: 20);
      expect(calibrating.baseKcal, calibrating.expenditureKcal);
    });

    test('the target weight is about 13 weeks off at either pace', () {
      final checkIn = run();

      // The scale is at 85.8 kg and the trend lags it a little above.
      expect(checkIn.daysToTargetAtGoal, inInclusiveRange(80, 100));
      expect(checkIn.daysToTargetAtTrend, inInclusiveRange(80, 100));
    });
  });

  group('AdaptiveService', () {
    test('reads the profile, weight log and tracked days', () async {
      final checkIn = await service.checkIn();

      expect(checkIn.loggedDays, 7);
      expect(checkIn.weighIns, inInclusiveRange(3, 4));
      expect(checkIn.expenditureKcal, greaterThan(2200));
      // The first check-in has no estimate before it to hold to.
      expect(checkIn.proposedTargetKcal, checkIn.uncappedTargetKcal);
      expect(checkIn.uncappedTargetKcal, lessThan(checkIn.expenditureKcal));
      expect(checkIn.goalRateKgPerWeek, -0.5);
      expect(checkIn.targetWeightKg, 80);
    });

    test(
      'the accepted target is the goal only while the switch is on',
      () async {
        final checkIn = await service.checkIn();
        await service.accept(checkIn, 2100);

        expect((await forkKcalGoal(_today)).target, isNull);
        expect((await forkKcalGoal(_today, store)).target, isNull);
        await store.save(const AdaptiveSettings(adaptiveTarget: true));
        expect((await forkKcalGoal(_today, store)).target, 2100);
      },
    );

    test('another profile answers with its own switch and target', () async {
      await store.save(const AdaptiveSettings(adaptiveTarget: true));
      await service.accept(await service.checkIn(), 2100);
      final other = AdaptiveStore(() => Hive.openBox<dynamic>('other'));

      expect((await forkKcalGoal(_today, other)).target, isNull);
      await other.save(const AdaptiveSettings(adaptiveTarget: true));
      expect((await forkKcalGoal(_today, other)).target, isNull);
      expect((await forkKcalGoal(_today, store)).target, 2100);
    });

    test('a check-in is due a week after the last', () async {
      expect(await service.checkInDue(), isFalse);
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
      );
      expect(await service.checkInDue(), isTrue);

      await service.accept(await service.checkIn(), 2100);
      expect(await service.checkInDue(), isFalse);
    });

    test('a changed goal is due a check-in at once', () async {
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
      );
      await service.accept(await service.checkIn(), 2100);
      final maintain = AdaptiveService(
        _User(rate: 0),
        _Weights(),
        _TrackedDays(),
        store,
        () => _today.add(const Duration(hours: 9)),
      );
      expect(await service.goalChanged(), isFalse);
      expect(await maintain.goalChanged(), isTrue);
      expect(await maintain.checkInDue(), isTrue);

      final checkIn = await maintain.checkIn();
      // The 500 kcal of the loss goal is all gone in this one check-in.
      expect(checkIn.proposedTargetKcal, closeTo(checkIn.expenditureKcal, 1));
      await maintain.accept(checkIn, checkIn.proposedTargetKcal);
      expect(await maintain.checkInDue(), isFalse);
    });

    test('settings the target is built under are due a check-in', () async {
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
      );
      await service.accept(await service.checkIn(), 2100);
      expect(await service.checkInDue(), isFalse);

      // Responsiveness leaves the target as it is; activity counted or a
      // flat kcal per kg does not.
      AdaptiveStore.settings.value = AdaptiveStore.settings.value.copyWith(
        responsiveness: Responsiveness.responsive,
      );
      expect(await service.checkInDue(), isFalse);
      for (final changed in [
        const AdaptiveSettings(
          adaptiveTarget: true,
          activityMode: ActivityMode.daily,
        ),
        const AdaptiveSettings(adaptiveTarget: true, flatEnergy: true),
      ]) {
        AdaptiveStore.settings.value = changed;
        expect(await service.basisChanged(), isTrue, reason: '$changed');
        expect(await service.checkInDue(), isTrue);
      }
      await service.accept(await service.checkIn(), 2100);
      expect(await service.checkInDue(), isFalse);

      final record = (await store.lastCheckIn())!;
      expect(CheckInRecord.fromJson(record.toJson()).basis, record.basis);
      // An older record, without one, is not due for it.
      final older = CheckInRecord.fromJson(
        {...record.toJson()}..remove('basis'),
      );
      expect(older.basisChanged(const AdaptiveSettings()), isFalse);
    });

    test("a check-in under other settings gives no change in the week's "
        'activity', () async {
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
        activityMode: ActivityMode.daily,
      );
      await service.accept(await service.checkIn(), 2100);
      // The daily mode keeps none of its activity in the target: the
      // weekly mode's first check-in has nothing to compare with.
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
        activityMode: ActivityMode.weekly,
      );
      expect((await service.checkIn()).activityChangeKcal, isNull);

      await service.accept(await service.checkIn(), 2100);
      expect((await service.checkIn()).activityChangeKcal, 0);
    });

    test(
      'a check-in is capped against a base of the same settings only',
      () async {
        const settings = AdaptiveSettings(
          adaptiveTarget: true,
          maxCheckInChangeKcal: 100,
        );
        AdaptiveStore.settings.value = settings;
        final free = (await service.checkIn()).baseKcal;
        await store.addCheckIn(
          CheckInRecord(
            date: _today.subtract(const Duration(days: 7)),
            expenditureKcal: free - 500,
            proposedKcal: 2000,
            acceptedKcal: 2000,
            baseKcal: free - 500,
            basis: settings.targetBasis,
          ),
        );
        expect((await service.checkIn()).baseKcal, closeTo(free - 400, 0.01));

        AdaptiveStore.settings.value = settings.copyWith(
          activityMode: ActivityMode.weekly,
        );
        final switched = await service.checkIn();
        expect(switched.baseKcal, closeTo(free, 0.01));

        // Switched back, as auto-accept takes each switch: capped against
        // the record of these settings again, not the switch's.
        await service.accept(switched, switched.proposedTargetKcal);
        AdaptiveStore.settings.value = settings;
        expect((await service.checkIn()).baseKcal, closeTo(free - 400, 0.01));
      },
    );

    test("switches in a day keep one record of their own", () async {
      const settings = AdaptiveSettings(adaptiveTarget: true);
      await store.addCheckIn(
        CheckInRecord(
          date: _today.subtract(const Duration(days: 3)),
          expenditureKcal: 2500,
          proposedKcal: 2000,
          acceptedKcal: 2000,
          baseKcal: 2500,
          basis: settings.targetBasis,
        ),
      );
      // Back and forth, landing on the seed's settings on the way.
      for (final s in [
        settings.copyWith(activityMode: ActivityMode.daily),
        settings,
        settings.copyWith(flatEnergy: true),
        settings,
      ]) {
        AdaptiveStore.settings.value = s;
        final due = await service.checkIn();
        await service.accept(due, due.proposedTargetKcal);
      }
      final history = await store.history();
      expect(history, hasLength(2));
      expect(history.last.basis, settings.targetBasis);

      // A check-in of the same settings is a record of its own; a switch
      // after it takes its place, as the day's target is the switch's.
      final weekly = await service.checkIn();
      await service.accept(weekly, weekly.proposedTargetKcal);
      expect(await store.history(), hasLength(3));
      AdaptiveStore.settings.value = settings.copyWith(flatEnergy: true);
      final due = await service.checkIn();
      await service.accept(due, due.proposedTargetKcal);
      final last = await store.history();
      expect(last, hasLength(3));
      expect(last.last.basis, AdaptiveStore.settings.value.targetBasis);
    });

    test('a record of these settings weeks before the last is no mark', () {
      const settings = AdaptiveSettings(adaptiveTarget: true);
      CheckInRecord at(int daysAgo, AdaptiveSettings s) => CheckInRecord(
        date: _today.subtract(Duration(days: daysAgo)),
        expenditureKcal: 2500,
        proposedKcal: 2000,
        acceptedKcal: 2000,
        baseKcal: 2500,
        basis: s.targetBasis,
      );
      final daily = settings.copyWith(activityMode: ActivityMode.daily);
      expect(
        AdaptiveService.capMark([at(30, settings), at(0, daily)], settings),
        isNull,
      );
      expect(
        AdaptiveService.capMark([at(7, settings), at(0, daily)], settings),
        isNotNull,
      );
    });

    test('a record without its settings gives no activity change', () async {
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
        activityMode: ActivityMode.weekly,
      );
      await store.addCheckIn(
        CheckInRecord(
          date: _today.subtract(const Duration(days: 7)),
          expenditureKcal: 2500,
          proposedKcal: 2000,
          acceptedKcal: 2000,
          activityKcal: 0,
          baseKcal: 2500,
        ),
      );
      expect((await service.checkIn()).activityChangeKcal, isNull);
    });

    test('the settings are saved and loaded', () async {
      await store.save(
        const AdaptiveSettings(smoothedTrend: true, cycleWindow: true),
      );
      AdaptiveStore.settings.value = const AdaptiveSettings();

      await store.load();

      expect(AdaptiveStore.settings.value.smoothedTrend, isTrue);
      expect(AdaptiveStore.settings.value.adaptiveTarget, isFalse);
      expect(AdaptiveStore.settings.value.cycleWindow, isTrue);
    });
  });

  test('the chart gets a smoothed point a day only when chosen', () async {
    final entries = await _Weights().getAllEntries();
    expect(smoothedTrendPoints(entries), isNull);

    AdaptiveStore.settings.value = const AdaptiveSettings(smoothedTrend: true);
    final points = smoothedTrendPoints(entries)!;

    expect(points, hasLength(59));
    expect(points.first.weightKg, 90);
    expect(points.last.weightKg, lessThan(90));
  });

  testWidgets('accepting the check-in hides the card and refreshes', (
    tester,
  ) async {
    AdaptiveStore.settings.value = const AdaptiveSettings(adaptiveTarget: true);
    final memory = _MemoryStore();
    var refreshed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveCheckInCard(
            service: AdaptiveService(
              _User(),
              _Weights(),
              _TrackedDays(),
              memory,
              () => _today.add(const Duration(hours: 9)),
            ),
            onAccepted: () => refreshed++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // None accepted yet: the first, not a weekly one.
    expect(find.text('Weekly check-in'), findsNothing);
    await tester.tap(find.text('Your first target'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();

    expect(refreshed, 1);
    expect(find.text('Your first target'), findsNothing);
    expect(memory.records, hasLength(1));
  });

  testWidgets('a kilojoule user reads and types the target in kJ', (
    tester,
  ) async {
    final memory = _MemoryStore();
    final service = AdaptiveService(
      _User(),
      _Weights(),
      _TrackedDays(),
      memory,
      () => _today.add(const Duration(hours: 9)),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => EnergyUnitProvider(usesKilojoules: true),
        child: MaterialApp(home: CheckInScreen(service: service)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining(' kJ'), findsWidgets);
    expect(find.textContaining('kcal'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('check-in-target')),
      '8368',
    );
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();

    expect(memory.records.single.acceptedKcal, closeTo(2000, 0.01));
  });

  testWidgets('the first check-in shows the target in use and the change', (
    tester,
  ) async {
    locator.registerSingleton<GetKcalGoalUsecase>(_Goal());
    addTearDown(locator.unregister<GetKcalGoalUsecase>);
    final service = AdaptiveService(
      _User(),
      _Weights(),
      _TrackedDays(),
      _MemoryStore(),
      () => _today.add(const Duration(hours: 9)),
    );
    final checkIn = await tester.runAsync(service.checkIn);
    await tester.pumpWidget(MaterialApp(home: CheckInScreen(service: service)));
    await tester.pumpAndSettle();

    expect(find.text('Current target'), findsOneWidget);
    expect(find.text('2847 kcal'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    // The rows add up as shown.
    final proposed = checkIn!.proposedTargetKcal.toInt();
    expect(find.text('${proposed - 2847} kcal'), findsOneWidget);
    expect(
      find.textContaining(
        'That is the expenditure less '
        '${checkIn.expenditureKcal.toInt() - proposed} kcal',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the first check-in leaves today\'s weekday shift out of the '
      'target in use, as the proposal does', (tester) async {
    locator.registerSingleton<GetKcalGoalUsecase>(_Goal());
    locator.registerSingleton<GetConfigUsecase>(_Config());
    addTearDown(locator.unregister<GetKcalGoalUsecase>);
    addTearDown(locator.unregister<GetConfigUsecase>);
    AdaptiveStore.settings.value = const AdaptiveSettings(
      weekdayOffsets: [300, 300, 300, 300, 300, 300, 300],
    );
    addTearDown(() => AdaptiveStore.settings.value = const AdaptiveSettings());
    final service = AdaptiveService(
      _User(),
      _Weights(),
      _TrackedDays(),
      _MemoryStore(),
      () => _today.add(const Duration(hours: 9)),
    );
    await tester.pumpWidget(MaterialApp(home: CheckInScreen(service: service)));
    await tester.pumpAndSettle();

    expect(find.text('2547 kcal'), findsOneWidget);
  });

  testWidgets("a new user's first check-in says it is from the profile", (
    tester,
  ) async {
    final service = AdaptiveService(
      _User(),
      _OneWeighIn(),
      _NoLogs(),
      _MemoryStore(),
      () => _today.add(const Duration(hours: 9)),
    );
    await _pumpLarge(tester, service);

    expect(find.textContaining('Your first target'), findsOneWidget);
    expect(find.textContaining('under the formula'), findsOneWidget);
    // No week before it to report, nor to carry the expenditure from.
    expect(find.text('Past week'), findsNothing);
    expect(find.textContaining('Not enough data'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a later check-in without an update keeps its past week', (
    tester,
  ) async {
    final memory = _MemoryStore();
    final service = AdaptiveService(
      _User(),
      _OneWeighIn(),
      _NoLogs(),
      memory,
      () => _today.add(const Duration(hours: 9)),
    );
    await service.accept(await service.checkIn(), 2000);
    await _pumpLarge(tester, service);

    expect(find.textContaining('Your first target'), findsNothing);
    expect(find.text('Past week'), findsOneWidget);
    expect(find.textContaining('Not enough data'), findsOneWidget);
  });

  testWidgets('a later check-in shows the current target and the change', (
    tester,
  ) async {
    final service = AdaptiveService(
      _User(),
      _Weights(),
      _TrackedDays(),
      _MemoryStore(),
      () => _today.add(const Duration(hours: 9)),
    );
    await service.accept(await service.checkIn(), 2000);
    // As shown: the rows add up.
    final change = (await service.checkIn()).proposedTargetKcal.toInt() - 2000;
    await _pumpLarge(tester, service);

    final current = find.text('Current target');
    await tester.scrollUntilVisible(current, 200);
    expect(find.text('2000 kcal'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Change'), 200);
    expect(find.text('${change > 0 ? '+' : ''}$change kcal'), findsOneWidget);
    // The cap is explained whether or not it held the change back.
    final cap = find.textContaining(RegExp('check-in limit|A check-in moves'));
    await tester.scrollUntilVisible(cap, 200);
    expect(cap, findsOneWidget);
  });

  testWidgets("without Home's target, the first check-in shows no change", (
    tester,
  ) async {
    final service = AdaptiveService(
      _User(),
      _Weights(),
      _TrackedDays(),
      _MemoryStore(),
      () => _today.add(const Duration(hours: 9)),
    );
    await _pumpLarge(tester, service);

    expect(find.text('Current target'), findsNothing);
    expect(find.text('Change'), findsNothing);
  });

  testWidgets('a settings change names the setting that changed', (
    tester,
  ) async {
    const weekly = AdaptiveSettings(
      adaptiveTarget: true,
      activityMode: ActivityMode.weekly,
    );
    AdaptiveStore.settings.value = weekly;
    addTearDown(() => AdaptiveStore.settings.value = const AdaptiveSettings());
    final service = AdaptiveService(
      _User(),
      _Weights(),
      _TrackedDays(),
      _MemoryStore(),
      () => _today.add(const Duration(hours: 9)),
    );
    await service.accept(await service.checkIn(), 2000);
    AdaptiveStore.settings.value = weekly.copyWith(countSteps: false);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveCheckInCard(service: service, onAccepted: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your target settings changed'), findsOneWidget);
    expect(find.textContaining('You changed steps.'), findsOneWidget);
  });

  testWidgets('a row at 200% text wraps its value below the label', (
    tester,
  ) async {
    final service = AdaptiveService(
      _User(),
      _Weights(),
      _TrackedDays(),
      _MemoryStore(),
      () => _today.add(const Duration(hours: 9)),
    );
    await _pumpLarge(tester, service);

    final label = find.text('Target weight, chosen pace');
    await tester.scrollUntilVisible(label, 200);
    // Squeezed beside its value it took a letter a line.
    expect(tester.getSize(label).height, lessThan(150));
    expect(find.textContaining('Your first target'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the planner moves the date with the pace and saves it', (
    tester,
  ) async {
    final saved = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GoalPlanCard(
              palette: AppPalette.light,
              unit: BodyWeightUnit.kg,
              service: service,
              onUsePace: (pace) async => saved.add(pace),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Goal planner'), findsOneWidget);
    expect(find.text('Pace: -0.50 kg a week'), findsOneWidget);
    expect(find.text('Use this pace'), findsNothing);
    expect(find.text('Last 7 days'), findsOneWidget);
    final reached = find.byWidgetPredicate(
      (w) => w is Text && (w.data ?? '').contains('weeks)'),
    );
    final before = (tester.widget(reached.first) as Text).data;

    await tester.drag(
      find.byKey(const ValueKey('plan-pace')),
      const Offset(-60, 0),
    );
    await tester.pumpAndSettle();
    expect((tester.widget(reached.first) as Text).data, isNot(before));

    await tester.ensureVisible(find.text('Use this pace'));
    await tester.tap(find.text('Use this pace'));
    await tester.pumpAndSettle();
    expect(saved.single, isNot(closeTo(-0.5, 0.01)));
  });

  testWidgets('the planner reloads when a pace is saved elsewhere', (
    tester,
  ) async {
    final paced = _PacedService(service);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GoalPlanCard(
              palette: AppPalette.light,
              unit: BodyWeightUnit.kg,
              service: paced,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pace: -0.50 kg a week'), findsOneWidget);

    // A diet phase beginning saves its pace through savePace.
    paced.pace = -0.25;
    paceChanges.value++;
    await tester.pumpAndSettle();
    expect(find.text('Pace: -0.25 kg a week'), findsOneWidget);
  });

  testWidgets('without a target the planner offers to set one', (tester) async {
    final paced = _PacedService(service)..noTarget = true;
    var asked = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GoalPlanCard(
              palette: AppPalette.light,
              unit: BodyWeightUnit.kg,
              service: paced,
              onSetTarget: (_, _, _) async {
                asked++;
                paced.noTarget = false;
                return true;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('No target weight'), findsOneWidget);
    expect(find.text('Reached'), findsNothing);
    expect(find.text('Target'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('plan-set-target')));
    await tester.pumpAndSettle();
    expect(asked, 1);
    expect(find.text('Reached'), findsOneWidget);
    expect(find.textContaining('No target weight'), findsNothing);
  });

  test('a measured body fat % changes the expenditure read', () async {
    final measurements = MeasurementStore(
      () => Hive.openBox<dynamic>('measurements'),
    );
    await measurements.addDay(_today, {BodyMetric.bodyFat: 10});
    final lean = AdaptiveService(
      _User(),
      _Weights(),
      _TrackedDays(),
      store,
      () => _today.add(const Duration(hours: 9)),
      measurements,
    );

    // Leaner: more of a loss is lean tissue, worth less energy, so the
    // same loss on the same intake reads as a lower expenditure.
    expect(
      (await lean.checkIn()).expenditureKcal,
      lessThan((await service.checkIn()).expenditureKcal),
    );
  });

  group('expenditure history', () {
    test(
      'every day from the first weigh-in, settled after two weeks',
      () async {
        final days = await service.expenditureHistory();

        expect(days.length, 60);
        expect(days.last.date, _today);
        expect(days.first.settled, isFalse);
        expect(days.last.settled, isTrue);
        expect(days.last.intakeKcal, 2000);
        // Losing 0.5 kg a week on 2,000 kcal: expenditure is well above it.
        expect(days.last.expenditureKcal, greaterThan(2300));
      },
    );

    test('nothing without a weigh-in', () async {
      final none = AdaptiveService(
        _User(),
        _NoWeights(),
        _TrackedDays(),
        store,
        () => _today,
      );
      expect(await none.expenditureHistory(), isEmpty);
    });

    testWidgets('the Trends card shows expenditure and a deficit', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExpenditureTrendCard(
              rangeDays: 30,
              palette: AppPalette.light,
              service: service,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Expenditure'), findsOneWidget);
      expect(find.text('Balance, logged days'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^-\d+ kcal a day$')), findsOneWidget);
      expect(find.textContaining('Energy you burn a day'), findsOneWidget);
      expect(find.textContaining('Solid: estimated'), findsOneWidget);
      expect(find.textContaining('Dots: logged'), findsOneWidget);
    });

    testWidgets('a single day names no lines, as none are drawn', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExpenditureTrendCard(
              rangeDays: 30,
              palette: AppPalette.light,
              service: AdaptiveService(
                _User(),
                _OneWeighIn(),
                _NoLogs(),
                _MemoryStore(),
                () => _today.add(const Duration(hours: 9)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Expenditure'), findsOneWidget);
      expect(find.textContaining('Solid'), findsNothing);
      expect(find.textContaining('Dashed'), findsNothing);
      expect(
        find.text(
          'Estimated expenditure is still the formula until two weeks of '
          'weigh-ins and logging.',
        ),
        findsOneWidget,
      );
    });
  });
}

class _Config extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      ConfigEntity(true, true, false, AppThemeEntity.system);
}

class _Goal extends Fake implements GetKcalGoalUsecase {
  @override
  Future<double> getKcalGoal({
    UserEntity? userEntity,
    double? totalKcalActivitiesParam,
    double? kcalUserAdjustment,
  }) async => totalKcalActivitiesParam == 0 ? 2847 : 3096;
}

/// Hive's file I/O does not finish in a widget test's fake time.
class _MemoryStore extends AdaptiveStore {
  final records = <CheckInRecord>[];

  @override
  Future<List<CheckInRecord>> history() async => records;

  @override
  Future<void> addCheckIn(CheckInRecord record) async => records.add(record);

  @override
  Future<void> replaceLastCheckIn(CheckInRecord record) async =>
      records[records.length - 1] = record;
}

/// [inner]'s plan at a pace set by the test.
class _PacedService extends Fake implements AdaptiveService {
  final AdaptiveService inner;
  double pace = -0.5;
  bool noTarget = false;

  _PacedService(this.inner);

  @override
  Future<GoalPlanInputs?> goalPlan({int pastDays = 60}) async {
    final plan = (await inner.goalPlan(pastDays: pastDays))!;
    return GoalPlanInputs(
      pastTrendKg: plan.pastTrendKg,
      trendKgPerDay: plan.trendKgPerDay,
      expenditureKcal: plan.expenditureKcal,
      bodyFatPercent: plan.bodyFatPercent,
      targetWeightKg: noTarget ? null : plan.targetWeightKg,
      paceKgPerWeek: pace,
    );
  }
}
