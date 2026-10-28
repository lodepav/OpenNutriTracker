import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/bulk/name_dish_dialog.dart';

void main() {
  testWidgets('returns what was typed, trimmed', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await askDishName(context, initial: 'dumplings'),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('dumplings'), findsOneWidget, reason: 'the note so far');

    await tester.enterText(find.byType(TextField), ' pelmeni ');
    await tester.tap(find.text('Read again'));
    await tester.pumpAndSettle();
    expect(result, 'pelmeni');
  });

  testWidgets('cancelled or left empty: null', (tester) async {
    var calls = 0;
    String? result = 'unset';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await askDishName(context);
              calls++;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect((calls, result), (1, null));

    result = 'unset';
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Read again'));
    await tester.pumpAndSettle();
    expect((calls, result), (2, null));
  });
}
