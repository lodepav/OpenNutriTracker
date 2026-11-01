import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/edit_meal/nutrition_facts.dart';

void main() {
  testWidgets('values a label fills in open the section they are in', (
    tester,
  ) async {
    Widget card({required bool open}) => MaterialApp(
      home: Scaffold(
        body: NutritionFactsCard(
          per: const Text('Per 100 g'),
          rows: const [Text('Energy')],
          more: const [Text('Calcium')],
          moreOpen: open,
        ),
      ),
    );

    await tester.pumpWidget(card(open: false));
    expect(find.text('Calcium'), findsNothing);
    await tester.pumpWidget(card(open: true));
    expect(find.text('Calcium'), findsOneWidget);
  });
}
