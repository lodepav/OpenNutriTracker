import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/fork/display/macro_foods.dart';
import 'package:opennutritracker/fork/trends/macro_contributors.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../fixture/intake_entity_fixtures.dart';

final dates = [for (var d = 20; d <= 26; d++) DateTime(2026, 10, d)];

Future<List<(DateTime, DateTime)>> pump(
  WidgetTester tester,
  List<IntakeEntity> Function(DateTime first, DateTime last) intakes,
) async {
  final asked = <(DateTime, DateTime)>[];
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
        home: Scaffold(
          body: ListView(
            children: [
              MacroDaysAndFoods(
                metric: FoodsMetric.carbs,
                series: [for (var i = 0; i < 7; i++) 200.0 + i],
                dates: dates,
                goal: 250,
                color: Colors.orange,
                chartLabel: 'Carbs chart',
                load: (first, last) async {
                  asked.add((first, last));
                  return intakes(first, last);
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return asked;
}

void main() {
  // Seven foods, the first the most carbs; rice twice.
  final foods = [
    for (final (i, name) in [
      'Rice',
      'Bread',
      'Pasta',
      'Oats',
      'Banana',
      'Apple',
      'Honey',
    ].indexed)
      intakeOf(name, 100, carbs100: 70.0 - i * 10),
    intakeOf('Rice', 100, carbs100: 70),
    intakeOf('Chicken', 100, protein100: 20),
  ];

  testWidgets('the period\'s top five by the macro, then all of them', (
    tester,
  ) async {
    final asked = await pump(tester, (_, _) => foods);
    expect(asked, [(dates.first, dates.last)]);
    expect(find.text('Top foods'), findsOneWidget);
    expect(find.text('Last 7 days'), findsOneWidget);
    final rows = find.byType(FoodShareRow);
    expect(rows, findsNWidgets(topFoodsShown));
    expect(
      [for (final r in tester.widgetList<FoodShareRow>(rows)) r.share.name],
      ['Rice', 'Bread', 'Pasta', 'Oats', 'Banana'],
    );
    // Rice twice: 140 g of 350.
    expect(find.text('140 g'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    expect(find.textContaining('2×'), findsOneWidget);
  });

  testWidgets('see all lists every food of the period', (tester) async {
    await pump(tester, (_, _) => foods);
    // Chicken has no carbs: seven foods in all.
    expect(find.text('See all 7 foods'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('top-foods-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('top-foods-all')));
    await tester.pumpAndSettle();
    expect(find.text('Foods · Last 7 days'), findsOneWidget);
    expect(find.byType(FoodShareRow), findsNWidgets(7));
  });

  testWidgets('a tapped day: its foods, and back to the period', (
    tester,
  ) async {
    final asked = await pump(
      tester,
      (first, last) => first == last ? [foods[5]] : foods,
    );
    tester.widget<DailyBarChart>(find.byType(DailyBarChart)).onTap!(6);
    await tester.pumpAndSettle();
    expect(asked.last, (dates[6], dates[6]));
    expect(
      tester.widget<DailyBarChart>(find.byType(DailyBarChart)).selected,
      6,
    );
    expect(find.text('Mon, Oct 26'), findsOneWidget);
    expect(find.byType(FoodShareRow), findsOneWidget);
    expect(find.text('Apple'), findsOneWidget);
    expect(find.text('See all 1 foods'), findsNothing);

    await tester.tap(find.text('All days'));
    await tester.pumpAndSettle();
    expect(find.text('Last 7 days'), findsOneWidget);
    expect(find.byType(FoodShareRow), findsNWidgets(topFoodsShown));
    // The period's foods were kept, not read again.
    expect(asked, hasLength(2));
  });

  testWidgets('nothing to read: no foods, no spinner', (tester) async {
    await pump(tester, (_, _) => throw StateError('no locator'));
    expect(
      find.text('No foods logged with carbs in this range.'),
      findsOneWidget,
    );
  });
}
