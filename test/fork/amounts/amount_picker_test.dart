import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/fork/amounts/amount_picker.dart';
import 'package:opennutritracker/fork/amounts/own_portions.dart';
import 'package:opennutritracker/fork/display/contrast.dart';
import 'package:opennutritracker/generated/l10n.dart';

import 'amount_test_foods.dart';

/// The picker as the food's sheet holds it: its amount and unit set
/// together, as the sheet's _forkSet does.
class _Host extends StatefulWidget {
  final MealEntity meal;
  final String unit;
  final String text;
  final List<(String, String)> sets;
  final bool keepCounts;

  const _Host(
    this.meal,
    this.unit,
    this.text,
    this.sets, {
    this.keepCounts = false,
  });

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
    keepCountBetweenPortions: widget.keepCounts,
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
    onRemovePortion: (label) async {
      setState(
        () => meal = withOwnPortions(meal, [
          for (final p in meal.portions)
            if (p is OwnPortionEntity && p.label != label) p,
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
  bool keepCounts = false,
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
      home: Scaffold(
        body: _Host(meal, unit, text, sets, keepCounts: keepCounts),
      ),
    ),
  );
  return sets;
}

String _summary(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('amount-summary'))).data!;

void main() {
  testWidgets("the food's portions are chips with their weights, then Grams", (
    tester,
  ) async {
    await _pump(tester, bread());
    expect(find.text('slice · 32 g'), findsOneWidget);
    expect(find.text('roll · 60 g'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Grams'), findsOneWidget);
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

    await tester.tap(find.widgetWithText(ChoiceChip, 'Grams'));
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

  testWidgets('an own portion has a remove button, and the long-press stays', (
    tester,
  ) async {
    await _pump(
      tester,
      withOwnPortions(rye(serving: null), [
        const OwnPortionEntity(label: 'slice', gramWeight: 35),
        const OwnPortionEntity(label: 'heel', gramWeight: 20),
      ]),
    );
    final remove = find.byTooltip('Remove slice');
    expect(remove, findsOneWidget);
    final button = find.ancestor(of: remove, matching: find.byType(IconButton));
    expect(tester.getSize(button), const Size(48, 48));
    // Only the user's own portions have one.
    expect(find.byIcon(Icons.close_rounded), findsNWidgets(2));

    await tester.tap(remove);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.textContaining('slice'), findsNothing);
    expect(find.byTooltip('Remove heel'), findsOneWidget);

    await tester.longPress(find.textContaining('heel'));
    await tester.pumpAndSettle();
    expect(find.text('Remove "heel"?'), findsOneWidget);
  });

  testWidgets('on Log with AI a count stays when the portion changes, and '
      'the unit shown, chosen again, is confirmed', (tester) async {
    final sets = await _pump(
      tester,
      bread(),
      unit: 'serving#1',
      text: '3',
      keepCounts: true,
    );
    await tester.tap(find.text('slice · 32 g'));
    await tester.pump();
    expect(sets.last, ('3', 'serving'));
    await tester.tap(find.text('slice · 32 g'));
    await tester.pump();
    expect(sets.length, 2);
    // To grams it still converts.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Grams'));
    await tester.pump();
    expect(sets.last, ('96', 'g'));
  });

  for (final palette in [AppPalette.light, AppPalette.dark]) {
    testWidgets('the unfocused field has a 3:1 edge '
        '(${palette == AppPalette.dark ? 'dark' : 'light'})', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(palette),
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(body: _Host(bread(), 'g', '64', [])),
        ),
      );
      final decoration = tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('amount-field')),
              matching: find.byType(TextField),
            ),
          )
          .decoration!;
      final side = decoration.enabledBorder?.borderSide;
      expect(side, isNotNull);
      expect(side!.style, BorderStyle.solid);
      // on the sheet and on the field's own fill
      expect(
        contrastRatio(side.color, palette.surface),
        greaterThanOrEqualTo(3),
      );
      expect(
        contrastRatio(side.color, palette.surfaceMuted),
        greaterThanOrEqualTo(3),
      );
    });
  }
}
