import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';

import '../../helpers/test_l10n.dart';
import '../screens/add_meal/photo_review_harness.dart';

const _rice = ParsedMealItem(query: 'rice', quantity: 150, unit: 'g');
final _read = find.bySemanticsIdentifier('bulk-add-parse');
const _replaceTitle = 'Replace your edited foods?';

/// Typed foods found, one left out, and a photo waiting with a note.
Future<void> _rowsThenPhoto(WidgetTester tester) async {
  await openWithStagedPhoto(tester);
  reviewBloc.add(
    const ParseBulkTextEvent(text: 'salad, egg', usesImperialUnits: false),
  );
  await tester.pumpAndSettle();
  expect(reviewRows(), hasLength(2));
  await tapAndSettle(
    tester,
    find.byKey(const ValueKey('bulk-add-leave-out-0')),
  );
  await tester.enterText(find.bySemanticsIdentifier('bulk-add-input'), 'lunch');
  await tester.pump();
}

/// Read a photo asks, as Find again does, before edited rows go (crit r3).
void main() {
  setUpReviewHarness('read_photo_replace_test');

  testWidgets('Read a photo asks before edited rows go; Cancel keeps all', (
    tester,
  ) async {
    await _rowsThenPhoto(tester);

    await tapAndSettle(tester, _read);
    expect(find.text(_replaceTitle), findsOneWidget);
    // Replace loses work: in the error colour (crit r4 g2)
    final replace = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Replace'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(
      replace.style?.backgroundColor?.resolve(const {}),
      Theme.of(tester.element(find.text('Replace'))).colorScheme.error,
    );
    await tapAndSettle(tester, find.text(l10nEn.dialogCancelLabel));

    expect(reviewReader.notes, isEmpty);
    expect(reviewRow(0).skipped, isTrue);
    expect(find.text('lunch'), findsOneWidget);
    expect(find.bySemanticsIdentifier('bulk-add-photo-staged'), findsOneWidget);

    reviewReader.items = const [_rice];
    await tapAndSettle(tester, _read);
    await tapAndSettle(tester, find.text('Replace'));
    expect(reviewReader.notes, ['lunch']);
    expect(reviewRows().single.resolved.parsed.query, 'rice');
  });

  testWidgets('Name the dish asks before edited rows go; Cancel keeps all', (
    tester,
  ) async {
    await openWithStagedPhoto(tester);
    await sendStagedPhoto(tester, const [
      _rice,
      ParsedMealItem(query: 'chicken', quantity: 100, unit: 'g'),
    ]);
    await tapAndSettle(
      tester,
      find.byKey(const ValueKey('bulk-add-leave-out-0')),
    );
    final name = find.text('Name the dish');

    await tapAndSettle(tester, name);
    expect(find.text(_replaceTitle), findsOneWidget);
    await tapAndSettle(tester, find.text(l10nEn.dialogCancelLabel));
    expect(find.text('Name what you ate'), findsNothing);
    expect(reviewReader.notes, hasLength(1));
    expect(reviewRow(0).skipped, isTrue);

    await tapAndSettle(tester, name);
    await tapAndSettle(tester, find.text('Replace'));
    await tester.enterText(
      find.descendant(
        of: find.bySemanticsIdentifier('name-dish-field'),
        matching: find.byType(TextField),
      ),
      'pilaf',
    );
    await tapAndSettle(tester, find.text('Read again'));
    expect(reviewReader.notes.last, 'pilaf');
  });

  testWidgets('Name the dish with untouched rows asks nothing first', (
    tester,
  ) async {
    await openWithStagedPhoto(tester);
    await sendStagedPhoto(tester, const [_rice]);

    await tapAndSettle(tester, find.text('Name the dish'));
    expect(find.text(_replaceTitle), findsNothing);
    expect(find.text('Name what you ate'), findsOneWidget);
  });

  testWidgets('with foods found, Read a photo is outlined beside Log', (
    tester,
  ) async {
    await _rowsThenPhoto(tester);

    expect(
      find.descendant(of: _read, matching: find.byType(OutlinedButton)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _read, matching: find.byType(FilledButton)),
      findsNothing,
    );
    expect(
      find.descendant(of: _read, matching: find.text(l10nEn.bulkAddPhotoLabel)),
      findsOneWidget,
    );
  });

  testWidgets('with no foods yet, Read a photo stays filled', (tester) async {
    await openWithStagedPhoto(tester);

    expect(
      find.descendant(of: _read, matching: find.byType(FilledButton)),
      findsOneWidget,
    );
  });
}
