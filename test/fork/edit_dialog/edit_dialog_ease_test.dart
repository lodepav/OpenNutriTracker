import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/edit_dialog.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/generated/l10n.dart';

final _intake = IntakeEntity(
  id: 'i-1',
  unit: 'g',
  amount: 150,
  type: IntakeTypeEntity.lunch,
  meal: MealEntity(
    code: 'rice',
    name: 'Rice',
    url: null,
    mealQuantity: null,
    mealUnit: 'g',
    servingQuantity: null,
    servingUnit: 'g',
    servingSize: null,
    nutriments: MealNutrimentsEntity.empty(),
    source: MealSourceEntity.custom,
  ),
  dateTime: DateTime.utc(2026, 10, 22),
);

/// Opens the dialog and returns what it pops with, once a test closes it.
Future<Future<double?>> _open(
  WidgetTester tester, {
  bool wholeMeal = false,
}) async {
  late Future<double?> result;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => result = showDialog<double>(
            context: context,
            builder: (_) => EditDialog(
              intakeEntity: _intake,
              usesImperialUnits: false,
              wholeMeal: wholeMeal,
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

TextEditingController _controller(WidgetTester tester, Finder field) =>
    tester.widget<TextFormField>(field).controller!;

/// Types [text] as a keyboard does: it replaces what is selected.
Future<void> _type(WidgetTester tester, Finder field, String text) async {
  final value = _controller(tester, field).value;
  final start = value.selection.start;
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: value.text.replaceRange(start, value.selection.end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
    ),
  );
  await tester.pump();
}

void main() {
  final amount = find.byType(TextFormField).first;
  final leftover = find.byType(TextFormField).last;

  testWidgets('tapping the amount selects it, so typing replaces it', (
    tester,
  ) async {
    final result = await _open(tester);

    await tester.tap(amount);
    await tester.pump();
    expect(
      _controller(tester, amount).selection,
      const TextSelection(baseOffset: 0, extentOffset: 3),
    );

    await _type(tester, amount, '80');
    expect(_controller(tester, amount).text, '80');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(await result, 80);
  });

  testWidgets('tapping a filled-in leftover selects it', (tester) async {
    await _open(tester);
    await tester.tap(find.text('½'));
    await tester.pump();

    await tester.tap(leftover);
    await tester.pump();

    expect(
      _controller(tester, leftover).selection,
      const TextSelection(baseOffset: 0, extentOffset: 2),
    );
  });

  testWidgets('the whole-meal button returns its own result', (tester) async {
    final result = await _open(tester, wholeMeal: true);

    await tester.tap(find.text(EditDialog.wholeMealLabel));
    await tester.pumpAndSettle();

    expect(await result, EditDialog.wholeMealResult);
  });

  testWidgets('with the whole-meal button it fits at 200% on 360 dp', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final result = await _open(tester, wholeMeal: true);

    expect(tester.takeException(), isNull);
    final button = find.ancestor(
      of: find.text(EditDialog.wholeMealLabel),
      matching: find.byWidgetPredicate((w) => w is TextButton),
    );
    // Taller than the screen at this size, so the content scrolls to it.
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(await result, EditDialog.wholeMealResult);
  });
}
