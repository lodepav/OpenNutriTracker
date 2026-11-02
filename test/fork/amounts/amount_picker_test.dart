import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/fork/amounts/amount_picker.dart';
import 'package:opennutritracker/fork/amounts/own_portions.dart';
import 'package:opennutritracker/generated/l10n.dart';

import 'amount_test_foods.dart';

/// The picker as the food's sheet holds it: its amount and unit set
/// together, as the sheet's _forkSet does.
class _Host extends StatefulWidget {
  final MealEntity meal;
  final String unit;
  final String text;
  final List<(String, String)> sets;

  const _Host(this.meal, this.unit, this.text, this.sets);

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late final controller = TextEditingController(text: widget.text);
  late String unit = widget.unit;
  late MealEntity meal = widget.meal;

  @override
  Widget build(BuildContext context) => AmountPicker(
    meal: meal,
    unit: unit,
    controller: controller,
    onSet: (text, to) {
      widget.sets.add((text, to));
      setState(() {
        controller.text = text;
        unit = to;
      });
    },
    onAddPortion: (label, grams) async {
      setState(
        () => meal = withOwnPortions(meal, [
          OwnPortionEntity(label: label, gramWeight: grams),
        ]),
      );
      return meal;
    },
  );
}

Future<List<(String, String)>> _pump(
  WidgetTester tester,
  MealEntity meal, {
  String unit = 'g',
  String text = '64',
}) async {
  final sets = <(String, String)>[];
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: _Host(meal, unit, text, sets)),
    ),
  );
  return sets;
}

String _summary(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('amount-summary'))).data!;

void main() {
  testWidgets("the food's portions are chips with their weights, then g", (
    tester,
  ) async {
    await _pump(tester, bread());
    expect(find.text('slice · 32 g'), findsOneWidget);
    expect(find.text('roll · 60 g'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'g'), findsOneWidget);
    expect(find.text('oz'), findsNothing);
    expect(find.text('ml'), findsNothing);
    expect(_summary(tester), '158 kcal');
  });

  testWidgets('a chip keeps the amount: 64 g becomes 2 slices', (tester) async {
    final sets = await _pump(tester, bread());
    await tester.tap(find.text('slice · 32 g'));
    await tester.pump();
    expect(sets.last, ('2', 'serving'));
    expect(_summary(tester), '2 × slice = 64 g · 158 kcal');
  });

  testWidgets('a weight that is a number of portions offers them', (
    tester,
  ) async {
    final sets = await _pump(tester, bread());
    expect(find.text('= 2 × slice'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('amount-fits')));
    await tester.pump();
    expect(sets.last, ('2', 'serving'));
    // Now in slices, it is not offered again.
    expect(find.byKey(const ValueKey('amount-fits')), findsNothing);
  });

  testWidgets('− and + move by the unit: a slice, or 10 g', (tester) async {
    final sets = await _pump(tester, bread(), unit: 'serving', text: '2');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(sets.last, ('3', 'serving'));
    await tester.tap(find.byIcon(Icons.remove));
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    expect(sets.last, ('1', 'serving'));

    await tester.tap(find.widgetWithText(ChoiceChip, 'g'));
    await tester.pump();
    expect(sets.last, ('32', 'g'));
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(sets.last, ('40', 'g'));
  });

  testWidgets('a typed amount is read as it is typed', (tester) async {
    await _pump(tester, bread());
    await tester.enterText(find.byKey(const ValueKey('amount-field')), '96');
    await tester.pump();
    expect(_summary(tester), '237 kcal');
    expect(find.text('= 3 × slice'), findsOneWidget);
  });

  testWidgets('a food with only grams takes a portion of the user\'s own, '
      'prefilled with the amount on the page', (tester) async {
    final sets = await _pump(tester, rye(serving: null), text: '70');
    expect(find.byType(ChoiceChip), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('amount-add-portion')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('portion-grams')))
          .controller!
          .text,
      '70',
    );
    await tester.enterText(find.byKey(const ValueKey('portion-grams')), '35');
    await tester.enterText(find.byKey(const ValueKey('portion-name')), 'slice');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('portion-save')));
    await tester.pumpAndSettle();

    expect(find.text('slice · 35 g'), findsOneWidget);
    expect(sets.last, ('2', 'serving'));
    expect(_summary(tester), startsWith('2 × slice = 70 g'));
  });
}
