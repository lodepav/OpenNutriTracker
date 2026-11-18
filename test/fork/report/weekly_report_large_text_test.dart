import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/fork/report/weekly_report.dart';

import '../../helpers/ux_checks.dart';

// The Trends recritique: at 200% on a 360 dp phone the week's date read
// "Nov …" beside its badge, and the figures shrank to fit.

TrackedDayEntity _day(int day, double kcal) => TrackedDayEntity(
  day: DateTime(2026, 11, day, 8),
  calorieGoal: 2000,
  caloriesTracked: kcal,
  proteinGoal: 140,
  proteinTracked: 150,
  carbsGoal: 200,
  carbsTracked: 180,
  fatGoal: 70,
  fatTracked: 60,
);

Future<void> _pump(WidgetTester tester, {double textScale = 2}) async {
  await pumpOnPhone(
    tester,
    SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: WeeklyReportCard(
        days: [_day(16, 1900), _day(17, 2300)],
        rangeDays: 7,
        palette: AppPalette.light,
        // Wednesday 18 November 2026.
        clock: () => DateTime(2026, 11, 18, 18),
      ),
    ),
    textScale: textScale,
  );
  tester.view
    ..physicalSize = const Size(360, 800)
    ..devicePixelRatio = 1;
  await tester.pump();
}

void main() {
  testWidgets('at 200% the week stacks and nothing shrinks or cuts', (
    tester,
  ) async {
    await _pump(tester);
    expect(tester.takeException(), isNull);
    expect(cutText(tester), isEmpty);

    final dates = find.text('Nov 16 – Nov 22');
    final badge = find.text('This week so far');
    expect(
      tester.getTopLeft(badge).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(dates).dy),
    );

    // The figure at its full size: no FittedBox scales it down.
    final figure = find.textContaining('2100 / 2000');
    expect(
      tester.getRect(figure).width,
      closeTo(tester.renderObject<RenderBox>(figure).size.width, 0.5),
    );
    expect(
      tester.getTopLeft(find.textContaining('+100')).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(figure).dy),
    );

    // The macros one under another.
    expect(
      tester.getTopLeft(find.text('Fat')).dy,
      greaterThan(tester.getBottomLeft(find.text('Carbs')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Protein')).dy,
      greaterThan(tester.getBottomLeft(find.text('Fat')).dy),
    );
  });

  testWidgets('at 100% the week keeps its rows', (tester) async {
    await _pump(tester, textScale: 1);
    expect(
      (tester.getCenter(find.text('This week so far')).dy -
              tester.getCenter(find.text('Nov 16 – Nov 22')).dy)
          .abs(),
      lessThan(8),
    );
    expect(
      tester.getTopLeft(find.text('Fat')).dy,
      tester.getTopLeft(find.text('Carbs')).dy,
    );
  });
}
