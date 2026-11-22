import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/check_in_history.dart';

class _Store extends Fake implements AdaptiveStore {
  final List<CheckInRecord> records;

  _Store(this.records);

  @override
  Future<List<CheckInRecord>> history() async => records;
}

CheckInRecord _full(
  int day, {
  required double base,
  required double proposed,
  required double set,
  double rate = -0.5,
  double target = 75,
}) => CheckInRecord(
  date: DateTime(2026, 11, day),
  expenditureKcal: base,
  proposedKcal: proposed,
  acceptedKcal: set,
  activityKcal: 0,
  baseKcal: base,
  goalRateKgPerWeek: rate,
  targetWeightKg: target,
  basis: 'expenditure',
);

Map<String, double> _parts(CheckInRecord before, CheckInRecord now) => {
  for (final p in checkInChangeParts(before, now)!)
    if (p.kcal != 0) p.label: p.kcal,
};

void main() {
  group('checkInChangeParts', () {
    test('a Keep last time, accepted as proposed now: no edit of this one', () {
      // Kept 2738 over a proposed 2548; now 3043 accepted unchanged.
      final before = _full(14, base: 3000, proposed: 2548, set: 2738);
      final now = _full(21, base: 3000, proposed: 3043, set: 3043, rate: 0);
      final parts = _parts(before, now);
      expect(parts, {
        "Last time's change to the proposal ends": -190,
        "Goal's pace or the plan": 495,
      });
      expect(parts.values.fold(0.0, (a, b) => a + b), 3043 - 2738);
    });

    test('a figure typed now is this check-in\'s edit', () {
      final before = _full(14, base: 3000, proposed: 2500, set: 2500);
      final now = _full(21, base: 2950, proposed: 2450, set: 2400);
      final parts = _parts(before, now);
      expect(parts, {'Your estimate moved': -50, 'You edited it': -50});
      expect(parts.values.fold(0.0, (a, b) => a + b), -100);
    });

    test('a Keep now is said as a Keep, not an edit', () {
      final before = _full(14, base: 3000, proposed: 2500, set: 2500);
      final now = _full(21, base: 2900, proposed: 2400, set: 2500);
      final parts = _parts(before, now);
      expect(parts, {
        'Your estimate moved': -100,
        'You kept the last target': 100,
      });
      expect(parts.values.fold(0.0, (a, b) => a + b), 0);
    });
  });

  testWidgets('dates as the other pages give them, paces with a true minus', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CheckInHistoryScreen(
          store: _Store([
            _full(14, base: 3000, proposed: 2500, set: 2500),
            _full(21, base: 3000, proposed: 2900, set: 2900, rate: 0),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Nov 21, 2026'), findsOneWidget);
    expect(find.textContaining('21 Nov'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('check-in-2026-11-21')));
    await tester.pumpAndSettle();
    expect(find.text('Why it moved from Nov 14'), findsOneWidget);
    expect(find.text('Pace went from −0.5 to 0.0 kg a week.'), findsOne);
  });

  testWidgets('why it moved: the notes sit 12 apart, the inset once below', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(bottom: 144);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: CheckInHistoryScreen(
          store: _Store([
            _full(14, base: 3000, proposed: 2500, set: 2500),
            _full(21, base: 3000, proposed: 2900, set: 2900, rate: 0, target: 70),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('check-in-2026-11-21')));
    await tester.pumpAndSettle();
    final pace = tester.getBottomLeft(
      find.text('Pace went from −0.5 to 0.0 kg a week.'),
    );
    final target = tester.getTopLeft(
      find.textContaining('Target weight went from'),
    );
    expect(target.dy - pace.dy, 12);
  });
}
