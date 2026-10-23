import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/fork/undo/undo_delete.dart';

import '../../fixture/intake_entity_fixtures.dart';

void main() {
  testWidgets('deletes in a row gather into one bar; its Undo restores all; '
      'another day starts a bar of its own', (tester) async {
    final restored = <(List<IntakeEntity>, DateTime)>[];
    Future<void> restore(List<IntakeEntity> intakes, DateTime day) async =>
        restored.add((intakes, day));
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    final oats = intakeOf('oats', 50);
    final milk = intakeOf('milk', 200);
    final today = DateTime(2026, 10, 23);

    DeletedEntries.show(context, oats, today, restore: restore);
    await tester.pumpAndSettle();
    expect(find.text('Entry deleted'), findsOneWidget);

    DeletedEntries.show(context, milk, today, restore: restore);
    await tester.pumpAndSettle();
    expect(find.text('2 entries deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(restored.single.$1, [oats, milk]);
    expect(restored.single.$2, today);

    DeletedEntries.show(context, oats, today, restore: restore);
    await tester.pumpAndSettle();
    DeletedEntries.show(
      context,
      milk,
      DateTime(2026, 10, 22),
      restore: restore,
    );
    await tester.pumpAndSettle();
    expect(find.text('Entry deleted'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(restored.last.$1, [milk]);
  });
}
