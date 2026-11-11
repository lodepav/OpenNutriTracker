import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/dish/dish_strings.dart';

import 'photo_review_harness.dart';

/// Chicken outweighs salad in energy, so the amount question is on the
/// chicken; salad's serving is 50 g.
const _chicken = ParsedMealItem(query: 'chicken', quantity: 200, unit: 'g');
const _salad = ParsedMealItem(query: 'salad', quantity: 400, unit: 'g');

Finder _line(int row) => find.byKey(ValueKey('bulk-add-usual-serving-$row'));
Finder _take(int row) =>
    find.byKey(ValueKey('bulk-add-usual-serving-take-$row'));

void main() {
  setUpReviewHarness('usual_serving');

  setUp(() {
    reviewFoods
      ..clear()
      ..addAll({
        'chicken': reviewFood('chicken', kcal100: 200, serving: 100),
        'salad': reviewFood('salad', kcal100: 20, serving: 50),
      });
  });

  testWidgets('an amount eight servings big says the usual serving, and '
      'nothing changes until its chip is tapped', (tester) async {
    await openReview(tester);
    await readReviewPhoto(tester, const [_chicken, _salad]);
    expect(_line(1), findsOneWidget);
    expect(find.text('Usual serving is about 50 g'), findsOneWidget);
    expect(find.text('Use 50 g'), findsOneWidget);
    // within three servings: no line
    expect(_line(0), findsNothing);
    expect(reviewRow(1).amountText, '400');
  });

  testWidgets('its chip sets the amount as the user\'s: the line goes, and '
      'the Size leaves the row, "Set by you"', (tester) async {
    final semantics = tester.ensureSemantics();
    await openReview(tester);
    await readReviewPhoto(tester, const [_chicken, _salad]);
    await tapAndSettle(tester, _take(1));
    expect(reviewRow(1).amountText, '50');
    expect(reviewRow(1).amountEditedByUser, isTrue);
    expect(_line(1), findsNothing);
    expect(
      tester.takeAnnouncements().map((a) => a.message),
      contains('50 grams. Meal now 410 kcal'),
    );

    await tapAndSettle(tester, mealSize(0.6));
    expect(reviewRow(0).amountText, '120');
    expect(reviewRow(1).amountText, '50');
    expect(find.byKey(const ValueKey('bulk-add-set-by-you-1')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('an amount the user changed another way ends the line', (
    tester,
  ) async {
    await openReview(tester);
    await readReviewPhoto(tester, const [_chicken, _salad]);
    await tapAndSettle(tester, find.byKey(const ValueKey('bulk-add-more-1')));
    expect(reviewRow(1).amountText, '410');
    expect(_line(1), findsNothing);
  });

  testWidgets('not on the row the amount question is on', (tester) async {
    await openReview(tester);
    await readReviewPhoto(tester, const [_salad]);
    expect(
      find.byKey(const ValueKey('bulk-add-amount-question-0')),
      findsOneWidget,
    );
    expect(_line(0), findsNothing);
  });

  testWidgets('follows the amount the Size shows', (tester) async {
    await openReview(tester);
    await readReviewPhoto(tester, const [
      _chicken,
      ParsedMealItem(query: 'salad', quantity: 160, unit: 'g'),
    ]);
    expect(_line(1), findsOneWidget);
    await tapAndSettle(tester, mealSize(0.8));
    expect(reviewRow(1).amountText, '128');
    expect(_line(1), findsNothing);
    await tapAndSettle(tester, mealSize(1.0));
    expect(_line(1), findsOneWidget);
  });

  testWidgets('a 48 dp chip, read as a line and a chip', (tester) async {
    final semantics = tester.ensureSemantics();
    await openReview(tester);
    await readReviewPhoto(tester, const [_chicken, _salad]);
    expect(tester.getSize(_take(1)).height, greaterThanOrEqualTo(48));
    expect(
      tester.getSemantics(find.text('Usual serving is about 50 g')),
      isSemantics(label: 'Usual serving is about 50 grams'),
    );
    expect(
      find.bySemanticsLabel(DishStrings.useUsualServing('50 grams')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('not for typed text', (tester) async {
    await openReview(tester);
    await tester.enterText(find.byType(TextField).first, 'salad, egg');
    await tester.pump();
    await tester.tap(find.widgetWithIcon(FilledButton, Icons.search));
    await tester.pumpAndSettle();
    expect(reviewRow(0).amountText, '400');
    expect(_line(0), findsNothing);
  });
}
