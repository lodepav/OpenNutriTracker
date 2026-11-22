import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_weight_log_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_ui.dart';
import 'package:opennutritracker/fork/adaptive/auto_check_in.dart';
import 'package:opennutritracker/fork/adaptive/check_in.dart';
import 'package:opennutritracker/fork/adaptive/goal_plan.dart';
import 'package:opennutritracker/fork/goal/goal_planner.dart';
import 'package:opennutritracker/fork/goal/goal_progress.dart';
import 'package:opennutritracker/fork/goal/planner_screen.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

final _today = DateTime(2026, 10, 22);

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

/// 60 days of losing 0.5 kg a week, weighed every other day.
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

class _MemoryStore extends AdaptiveStore {
  final records = <CheckInRecord>[];

  @override
  Future<List<CheckInRecord>> history() async => records;

  @override
  Future<void> addCheckIn(CheckInRecord record) async => records.add(record);

  @override
  Future<void> restoreCheckIns(List<CheckInRecord> records) async =>
      this.records
        ..clear()
        ..addAll(records);

  final keys = <String, Object?>{};

  @override
  Future<Object?> readKey(String key) async => keys[key];

  @override
  Future<void> writeKey(String key, Object? value) async => keys[key] = value;
}

/// Home's goal: the formula's 2738 before the first check-in, with 250 of
/// logged activity added, as the critique's.
class _Goal extends Fake implements GetKcalGoalUsecase {
  @override
  Future<double> getKcalGoal({
    UserEntity? userEntity,
    double? totalKcalActivitiesParam,
    double? kcalUserAdjustment,
  }) async => totalKcalActivitiesParam == 0 ? 2738 : 2988;
}

/// Saves to the settings in use; [checkIn] is the last one accepted.
class _PlannerStore extends Fake implements AdaptiveStore {
  final CheckInRecord? checkIn;

  _PlannerStore([this.checkIn]);

  @override
  Future<void> save(AdaptiveSettings value) async =>
      AdaptiveStore.settings.value = value;

  @override
  Future<CheckInRecord?> lastCheckIn() async => checkIn;
}

AdaptiveService _service(_MemoryStore store) => AdaptiveService(
  _User(),
  _Weights(),
  _TrackedDays(),
  store,
  () => _today.add(const Duration(hours: 9)),
);

