import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_water_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_weight_log_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
import 'package:opennutritracker/features/trends/presentation/trends_page.dart';
import 'package:opennutritracker/fork/report/trends_layout.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

class _FakeGetTrackedDayUsecase extends Fake implements GetTrackedDayUsecase {}

class _FakeGetWeightLogUsecase extends Fake implements GetWeightLogUsecase {}

class FakeGetUserUsecase extends Fake implements GetUserUsecase {}

class _FakeGetConfigUsecase extends Fake implements GetConfigUsecase {}

class _FakeGetWaterIntakeUsecase extends Fake
    implements GetWaterIntakeUsecase {}

/// A TrendsBloc pinned to one loaded state: the page's events are kept in
/// [events] and not run, so the test controls exactly what is drawn.
class SeededTrendsBloc extends TrendsBloc {
  final events = <TrendsEvent>[];

  SeededTrendsBloc(TrendsLoaded seeded)
    : super(
        _FakeGetTrackedDayUsecase(),
        _FakeGetWeightLogUsecase(),
        FakeGetUserUsecase(),
        _FakeGetConfigUsecase(),
        _FakeGetWaterIntakeUsecase(),
      ) {
    emit(seeded);
  }

  void show(TrendsLoaded state) => emit(state);

  @override
  void add(TrendsEvent event) => events.add(event);
}

DateTime day(int offset) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + offset);
}

TrendsLoaded loaded({
  int rangeDays = 7,
  int? windowDays,
  List<TrackedDayEntity> days = const [],
  List<WeightLogEntity> weight = const [],
  BodyWeightUnit unit = BodyWeightUnit.kg,
  double? targetWeightKg,
  Map<DateTime, int> waterByDay = const {},
  int waterGoalMl = 0,
}) => TrendsLoaded(
  rangeDays: rangeDays,
  windowDays: windowDays ?? rangeDays,
  days: days,
  priorWeek: const [],
  weight: weight,
  bodyWeightUnit: unit,
  targetWeightKg: targetWeightKg,
  waterByDay: waterByDay,
  waterGoalMl: waterGoalMl,
);

/// Trends on [state], the bloc in the locator as the page reads it.
Future<SeededTrendsBloc> pumpTrends(
  WidgetTester tester,
  TrendsLoaded state, {
  bool kj = false,
}) async {
  final bloc = SeededTrendsBloc(state);
  locator.registerSingleton<TrendsBloc>(bloc);
  // The cards below the grid read the locator; the grid is the test's.
  TrendsLayoutStore.current.value = (
    order: const [],
    hidden: trendCards.keys.toSet(),
  );
  addTearDown(
    () => TrendsLayoutStore.current.value = (order: const [], hidden: const {}),
  );
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => EnergyUnitProvider(usesKilojoules: kj),
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
  // The page's own first load is not the test's.
  bloc.events.clear();
  return bloc;
}

/// Taps [metric]'s tile and waits for its page.
Future<void> openTile(WidgetTester tester, String metric) async {
  final tile = find.byKey(ValueKey('trends-tile-$metric'));
  await tester.scrollUntilVisible(
    tile,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

/// The text of [tile] (its value and what follows), joined.
String tileText(WidgetTester tester, String metric) {
  final texts = tester.widgetList<RichText>(
    find.descendant(
      of: find.byKey(ValueKey('trends-tile-$metric')),
      matching: find.byType(RichText),
    ),
  );
  return texts.map((t) => t.text.toPlainText()).join(' | ');
}
