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
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_weight_log_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/goal/completed_goals_page.dart';
import 'package:opennutritracker/fork/goal/goal_actions.dart';
import 'package:opennutritracker/fork/goal/goal_planner.dart';
import 'package:opennutritracker/fork/goal/goal_reached.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

final _today = DateTime(2026, 10, 22);
final _start = DateTime(2026, 10, 5);

/// The profile after the cut is completed: maintaining, no target weight.
class _User extends Fake implements GetUserUsecase {
  @override
  Future<UserEntity> getUserData() async => UserEntity(
    birthday: DateTime(1990, 1, 1),
    heightCM: 180,
    weightKG: 85,
    gender: UserGenderEntity.male,
    goal: UserWeightGoalEntity.maintainWeight,
    pal: UserPALEntity.active,
    weeklyWeightGoalKg: 0,
    targetWeightKg: null,
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

/// 2500 kcal a day; yesterday [yesterdayKcal].
class _TrackedDays extends Fake implements GetTrackedDayUsecase {
  final double yesterdayKcal;

  _TrackedDays([this.yesterdayKcal = 2500]);

  @override
  Future<List<TrackedDayEntity>> getTrackedDaysByRange(
    DateTime start,
    DateTime end,
  ) async => [
    for (var d = 0; d < 60; d++)
      TrackedDayEntity(
        day: _today.subtract(Duration(days: d)),
        calorieGoal: 2500,
        caloriesTracked: d == 1 ? yesterdayKcal : 2500,
      ),
  ];
}

class _MemoryStore extends AdaptiveStore {
  final records = <CheckInRecord>[];

  _MemoryStore(CheckInRecord last) {
    records.add(last);
  }

  @override
  Future<List<CheckInRecord>> history() async => records;

  @override
  Future<void> addCheckIn(CheckInRecord record) async => records.add(record);
}

/// The cut's last check-in, three days ago.
CheckInRecord _cutCheckIn() => CheckInRecord(
  date: _today.subtract(const Duration(days: 3)),
  expenditureKcal: 2900,
  proposedKcal: 2350,
  acceptedKcal: 2350,
  activityKcal: 0,
  baseKcal: 2900,
  goalRateKgPerWeek: -0.5,
  targetWeightKg: 80,
  basis: const AdaptiveSettings().targetBasis,
);

PhasePlan _cut() => GoalDraft(
  kind: PhaseKind.cut,
  startKg: 86.4,
  targetKg: 80,
  start: _start,
  paceKg: 0.5,
  breaks: false,
).toPlan();

class _MemoryPhases extends PhaseStore {
  PhasePlan? saved;
  final goals = <GoalRecord>[];

  _MemoryPhases([this.saved]);

  @override
  Future<PhasePlan?> plan() async => saved;

  @override
  Future<void> save(PhasePlan? plan) async => saved = plan;

  @override
  Future<List<GoalRecord>> history() async => goals;

  @override
  Future<void> addToHistory(List<GoalRecord> records) async =>
      goals.addAll(records);

  @override
  Future<List<PhasePlan>> upcoming() async => const [];

  @override
  Future<void> saveUpcoming(List<PhasePlan> plans) async {}
}

Future<void> _pump(WidgetTester tester, Widget home) async {
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
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => AdaptiveStore.settings.value = const AdaptiveSettings());

  group('applyGoalTarget', () {
    AdaptiveService service(_MemoryStore store, [double yesterday = 2500]) =>
        AdaptiveService(
          _User(),
          _Weights(),
          _TrackedDays(yesterday),
          store,
          () => _today.add(const Duration(hours: 9)),
        );

    test(
      'with the adaptive target on, maintenance is accepted at once',
      () async {
        AdaptiveStore.settings.value = const AdaptiveSettings(
          adaptiveTarget: true,
        );
        final store = _MemoryStore(_cutCheckIn());
        final adaptive = service(store);
        final proposed = (await adaptive.checkIn()).proposedTargetKcal;

        expect(await applyGoalTarget(adaptive), isTrue);

        expect(store.records, hasLength(2));
        expect(store.records.last.goalRateKgPerWeek, 0);
        expect(store.records.last.acceptedKcal, proposed);
        expect(await adaptive.goalChanged(), isFalse);
      },
    );

    test('a day that looks partly logged leaves it to the check-in', () async {
      AdaptiveStore.settings.value = const AdaptiveSettings(
        adaptiveTarget: true,
      );
      final store = _MemoryStore(_cutCheckIn());
      final adaptive = service(store, 600);
      expect(await adaptive.partialDays(), isNotEmpty);

      expect(await applyGoalTarget(adaptive), isFalse);
      expect(store.records, hasLength(1));
    });

    test('with the adaptive target off there is nothing to accept', () async {
      final store = _MemoryStore(_cutCheckIn());
      expect(await applyGoalTarget(service(store)), isTrue);
      expect(store.records, hasLength(1));
    });
  });

  group('Mark completed and maintain', () {
    Future<void> complete(
      WidgetTester tester,
      Future<bool> Function() applyTarget, {
      void Function()? onPage,
    }) async {
      final today = DateTime(2027, 1, 4);
      final page = GoalReachedPage(
        plan: _cut(),
        nowKg: 79.9,
        unit: BodyWeightUnit.kg,
        today: today,
        load: (_) async => GoalRun(trend: const [], first: _start),
        upcoming: () async => const [],
        actions: GoalActions(
          store: _MemoryPhases(_cut()),
          save: (_, _) async => true,
          clock: () => today,
        ),
        applyTarget: applyTarget,
      );
      await _pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute<bool>(builder: (_) => page)),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      onPage?.call();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }

    testWidgets('puts the target in force as it completes', (tester) async {
      var applied = 0;
      await complete(tester, () async {
        applied++;
        return true;
      });
      expect(applied, 1);
      expect(
        find.text('Cut to 80.0 kg completed. Maintaining now.'),
        findsOneWidget,
      );
    });

    testWidgets('says the check-in sets it when it could not', (tester) async {
      await complete(tester, () async => false);
      expect(
        find.text(
          'Cut to 80.0 kg completed. Your check-in on Home sets the '
          'maintenance target.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Maintaining now'), findsNothing);
    });

    testWidgets('with a fixed target, says it stays', (tester) async {
      AdaptiveStore.settings.value = const AdaptiveSettings(
        fixedTarget: true,
        fixedKcal: 2200,
      );
      await complete(
        tester,
        applyGoalTarget,
        onPage: () {
          expect(
            find.text(
              'Your fixed target stays at 2200 kcal. Change it in Settings.',
            ),
            findsOneWidget,
          );
          expect(find.text('Eat at what you burn from today.'), findsNothing);
        },
      );
      expect(
        find.text(
          'Cut to 80.0 kg completed. Your fixed target stays at 2200 kcal.',
        ),
        findsOneWidget,
      );
    });
  });

