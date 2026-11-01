import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/diary/presentation/widgets/daily_nutrient_panel.dart';
import 'package:opennutritracker/generated/l10n.dart';

void main() {
  testWidgets('the Diary panel gives salt in g, as Trends does', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(child: DailyNutrientPanel(intakes: [])),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(find.text('Salt'), findsOneWidget);
    expect(find.textContaining('0.0 / 5.8g'), findsOneWidget);
    expect(find.text('Sodium'), findsNothing);
  });
}
