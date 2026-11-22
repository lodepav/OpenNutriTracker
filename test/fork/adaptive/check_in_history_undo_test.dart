import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/check_in_history.dart';

class _Store extends Fake implements AdaptiveStore {
  List<CheckInRecord> records;

  _Store(this.records);

  @override
  Future<List<CheckInRecord>> history() async => [...records];
}

class _Service extends Fake implements AdaptiveService {
  final _Store store;
  List<CheckInRecord>? restored;

  _Service(this.store);

  @override
  Future<void> restoreCheckIns(List<CheckInRecord> records) async {
    restored = records;
    store.records = records;
  }
}

CheckInRecord _record(int day, double set) => CheckInRecord(
  date: DateTime(2026, 11, day),
  expenditureKcal: 2900,
  proposedKcal: set,
  acceptedKcal: set,
);

void main() {
  // G4-22: the latest check-in can be undone from the history, with a
  // confirm; older ones can't.
  testWidgets('the latest check-in can be undone, after a confirm', (
    tester,
  ) async {
    final store = _Store([_record(14, 2500), _record(21, 250)]);
    final service = _Service(store);
    await tester.pumpWidget(
      MaterialApp(
        home: CheckInHistoryScreen(store: store, service: service),
      ),
    );
    await tester.pumpAndSettle();

    // One Undo, on the newest row.
    final undo = find.byKey(const ValueKey('undo-latest-check-in'));
    expect(undo, findsOneWidget);
    expect(
      find.ancestor(
        of: undo,
        matching: find.byKey(const ValueKey('check-in-2026-11-21')),
      ),
      findsNothing,
    );
    expect(
      tester.getTopLeft(undo).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('check-in-2026-11-14'))).dy,
      ),
    );

    await tester.tap(undo);
    await tester.pumpAndSettle();
    expect(find.text('Undo the check-in of Nov 21?'), findsOneWidget);
    expect(find.textContaining('goes back to 2500 kcal'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(service.restored, isNull);

    await tester.tap(undo);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo check-in'));
    await tester.pumpAndSettle();
    expect(service.restored, [store.records.single]);
    expect(store.records.single.acceptedKcal, 2500);
    expect(find.text('Check-in of Nov 21 undone.'), findsOneWidget);
    // The list shows the one left, which is now the latest.
    expect(find.byKey(const ValueKey('check-in-2026-11-21')), findsNothing);
    expect(find.byKey(const ValueKey('check-in-2026-11-14')), findsOneWidget);
  });
}
