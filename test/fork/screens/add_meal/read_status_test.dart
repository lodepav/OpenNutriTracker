import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_photo_usecase.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';

import '../../../helpers/test_l10n.dart';
import 'photo_review_harness.dart';

// Log with AI says a read to a screen reader once as it changes: started,
// the foods found, or why it failed; a row edit after it says nothing more.

List<String> _said(WidgetTester tester) =>
    tester.takeAnnouncements().map((a) => a.message).toList();

void main() {
  setUpReviewHarness('read_status');

  testWidgets('started, then the foods found; a row edit says no more', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await openReview(tester);
    _said(tester);
    await readReviewPhoto(tester, const [
      ParsedMealItem(query: 'rice', quantity: 150, unit: 'g'),
      ParsedMealItem(query: 'chicken', quantity: 100, unit: 'g'),
    ]);
    expect(_said(tester), ['Reading the meal', 'Found 2 foods']);

    await tapAndSettle(tester, find.byKey(const ValueKey('bulk-add-more-0')));
    expect(reviewRow(0).amountText, isNot('150'));
    expect(_said(tester), isEmpty);
    semantics.dispose();
  });

  testWidgets('one food is said as one', (tester) async {
    final semantics = tester.ensureSemantics();
    await openReview(tester);
    _said(tester);
    await readReviewPhoto(tester, const [
      ParsedMealItem(query: 'rice', quantity: 150, unit: 'g'),
    ]);
    expect(_said(tester), ['Reading the meal', 'Found 1 food']);
    semantics.dispose();
  });

  testWidgets('a photo with no food says the line the screen shows', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await openReview(tester);
    _said(tester);
    await readReviewPhoto(tester, const []);
    expect(_said(tester), ['Reading the meal', l10nEn.bulkAddPhotoNoFoodLabel]);
    semantics.dispose();
  });

  testWidgets('a failed read says why', (tester) async {
    final semantics = tester.ensureSemantics();
    await openReview(tester);
    _said(tester);
    reviewReader.answer = const MealPhotoFailed(MealPhotoFailure.transient);
    await readReviewPhoto(tester, const []);
    expect(find.text(l10nEn.bulkAddPhotoFailedLabel), findsOneWidget);
    expect(_said(tester), ['Reading the meal', l10nEn.bulkAddPhotoFailedLabel]);
    semantics.dispose();
  });
}
