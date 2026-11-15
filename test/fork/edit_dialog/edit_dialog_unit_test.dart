import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/edit_dialog.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/amounts/own_portions.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../helpers/ux_checks.dart';
import '../amounts/amount_test_foods.dart';

class _Own extends OwnPortions {
  final List<OwnPortionEntity> own;

  _Own(this.own);

  @override
  Future<List<OwnPortionEntity>> of(MealEntity meal) async => own;
}

IntakeEntity _logged(String unit, double amount, [MealEntity? meal]) =>
    IntakeEntity(
      id: 'i-1',
      unit: unit,
      amount: amount,
      type: IntakeTypeEntity.lunch,
      meal: meal ?? bread(),
      dateTime: DateTime.utc(2026, 11, 15),
    );

/// Opens the dialog with a unit notifier, as Home and the Diary do, and
/// returns what it pops with once a test closes it.
Future<Future<double?>> _open(
  WidgetTester tester,
  IntakeEntity intake,
  ValueNotifier<String> unit, {
  List<OwnPortionEntity> own = const [],
  bool phone = false,
}) async {
  final before = OwnPortions.current;
  OwnPortions.current = _Own(own);
  addTearDown(() => OwnPortions.current = before);
  late Future<double?> result;
  final opener = Builder(
    builder: (context) => TextButton(
      onPressed: () => result = showDialog<double>(
        context: context,
        builder: (_) => EditDialog(
          intakeEntity: intake,
          usesImperialUnits: false,
          unit: unit,
        ),
      ),
      child: const Text('open'),
    ),
  );
  if (phone) {
    // the app's fonts and theme at 200%, on a 360 dp wide screen
    await pumpOnPhone(tester, opener);
    tester.view.physicalSize = const Size(360 * 2.625, 640 * 2.625);
    await tester.pump();
  } else {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.supportedLocales,
        home: opener,
      ),
    );
  }
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

final _amount = find.byKey(const ValueKey('amount-field'));
final _leftover = find.byType(TextFormField).last;

String _text(WidgetTester tester, Finder field) => tester
    .widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    )
    .controller
    .text;

Future<void> _ok(WidgetTester tester) async {
  await tester.ensureVisible(find.text('OK'));
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an entry logged in a portion opens in that portion', (
    tester,
  ) async {
    final unit = ValueNotifier('serving#1');
    await _open(tester, _logged('serving#1', 120), unit);

    expect(_text(tester, _amount), '2');
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'roll · 60 g'))
          .selected,
      isTrue,
    );
    // the leftover is typed in rolls too
    expect(find.text('roll'), findsWidgets);
  });

  testWidgets('a weight chip converts the number, and OK stores grams', (
    tester,
  ) async {
    final unit = ValueNotifier('serving#1');
    final result = await _open(tester, _logged('serving#1', 120), unit);

    await tester.tap(find.widgetWithText(ChoiceChip, 'g'));
    await tester.pump();
    expect(_text(tester, _amount), '120');

    await _ok(tester);
    expect(await result, 120);
    expect(unit.value, 'g');
  });

  testWidgets('a count moved with + stores its grams in the same unit', (
    tester,
  ) async {
    final unit = ValueNotifier('serving#1');
    final result = await _open(tester, _logged('serving#1', 120), unit);

    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    expect(_text(tester, _amount), '3');

    await _ok(tester);
    expect(await result, 180);
    expect(unit.value, 'serving#1');
  });

  testWidgets('a leftover is typed and taken off in the portion', (
    tester,
  ) async {
    final unit = ValueNotifier('serving#1');
    final result = await _open(tester, _logged('serving#1', 120), unit);

    await tester.enterText(_leftover, '0.5');
    await tester.pump();
    expect(_text(tester, _amount), '1.5');

    await _ok(tester);
    expect(await result, 90);
  });

  testWidgets('a new unit clears the leftover and takes the next from it', (
    tester,
  ) async {
    final unit = ValueNotifier('serving#1');
    final result = await _open(tester, _logged('serving#1', 120), unit);
    await tester.enterText(_leftover, '0.5');
    await tester.pump();

    await tester.tap(find.widgetWithText(ChoiceChip, 'g'));
    await tester.pump();
    expect(_text(tester, _amount), '90');
    expect(_text(tester, _leftover), '');

    // half of the 120 g logged, not of the 90 g left
    await tester.ensureVisible(find.text('½'));
    await tester.tap(find.text('½'));
    await tester.pump();
    expect(_text(tester, _leftover), '60');
    expect(_text(tester, _amount), '60');

    await _ok(tester);
    expect(await result, 60);
    expect(unit.value, 'g');
  });

  testWidgets('own portions are chips, with nothing to add or remove one', (
    tester,
  ) async {
    final unit = ValueNotifier('serving#2');
    final result = await _open(
      tester,
      _logged('serving#2', 500),
      unit,
      own: const [OwnPortionEntity(label: 'bowl', gramWeight: 250)],
    );

    expect(_text(tester, _amount), '2');
    expect(find.widgetWithText(ChoiceChip, 'bowl · 250 g'), findsOneWidget);
    expect(find.byKey(const ValueKey('amount-add-portion')), findsNothing);
    expect(find.byKey(const ValueKey('amount-remove-serving#2')), findsNothing);

    await _ok(tester);
    expect(await result, 500);
    expect(unit.value, 'serving#2');
  });

  testWidgets('an energy-only Quick add keeps its energy field', (
    tester,
  ) async {
    final quick = MealEntity(
      code: null,
      name: 'Snack',
      url: null,
      mealQuantity: '100',
      mealUnit: 'gml',
      servingQuantity: null,
      servingUnit: null,
      servingSize: null,
      nutriments: const MealNutrimentsEntity(
        energyKcal100: 300,
        carbohydrates100: null,
        fat100: null,
        proteins100: null,
        sugars100: null,
        saturatedFat100: null,
        fiber100: null,
      ),
      source: MealSourceEntity.custom,
    );
    final unit = ValueNotifier('gml');
    final result = await _open(tester, _logged('gml', 100, quick), unit);

    expect(_amount, findsNothing);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('kcal'), findsWidgets);

    await tester.enterText(find.byType(TextFormField).first, '150');
    await _ok(tester);
    expect(await result, 50);
    expect(unit.value, 'gml');
  });

  testWidgets('it fits at 200% on 360 dp', (tester) async {
    final unit = ValueNotifier('serving#2');
    await _open(
      tester,
      _logged('serving#2', 500),
      unit,
      own: const [OwnPortionEntity(label: 'bowl', gramWeight: 250)],
      phone: true,
    );

    expect(tester.takeException(), isNull);
    expect(cutText(tester), isEmpty);
    // 48 dp targets, labelled, in contrast
    await expectAccessible(tester);
    await tester.ensureVisible(find.text('OK'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
