import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/fork/undo/undo_delete.dart';

import '../../fixture/intake_entity_fixtures.dart';

void main() {
  final restored = <(List<IntakeEntity>, DateTime, ProfileStamp)>[];
  Future<void> restore(
    List<IntakeEntity> intakes,
    DateTime day,
    ProfileStamp startedOn,
  ) async => restored.add((intakes, day, startedOn));
  final oats = intakeOf('oats', 50);
  final milk = intakeOf('milk', 200);
  final today = DateTime(2026, 10, 23);

  setUp(restored.clear);

  Future<BuildContext> pumpScaffold(WidgetTester tester) async {
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
    return context;
  }

  testWidgets('deletes in a row gather into one bar; its Undo restores all; '
      'another day starts a bar of its own', (tester) async {
    final context = await pumpScaffold(tester);
    void show(IntakeEntity intake, DateTime day) => DeletedEntries.show(
      context,
      intake,
      day,
      startedOn: ProfileStamp.now(),
      restore: restore,
    );

    show(oats, today);
    await tester.pumpAndSettle();
    expect(find.text('Food deleted'), findsOneWidget);

    show(milk, today);
    await tester.pumpAndSettle();
    expect(find.text('2 foods deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(restored.single.$1, [oats, milk]);
    expect(restored.single.$2, today);

    show(oats, today);
    await tester.pumpAndSettle();
    show(milk, DateTime(2026, 10, 22));
    await tester.pumpAndSettle();
    expect(find.text('Food deleted'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(restored.last.$1, [milk]);
  });

  testWidgets('the bar goes by itself, and a later delete starts its own', (
    tester,
  ) async {
    final context = await pumpScaffold(tester);
    DeletedEntries.show(
      context,
      oats,
      today,
      startedOn: ProfileStamp.now(),
      restore: restore,
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(find.text('Food deleted'), findsNothing);

    DeletedEntries.show(
      context,
      milk,
      today,
      startedOn: ProfileStamp.now(),
      restore: restore,
    );
    await tester.pumpAndSettle();
    expect(find.text('Food deleted'), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
  });

  testWidgets('a profile switch: no bar for a delete it overtook, and a '
      'delete in the new profile does not gather with the old one', (
    tester,
  ) async {
    final context = await pumpScaffold(tester);
    final before = ProfileStamp.now();
    DeletedEntries.show(
      context,
      oats,
      today,
      startedOn: before,
      restore: restore,
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() => withProfileSwitchLock(() async {}));

    DeletedEntries.show(
      context,
      milk,
      today,
      startedOn: before,
      restore: restore,
    );
    await tester.pumpAndSettle();
    expect(find.text('2 foods deleted'), findsNothing);
    expect(find.text('Food deleted'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    // The bar up is the old profile's oats: no bar for the overtaken milk,
    // and the oats are not restored into the new profile.
    expect(restored, isEmpty);
    expect(find.text('Not restored: the profile changed.'), findsOneWidget);

    final after = ProfileStamp.now();
    DeletedEntries.show(
      context,
      milk,
      today,
      startedOn: after,
      restore: restore,
    );
    await tester.pumpAndSettle();
    expect(find.text('Food deleted'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(restored.single.$1, [milk]);
    expect(restored.single.$3, same(after));
  });

  test(
    'Undo after a profile switch writes nothing into the new profile',
    () async {
      final before = ProfileStamp.now();
      await withProfileSwitchLock(() async {});
      // A write would reach CopyEntries.fromLocator, which has nothing here.
      await restoreDeletedIntakes([oats], today, before);
    },
  );

  testWidgets('a delete in a new profile does not gather with a bar still '
      'up from the old one', (tester) async {
    final context = await pumpScaffold(tester);
    DeletedEntries.show(
      context,
      oats,
      today,
      startedOn: ProfileStamp.now(),
      restore: restore,
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() => withProfileSwitchLock(() async {}));
    DeletedEntries.show(
      context,
      milk,
      today,
      startedOn: ProfileStamp.now(),
      restore: restore,
    );
    await tester.pumpAndSettle();
    expect(find.text('Food deleted'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(restored.single.$1, [milk]);
  });

  testWidgets('a delete while an undone bar leaves starts a bar of its own', (
    tester,
  ) async {
    final context = await pumpScaffold(tester);
    DeletedEntries.show(
      context,
      oats,
      today,
      startedOn: ProfileStamp.now(),
      restore: restore,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pump();
    DeletedEntries.show(
      context,
      milk,
      today,
      startedOn: ProfileStamp.now(),
      restore: restore,
    );
    await tester.pumpAndSettle();
    expect(find.text('Food deleted'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(restored.last.$1, [milk]);
  });
}
