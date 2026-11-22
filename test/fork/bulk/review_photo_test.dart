import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';

import '../screens/add_meal/photo_review_harness.dart';

const _rice = ParsedMealItem(query: 'rice', quantity: 150, unit: 'g');
final _thumbnail = find.bySemanticsIdentifier('bulk-add-review-photo');
final _full = find.bySemanticsIdentifier('bulk-add-review-photo-full');

/// A photo's review keeps the photo in view, to check each food against.
void main() {
  setUpReviewHarness('review_photo_test');

  testWidgets('the review shows the photo small, and whole on a tap', (
    tester,
  ) async {
    await openWithStagedPhoto(tester);
    await sendStagedPhoto(tester, const [_rice]);

    expect(_thumbnail, findsOneWidget);
    expect(
      find.descendant(of: _thumbnail, matching: find.byType(Image)),
      findsOneWidget,
    );

    await tapAndSettle(tester, _thumbnail);
    expect(_full, findsOneWidget);

    await tapAndSettle(tester, find.byTooltip('Close'));
    expect(_full, findsNothing);
    expect(_thumbnail, findsOneWidget);
  });
}
