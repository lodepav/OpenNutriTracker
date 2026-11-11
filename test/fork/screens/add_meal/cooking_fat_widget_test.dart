import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/dish/dish_strings.dart';
import 'package:opennutritracker/fork/screens/add_meal/bulk_add_screen.dart';

import 'photo_review_harness.dart';

const _egg = ParsedMealItem(query: 'egg, fried', quantity: 100, unit: 'g');
const _rice = ParsedMealItem(query: 'rice', quantity: 160, unit: 'g');

Finder _chip(int i) => find.byKey(ValueKey('bulk-add-cooking-fat-$i'));
final _none = find.byKey(const ValueKey('bulk-add-cooking-fat-none'));
final _question = find.byKey(const ValueKey('bulk-add-cooking-fat'));

bool _selected(WidgetTester tester, Finder chip) =>
    tester.widget<ChoiceChip>(chip).selected;

void main() {
  setUpReviewHarness('cooking_fat');

  final looked = <double>[];
  setUp(() {
    reviewFoods
      ..clear()
      ..addAll({
        'egg, fried': reviewFood('Egg, whole', kcal100: 200),
        'rice': reviewFood('Rice'),
      });
    looked.clear();
    final before = forkCookingFatFood;
    forkCookingFatFood = (grams) async {
      looked.add(grams);
      return ResolvedMealItem(
        parsed: ParsedMealItem(query: 'sunflower oil', quantity: grams),
        candidates: [reviewFood('Sunflower oil', kcal100: 900, serving: 14)],
        selectedIndex: 0,
        confidence: 0.9,
      );
    };
    addTearDown(() => forkCookingFatFood = before);
  });

  testWidgets('asked for a fried food, nothing chosen and nothing added', (
    tester,
  ) async {
    await openReview(tester);
    await readReviewPhoto(tester, const [_egg, _rice]);
    expect(find.text(DishStrings.cookedWithFat), findsOneWidget);
    expect(_selected(tester, _none), isFalse);
    for (var i = 0; i < 3; i++) {
      expect(_selected(tester, _chip(i)), isFalse);
    }
    expect(reviewRows().length, 2);
    expect(looked, isEmpty);
  });

  testWidgets('a salad asks about dressing', (tester) async {
    await openReview(tester);
    await readReviewPhoto(tester, const [
      ParsedMealItem(query: 'salad', quantity: 150, unit: 'g'),
    ]);
    expect(find.text(DishStrings.dressedWithFat), findsOneWidget);
    expect(find.text(DishStrings.cookedWithFat), findsNothing);
  });

  testWidgets('not asked when nothing was cooked in fat, or a fat is there', (
    tester,
  ) async {
    await openReview(tester);
    await readReviewPhoto(tester, const [_rice]);
    expect(_question, findsNothing);
    await readReviewPhoto(tester, const [
      _egg,
      ParsedMealItem(query: 'butter', quantity: 10, unit: 'g'),
    ]);
    expect(_question, findsNothing);
  });

  testWidgets('a little oil on the read asks for more, and a chip adds its '
      'own row beside the model\'s', (tester) async {
    await openReview(tester);
    await readReviewPhoto(tester, const [
      ParsedMealItem(query: 'salad', quantity: 150, unit: 'g'),
      ParsedMealItem(query: 'olive oil', quantity: 8, unit: 'g'),
    ]);
    expect(find.text(DishStrings.moreDressing), findsOneWidget);
    expect(find.text(DishStrings.dressedWithFat), findsNothing);

    await tapAndSettle(tester, _chip(0));
    expect(reviewRows().length, 3);
    expect(reviewRow(1).amountText, '8');
    expect(reviewRow(2).meal!.name, 'Sunflower oil');
    expect(reviewRow(2).amountText, '5');
  });

  testWidgets('a fried food with a little butter asks for more oil or '
      'butter', (tester) async {
    await openReview(tester);
    await readReviewPhoto(tester, const [
      _egg,
      ParsedMealItem(query: 'butter', quantity: 5, unit: 'g'),
    ]);
    expect(find.text(DishStrings.moreCookedFat), findsOneWidget);
  });

  testWidgets('a chip adds one row of the table\'s oil; another changes that '
      'row; None takes it off and ends the question', (tester) async {
    await openReview(tester);
    await readReviewPhoto(tester, const [_egg, _rice]);

    await tapAndSettle(tester, _chip(1));
    expect(looked, [10]);
    expect(reviewRows().length, 3);
    final oil = reviewRow(2);
    expect(oil.meal!.name, 'Sunflower oil');
    expect(oil.amountText, '10');
    expect(oil.unit, 'g');
    expect(oil.isLowConfidence, isFalse);
    expect(find.text('Sunflower oil'), findsOneWidget);
    expect(find.text('90 kcal'), findsOneWidget);
    expect(_selected(tester, _chip(1)), isTrue);

    await tapAndSettle(tester, _chip(2));
    expect(looked, [10], reason: 'the same row, not another');
    expect(reviewRows().length, 3);
    expect(identical(reviewRow(2).resolved, oil.resolved), isTrue);
    expect(reviewRow(2).amountText, '20');
    expect(_selected(tester, _chip(2)), isTrue);
    expect(_selected(tester, _chip(1)), isFalse);

    await tapAndSettle(tester, _none);
    expect(reviewRows().length, 2);
    expect(find.text('Sunflower oil'), findsNothing);
    expect(_question, findsNothing);
  });

  testWidgets('None before any amount just ends the question', (tester) async {
    await openReview(tester);
    await readReviewPhoto(tester, const [_egg, _rice]);
    await tapAndSettle(tester, _none);
    expect(_question, findsNothing);
    expect(reviewRows().length, 2);
  });

  testWidgets('the Size leaves the added row, "Set by you"', (tester) async {
    await openReview(tester);
    await readReviewPhoto(tester, const [_egg, _rice]);
    await tapAndSettle(tester, _chip(1));
    await tapAndSettle(tester, mealSize(0.6));
    expect(reviewRow(0).amountText, '60');
    expect(reviewRow(2).amountText, '10');
    expect(find.byKey(const ValueKey('bulk-add-set-by-you-2')), findsOneWidget);
    await tapAndSettle(tester, mealSize(1.4));
    expect(reviewRow(2).amountText, '10');
  });

  testWidgets('a chosen amount stays with a Size chosen first', (tester) async {
    await openReview(tester);
    await readReviewPhoto(tester, const [_egg, _rice]);
    await tapAndSettle(tester, mealSize(1.2));
    await tapAndSettle(tester, _chip(0));
    expect(reviewRow(2).amountText, '5');
    expect(reviewRow(0).amountText, '120');
  });

  testWidgets('the row is edited like any other, and the chips follow it', (
    tester,
  ) async {
    await openReview(tester);
    await readReviewPhoto(tester, const [_egg, _rice]);
    await tapAndSettle(tester, _chip(2));
    await tapAndSettle(tester, find.byKey(const ValueKey('bulk-add-more-2')));
    expect(reviewRow(2).amountText, '30');
    for (var i = 0; i < 3; i++) {
      expect(_selected(tester, _chip(i)), isFalse);
    }
    await tapAndSettle(tester, _chip(1));
    expect(reviewRow(2).amountText, '10');
  });

  testWidgets('chips are 48 dp, spoken with grams', (tester) async {
    final semantics = tester.ensureSemantics();
    await openReview(tester);
    await readReviewPhoto(tester, const [_egg, _rice]);
    expect(tester.getSize(_none).height, greaterThanOrEqualTo(48));
    for (var i = 0; i < 3; i++) {
      expect(tester.getSize(_chip(i)).height, greaterThanOrEqualTo(48));
    }
    expect(
      tester.getSemantics(_chip(1)),
      isSemantics(
        label: DishStrings.fatSomeSpoken,
        hasSelectedState: true,
        isSelected: false,
      ),
    );
    semantics.dispose();
  });

  testWidgets('a chip after the user changed the row\'s unit sets grams', (
    tester,
  ) async {
    await openReview(tester);
    await readReviewPhoto(tester, const [_egg, _rice]);
    await tapAndSettle(tester, _chip(0));
    reviewBloc.add(const ChangeRowUnitEvent(2, 'serving'));
    await tester.pumpAndSettle();
    expect(reviewRow(2).effectiveUnit, 'serving');
    for (var i = 0; i < 3; i++) {
      expect(_selected(tester, _chip(i)), isFalse);
    }
    await tapAndSettle(tester, _chip(2));
    expect(reviewRow(2).unit, 'g');
    expect(reviewRow(2).amountText, '20');
    expect(_selected(tester, _chip(2)), isTrue);
  });

  testWidgets('None while the oil is looked up: nothing added when it '
      'arrives', (tester) async {
    final lookup = Completer<ResolvedMealItem?>();
    forkCookingFatFood = (_) => lookup.future;
    await openReview(tester);
    await readReviewPhoto(tester, const [_egg, _rice]);
    await tapAndSettle(tester, _chip(1));
    expect(_selected(tester, _chip(1)), isTrue);
    await tapAndSettle(tester, _none);
    lookup.complete(
      ResolvedMealItem(
        parsed: const ParsedMealItem(query: 'sunflower oil', quantity: 10),
        candidates: [reviewFood('Sunflower oil', kcal100: 900)],
        selectedIndex: 0,
        confidence: 1,
      ),
    );
    await tester.pumpAndSettle();
    expect(reviewRows().length, 2);
    expect(find.text('Sunflower oil'), findsNothing);
    expect(_question, findsNothing);
  });

  testWidgets('no oil in the table: said, and no row', (tester) async {
    forkCookingFatFood = (_) async => null;
    await openReview(tester);
    await readReviewPhoto(tester, const [_egg, _rice]);
    await tapAndSettle(tester, _chip(1));
    expect(find.text(DishStrings.fatNotFound), findsOneWidget);
    expect(reviewRows().length, 2);
    expect(_selected(tester, _chip(1)), isFalse);
  });

  testWidgets('not asked on a weighed plate', (tester) async {
    await openWithStagedPhoto(tester);
    await tester.enterText(find.byType(TextField).first, '260 g');
    await tester.pump();
    await sendStagedPhoto(tester, const [_egg, _rice]);
    expect(reviewReader.notes.last, '260 g');
    expect(reviewRows().length, 2);
    expect(_question, findsNothing);
  });
}