/// The check-in pushed over a page, so it pops back to one.
Future<void> _open(WidgetTester tester, AdaptiveService service) async {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<bool>(
                builder: (_) => CheckInScreen(service: service),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => AdaptiveStore.settings.value = const AdaptiveSettings());

  group('checkInDoneText', () {
    test("names today's new goal, the one before, and the activity", () {
      expect(
        checkInDoneText(
          before: 2988,
          after: 2738,
          activityDropped: true,
          unit: 'kcal',
        ),
        "Today's goal is now 2738 kcal, from 2988 "
        '(activity no longer added)',
      );
      expect(
        checkInDoneText(
          before: 2988,
          after: 2988,
          activityDropped: false,
          unit: 'kcal',
        ),
        "Today's goal stays 2988 kcal",
      );
    });
  });

  group("Keep changing today's goal", () {
    setUp(() {
      locator.registerSingleton<GetKcalGoalUsecase>(_Goal());
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
      );
    });
    tearDown(() => locator.unregister<GetKcalGoalUsecase>());

    testWidgets('says so under the button, then in a bar with Undo', (
      tester,
    ) async {
      final store = _MemoryStore();
      await _open(tester, _service(store));

      expect(find.text('Keep 2738 kcal'), findsOneWidget);
      expect(find.text("Keep: today's goal 2988 → 2738 kcal"), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('check-in-keep')));
      await tester.pumpAndSettle();
      expect(find.byType(CheckInScreen), findsNothing);
      expect(store.records.single.acceptedKcal, 2738);
      expect(
        find.text(
          "Today's goal is now 2738 kcal, from 2988 "
          '(activity no longer added)',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(store.records, isEmpty);
    });

    testWidgets('Accept names the goal too, and Undo puts back the '
        'check-in before', (tester) async {
      final store = _MemoryStore();
      final service = _service(store);
      final first = await tester.runAsync(service.checkIn);
      await tester.runAsync(() => service.accept(first!, 2600));
      await _open(tester, service);

      await tester.enterText(
        find.byKey(const ValueKey('check-in-target')),
        '2500',
      );
      await tester.tap(find.byKey(const ValueKey('check-in-accept')));
      await tester.pumpAndSettle();
      expect(store.records, hasLength(2));
      expect(find.textContaining("Today's goal is now "), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(store.records.single.acceptedKcal, 2600);
    });
  });

  testWidgets('with automatic check-ins, Home asks after an Undo rather than '
      'accepting the same check-in again', (tester) async {
    AdaptiveStore.settings.value = const AdaptiveSettings(
      adaptiveTarget: true,
      autoAcceptCheckIn: true,
    );
    addTearDown(() {
      AutoCheckIn.accepted.value = null;
      AutoCheckIn.waiting.value = null;
    });
    final store = _MemoryStore();
    final service = _service(store);
    // What Undo of a first check-in leaves.
    await tester.runAsync(() => service.restoreCheckIns(const []));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveCheckInCard(service: service, onAccepted: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(store.records, isEmpty);
    expect(find.text('Your first target'), findsOneWidget);
    expect(find.text('Your first target is set'), findsNothing);
  });

  testWidgets('without a goal on an Adaptive target, Keep says nothing more '
      'under it', (tester) async {
    locator.registerSingleton<GetKcalGoalUsecase>(_Goal());
    addTearDown(locator.unregister<GetKcalGoalUsecase>);
    // On the formula a check-in does not move Home's goal.
    await _open(tester, _service(_MemoryStore()));
    expect(find.text('Keep 2738 kcal'), findsOneWidget);
    expect(find.byKey(const ValueKey('check-in-keep-moves')), findsNothing);
  });

  testWidgets('the arrival rows start where the other rows do', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final plan = GoalDraft(
      kind: PhaseKind.cut,
      startKg: 87.1,
      targetKg: 82,
      start: _today,
      paceKg: 0.5,
    ).toPlan();
    final progress = GoalProgress(
      start: GoalStart(
        date: _today,
        kg: 87.1,
        targetKg: 82,
        paceKgPerWeek: -0.5,
      ),
      nowKg: 87.1,
      paceKgPerWeek: -0.5,
      trend: const [87.1],
      today: _today,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CheckInScreen(
          service: _service(_MemoryStore()),
          loadArrivals: () async => goalArrivals(progress, plan),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final arrival = find.text('By your plan');
    expect(arrival, findsOneWidget);
    expect(
      tester.getTopLeft(arrival).dx,
      tester.getTopLeft(find.text('Weigh-ins')).dx,
    );
  });

  test('a check-in says what a target typed in place of its own does', () {
    const checkIn = CheckIn(
      averageIntakeKcal: 2000,
      loggedDays: 7,
      weighIns: 4,
      trendKg: 85,
      weekChangeKg: -0.5,
      expenditureKcal: 3000,
      baseKcal: 3000,
      uncappedTargetKcal: 2500,
      proposedTargetKcal: 2500,
      daysToTargetAtGoal: 70,
      daysToTargetAtTrend: 70,
      goalRateKgPerWeek: -0.5,
      targetWeightKg: 80,
      kcalPerKg: 7000,
      recommendedFloorKcal: 1500,
    );
    expect(checkIn.paceAt(2500), -0.5);
    // 500 kcal less a day is 0.5 kg more a week at 7000 a kg.
    expect(checkIn.paceAt(2000), closeTo(-1.0, 1e-9));
    expect(checkIn.daysToTargetAt(2500), daysToTarget(85, 80, -0.5 / 7));
    expect(checkIn.daysToTargetAt(2000), daysToTarget(85, 80, -1.0 / 7));
    // A target that gains leads away from a target below.
    expect(checkIn.daysToTargetAt(3600), isNull);
    expect(checkIn.belowFloor(1499), isTrue);
    expect(checkIn.belowFloor(1500), isFalse);
  });

  group('a daily target typed in', () {
    setUp(() {
      locator.registerSingleton<GetKcalGoalUsecase>(_Goal());
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
      );
    });
    tearDown(() => locator.unregister<GetKcalGoalUsecase>());

    Future<CheckIn> openWithArrivals(WidgetTester tester) async {
      final service = _service(_MemoryStore());
      final checkIn = (await tester.runAsync(service.checkIn))!;
      final plan = GoalDraft(
        kind: PhaseKind.cut,
        startKg: checkIn.trendKg!,
        targetKg: 80,
        start: _today,
        paceKg: 0.5,
      ).toPlan();
      final progress = GoalProgress(
        start: GoalStart(
          date: _today,
          kg: checkIn.trendKg!,
          targetKg: 80,
          paceKgPerWeek: -0.5,
        ),
        nowKg: checkIn.trendKg!,
        paceKgPerWeek: -0.5,
        trend: [checkIn.trendKg!],
        today: _today,
      );
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: CheckInScreen(
            service: service,
            loadArrivals: () async => goalArrivals(progress, plan),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return checkIn;
    }

    testWidgets('moves the change and the arrival with it as it is typed', (
      tester,
    ) async {
      final checkIn = await openWithArrivals(tester);
      expect(find.text('By your plan'), findsOneWidget);
      expect(find.text('At this target'), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('check-in-target')),
        '2000',
      );
      await tester.pump();
      // Today's goal 2988 less the 250 of activity a check-in leaves out.
      expect(
        find.text('\u2212988 kcal (activity no longer added)'),
        findsOneWidget,
      );
      expect(find.text('By your plan'), findsNothing);
      expect(find.text('At this target'), findsOneWidget);
      final days = checkIn.daysToTargetAt(2000)!;
      final weeks = (days / 7).round();
      expect(find.textContaining('about $weeks weeks'), findsOneWidget);
      expect(
        find.textContaining(
          'That is the expenditure less '
          '${checkIn.expenditureKcal.round() - 2000} kcal for ',
        ),
        findsOneWidget,
      );

      // Back to the proposal: the plan's rows again.
      await tester.enterText(
        find.byKey(const ValueKey('check-in-target')),
        '${checkIn.proposedTargetKcal.round()}',
      );
      await tester.pump();
      expect(find.text('By your plan'), findsOneWidget);
    });

    testWidgets('warns under the field of a target on the low side', (
      tester,
    ) async {
      await _open(tester, _service(_MemoryStore()));
      expect(find.text('This daily target is on the low side'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('check-in-target')),
        '250',
      );
      await tester.pump();
      expect(find.text('This daily target is on the low side'), findsOneWidget);
      final field = tester.getBottomLeft(
        find.byKey(const ValueKey('check-in-target')),
      );
      final warning = tester.getTopLeft(
        find.text('This daily target is on the low side'),
      );
      expect(warning.dy, greaterThan(field.dy));
      expect(
        warning.dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('check-in-accept'))).dy,
        ),
      );
    });
  });

  group("the plan's figure beside the target in use", () {
    final day0 = DateTime(2026, 11, 21);
    Future<void> pump(WidgetTester tester, CheckInRecord? checkIn) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => EnergyUnitProvider(usesKilojoules: false),
          child: MaterialApp(
            localizationsDelegates: const [
              S.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: S.supportedLocales,
            home: GoalPlannerScreen(
              setup: const PlannerSetup(
                nowKg: 87.1,
                unit: BodyWeightUnit.kg,
                expenditureKcal: 3036,
                formulaKcal: 2738,
                bodyFatPercent: 22,
              ),
              draft: GoalDraft.fresh(87.1, day0, targetKg: 82),
              today: day0,
              store: _PlannerStore(checkIn),
              onStart: (_) async => true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      while (find
          .byKey(const ValueKey('goal-planner-step-plan'))
          .evaluate()
          .isEmpty) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
    }

    testWidgets('a target kept at a check-in is named apart', (tester) async {
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
      );
      await pump(
        tester,
        CheckInRecord(
          date: day0,
          expenditureKcal: 3036,
          proposedKcal: 2548,
          acceptedKcal: 2738,
        ),
      );
      expect(
        find.textContaining(
          'Your target now is 2738 kcal, from your last check-in.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('none before a check-in', (tester) async {
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
      );
      await pump(tester, null);
      expect(find.byKey(const ValueKey('goal-plan-target-now')), findsNothing);
    });
  });
}
