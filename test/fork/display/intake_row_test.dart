import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';

import '../screens/home/intake_card_sort_test.dart'
    as card;

void main() {
  tearDown(() => DisplayPrefs.macroOrder.value = DisplayPrefs.upstreamOrder);

  testWidgets('a logged food shows its own macros under the name and the '
      'amount under the energy', (tester) async {
    await tester.pumpWidget(card.wrap(null));

    expect(find.text('C 30 · F 15 · P 8', findRichText: true), findsOneWidget);
    expect(find.text('150 g'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('150 g')).dy,
      greaterThan(tester.getTopLeft(find.text('300 kcal')).dy),
    );
  });

  testWidgets('the macros follow the chosen order', (tester) async {
    DisplayPrefs.macroOrder.value = [Macro.protein, Macro.fat, Macro.carbs];
    await tester.pumpWidget(card.wrap(null));

    expect(find.text('P 8 · F 15 · C 30', findRichText: true), findsOneWidget);
  });

  testWidgets('fits at a large text size', (tester) async {
    await tester.pumpWidget(card.wrap(null, scale: 2));
    expect(tester.takeException(), isNull);
  });
}