  group('time in goals', () {
    GoalRecord goal(DateTime start, DateTime end) => GoalRecord(
      kind: PhaseKind.cut,
      start: start,
      end: end,
      startKg: 86,
      endKg: 85,
    );

    test('a goal of a day is a day, not a week', () {
      final t = timeInGoals([goal(_start, DateTime(2026, 10, 6))]);
      expect(t, (label: 'Days in goals', value: '1'));
    });

    test('a short goal beside a long one adds its days, not a week', () {
      final t = timeInGoals([
        goal(DateTime(2026, 1, 5), DateTime(2026, 3, 16)), // 10 weeks
        goal(_start, DateTime(2026, 10, 6)),
      ]);
      expect(t, (label: 'Weeks in goals', value: '10'));
    });

    testWidgets('the tile shows days for a goal of a day', (tester) async {
      await _pump(
        tester,
        CompletedGoalsPage(
          unit: BodyWeightUnit.kg,
          load: () async => (
            history: [goal(_start, DateTime(2026, 10, 6))],
            running: null,
            trend: const <double>[],
            today: DateTime(2026, 10, 7),
          ),
        ),
      );
      expect(find.text('Days in goals'), findsOneWidget);
      expect(find.text('Weeks in goals'), findsNothing);
    });
  });
}
