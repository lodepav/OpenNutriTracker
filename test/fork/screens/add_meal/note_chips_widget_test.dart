import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';

import 'photo_review_harness.dart';

Finder _chip(int i) => find.byKey(ValueKey('bulk-add-note-chip-$i'));
final _chips = find.byKey(const ValueKey('bulk-add-note-chips'));

String _note(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).first).controller!.text;

const _rice = ParsedMealItem(query: 'rice', quantity: 160, unit: 'g');

void main() {
  setUpReviewHarness('note_chips');

  testWidgets('not shown without a photo waiting', (tester) async {
    await openReview(tester);
    expect(_chips, findsNothing);
  });

  testWidgets('a tap writes into the note, which stays editable, and the '
      'note sent with the photo carries it', (tester) async {
    await openWithStagedPhoto(tester);
    expect(_chips, findsOneWidget);

    await tapAndSettle(tester, _chip(3)); // Home-cooked
    expect(_note(tester), 'home-cooked');
    expect(tester.widget<FilterChip>(_chip(3)).selected, isTrue);

    await tapAndSettle(tester, _chip(0)); // Weighed
    expect(_note(tester), 'home-cooked, weighed: ');
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.selection.baseOffset, _note(tester).length);
    expect(field.focusNode!.hasFocus, isTrue);

    await tester.enterText(
      find.byType(TextField).first,
      '${_note(tester)}350 g',
    );
    await tester.pump();
    await sendStagedPhoto(tester, const [_rice]);
    expect(reviewReader.notes.last, 'home-cooked, weighed: 350 g');
  });

  testWidgets('a second tap takes exactly those words out', (tester) async {
    await openWithStagedPhoto(tester);
    await tester.enterText(find.byType(TextField).first, 'pelmeni');
    await tester.pump();
    await tapAndSettle(tester, _chip(4)); // Small plate
    expect(_note(tester), 'pelmeni, small plate');
    await tapAndSettle(tester, _chip(4));
    expect(_note(tester), 'pelmeni');
    expect(tester.widget<FilterChip>(_chip(4)).selected, isFalse);
  });

  testWidgets('six chips, 48 dp each, on one line', (tester) async {
    await openWithStagedPhoto(tester);
    final tops = <double>{};
    for (var i = 0; i < 6; i++) {
      expect(_chip(i), findsOneWidget);
      expect(tester.getSize(_chip(i)).height, greaterThanOrEqualTo(48));
      tops.add(tester.getTopLeft(_chip(i)).dy);
    }
    expect(tops.length, 1);
    expect(
      [
        for (var i = 0; i < 6; i++)
          (tester.widget<FilterChip>(_chip(i)).label as Text).data,
      ],
      [
        'Weighed',
        'Counts',
        'Restaurant',
        'Home-cooked',
        'Small plate',
        'Large plate',
      ],
    );
  });
}
