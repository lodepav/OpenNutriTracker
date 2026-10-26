// Fork cases moved out of test/features/diary/presentation/widgets/diary_table_calendar_test.dart (they test the fork's changes).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/diary/presentation/widgets/diary_table_calendar.dart';
import 'package:opennutritracker/generated/l10n.dart';

Widget _app({required double textScale}) => MediaQuery(
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
        trackedDaysMap: const {},
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
}
