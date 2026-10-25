import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_water_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_weight_log_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
import 'package:opennutritracker/features/trends/presentation/trends_page.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

// Seam S87: Daily average's macro goals are the mean over the days that
// have a goal, not their sum over the range's days.

class _FakeGetTrackedDayUsecase extends Fake implements GetTrackedDayUsecase {}

class _FakeGetWeightLogUsecase extends Fake implements GetWeightLogUsecase {}

class _FakeGetUserUsecase extends Fake implements GetUserUsecase {}

class _FakeGetConfigUsecase extends Fake implements GetConfigUsecase {}

class _FakeGetWaterIntakeUsecase extends Fake
    implements GetWaterIntakeUsecase {}

/// A TrendsBloc pinned to one loaded state: the page's LoadTrendsEvent is
/// ignored so the test controls exactly what the chart plots.
class _SeededTrendsBloc extends TrendsBloc {
  _SeededTrendsBloc(TrendsLoaded seeded)
    : super(
        _FakeGetTrackedDayUsecase(),
        _FakeGetWeightLogUsecase(),
        _FakeGetUserUsecase(),
        _FakeGetConfigUsecase(),
        _FakeGetWaterIntakeUsecase(),
      ) {
    emit(seeded);
  }

  @override
  void add(TrendsEvent event) {}
}

void main() {
  setUp(() {
    final now = DateTime.now();
    locator.registerSingleton<TrendsBloc>(
      _SeededTrendsBloc(
        TrendsLoaded(
          rangeDays: 7,
          windowDays: 7,
          // One day logged of the seven.
          days: [
            TrackedDayEntity(
              day: DateTime(now.year, now.month, now.day),
              calorieGoal: 2000,
              caloriesTracked: 700,
              carbsGoal: 259,
              carbsTracked: 70,
              fatGoal: 48,
              fatTracked: 14,
              proteinGoal: 64,
              proteinTracked: 21,
            ),
          ],
          priorWeek: const [],
          weight: const [],
          bodyWeightUnit: BodyWeightUnit.kg,
          targetWeightKg: null,
          waterByDay: const {},
          waterGoalMl: 0,
        ),
      ),
    );
  });

  tearDown(() async => locator.reset());

  testWidgets('a week with one day logged: the goals as that day had them', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => EnergyUnitProvider(usesKilojoules: false),
        child: const MaterialApp(
          localizationsDelegates: [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: S.supportedLocales,
          home: Scaffold(body: TrendsPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('10 / 259 g'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    // The intake is over the range, as upstream has it.
    expect(find.text('10 / 259 g'), findsOneWidget);
    expect(find.text('2 / 48 g'), findsOneWidget);
    expect(find.text('3 / 64 g'), findsOneWidget);
  });
}
