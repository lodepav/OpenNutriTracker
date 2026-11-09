// Fork cases moved out of test/features/diary/presentation/widgets/diary_table_calendar_test.dart (they test the fork's changes).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/features/diary/presentation/widgets/diary_table_calendar.dart';
import 'package:opennutritracker/fork/display/day_ring.dart';
import 'package:opennutritracker/generated/l10n.dart';

Widget _app({
  required double textScale,
  Map<String, TrackedDayEntity> trackedDaysMap = const {},
  Set<String> daysWithEntries = const {},
}) => MediaQuery(
  data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
  child: MaterialApp(
    localizationsDelegates: const [
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: S.supportedLocales,
    home: Scaffold(
      body: DiaryTableCalendar(
        onDateSelected: (_, _) {},
        calendarDurationDays: const Duration(days: 365),
        focusedDate: DateTime(2026, 8, 24),
        currentDate: DateTime(2026, 8, 24),
        selectedDate: DateTime(2026, 8, 24),
        trackedDaysMap: trackedDaysMap,
        daysWithEntries: daysWithEntries,
      ),
    ),
  ),
);

void main() {
  // the strip's arrows say they move a week, and
  // a day is a 48 dp target
  testWidgets('the week strip says week and its days are 48 high', (
    tester,
  ) async {
    await tester.pumpWidget(_app(textScale: 1));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Previous week'), findsOneWidget);
    expect(find.bySemanticsLabel('Next week'), findsOneWidget);
    expect(find.bySemanticsLabel('Previous month'), findsNothing);
    // The day's cell: what takes the tap.
    final cell = find
        .ancestor(
          of: find.text('25'),
          matching: find.byType(RawGestureDetector),
        )
        .first;
    expect(tester.getSize(cell).height, greaterThanOrEqualTo(48));
  });

  // A day-boundary move keeps the row of a day it left with no entries, for
  // its goals (#1440): the ring follows what is logged, not the row.
  testWidgets('a day ring shows a row only on a day with entries', (
    tester,
  ) async {
    TrackedDayEntity row(int date, double tracked) => TrackedDayEntity(
      day: DateTime(2026, 8, date),
      calorieGoal: 2000,
      caloriesTracked: tracked,
      carbsTracked: tracked / 10,
      fatTracked: 0,
      proteinTracked: 0,
    );
    await tester.pumpWidget(
      _app(
        textScale: 1,
        trackedDaysMap: {
          '2026-08-25': row(25, 1800),
          '2026-08-26': row(26, 0),
          '2026-08-27': row(27, 0),
        },
        // the 27th: only zero-calorie entries, still logged
        daysWithEntries: {'2026-08-25', '2026-08-27'},
      ),
    );
    await tester.pumpAndSettle();
    TrackedDayEntity? ringOf(int date) => tester
        .widgetList<DayRing>(find.byType(DayRing))
        .firstWhere((r) => r.day.month == 8 && r.day.day == date)
        .trackedDay;
    expect(ringOf(25), isNotNull);
    expect(ringOf(26), isNull);
    expect(ringOf(27), isNotNull);
  });
}
