import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/fork/trends/calories_detail.dart';

// The Calories page's card of energy by weekday, over three months.

final _today = DateTime(2026, 10, 26);

class _TrackedDays extends Fake implements GetTrackedDayUsecase {
  final List<TrackedDayEntity> days;
  DateTime? start;

  _TrackedDays(this.days);

  @override
  Future<List<TrackedDayEntity>> getTrackedDaysByRange(
    DateTime start,
    DateTime end,
  ) async {
    this.start = start;
    return days;
  }
}

TrackedDayEntity _tracked(int offset, double kcal) => TrackedDayEntity(
  day: DateTime(_today.year, _today.month, _today.day + offset, 9),
  calorieGoal: 2000,
  caloriesTracked: kcal,
);

Future<void> _pump(WidgetTester tester, {double scale = 1}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(child: WeekdayCard(now: () => _today)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final getIt = GetIt.instance;
  tearDown(getIt.reset);

  testWidgets('the weekday that runs over is named', (tester) async {
    // Oct 26 2026 is a Monday, so offset -2 is a Saturday.
    final usecase = _TrackedDays([
      for (var w = 0; w < 4; w++)
        for (var i = 0; i < 7; i++) _tracked(-w * 7 - i, i == 2 ? 2700 : 2000),
    ]);
    getIt.registerSingleton<GetTrackedDayUsecase>(usecase);
    await _pump(tester);

    expect(usecase.start, DateTime(2026, 7, 29));
    expect(find.text('By weekday, last 3 months'), findsOneWidget);
    expect(
      find.text('Saturdays run 600 kcal over your average.'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Saturday, 2700 kcal'), findsOneWidget);
  });

  testWidgets('even weekdays say so', (tester) async {
    getIt.registerSingleton<GetTrackedDayUsecase>(
      _TrackedDays([_tracked(0, 2000), _tracked(-1, 2050)]),
    );
    await _pump(tester);
    expect(find.text('No weekday runs far from your average.'), findsOneWidget);
    expect(find.bySemanticsLabel('Sunday, 2050 kcal'), findsOneWidget);
    expect(find.bySemanticsLabel('Friday, nothing logged'), findsOneWidget);
  });

  testWidgets('a large font grows the chart rather than overflowing it', (
    tester,
  ) async {
    getIt.registerSingleton<GetTrackedDayUsecase>(
      _TrackedDays([for (var i = 0; i < 7; i++) _tracked(-i, 2000.0 + i)]),
    );
    await _pump(tester, scale: 2);
    expect(tester.takeException(), isNull);
    expect(find.text('Wed'), findsOneWidget);
  });

  testWidgets('hidden with nothing logged', (tester) async {
    getIt.registerSingleton<GetTrackedDayUsecase>(_TrackedDays(const []));
    await _pump(tester);
    expect(find.text('By weekday, last 3 months'), findsNothing);
  });
}
