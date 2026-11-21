import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_ui.dart';
import 'package:opennutritracker/fork/adaptive/check_in_history.dart';

import '../../helpers/ux_checks.dart';

class _Store extends Fake implements AdaptiveStore {
  final List<CheckInRecord> records;

  _Store(this.records);

  @override
  Future<List<CheckInRecord>> history() async => records;

  @override
  Future<void> save(AdaptiveSettings value) async =>
      AdaptiveStore.settings.value = value;
}

CheckInRecord _record(int day, double spent, double proposed, double set) =>
    CheckInRecord(
      date: DateTime(2026, 10, day),
      expenditureKcal: spent,
      proposedKcal: proposed,
      acceptedKcal: set,
    );

CheckInRecord _full(
  int day, {
  required double base,
  double activity = 0,
  required double proposed,
  required double set,
  double rate = -0.5,
  double? targetKg = 75,
  String basis = 'expenditure',
}) => CheckInRecord(
  date: DateTime(2026, 10, day),
  expenditureKcal: base + activity,
  proposedKcal: proposed,
  acceptedKcal: set,
  activityKcal: activity,
  baseKcal: base,
  goalRateKgPerWeek: rate,
  targetWeightKg: targetKg,
  basis: basis,
);

void main() {
  tearDown(() => AdaptiveStore.settings.value = const AdaptiveSettings());

  group('checkInChangeParts', () {
    test('the parts add up to the change', () {
      final before = _full(5, base: 2600, proposed: 2100, set: 2050);
      final now = _full(
        12,
        base: 2550,
        activity: 120,
        proposed: 2345,
        set: 2400,
        rate: -0.25,
      );
      final parts = checkInChangeParts(before, now)!;
      expect(
        {for (final p in parts) p.label: p.kcal},
        {
          'Your estimate moved': -50,
          'Counted activity': 120,
          "Last time's change to the proposal ends": 50,
          'You edited it': 55,
          "Goal's pace or the plan": 175,
        },
      );
      expect(parts.fold(0.0, (a, p) => a + p.kcal), 350);
    });

    test('the rounding of an accepted target is not an edit', () {
      final before = _full(5, base: 2600, proposed: 2100.4, set: 2100);
      final now = _full(12, base: 2500, proposed: 1999.5, set: 2000);
      final parts = {
        for (final p in checkInChangeParts(before, now)!) p.label: p.kcal,
      };
      expect(parts['You edited it'], 0);
      expect(parts.values.fold(0.0, (a, b) => a + b), -100);
    });

    test('an older record has no split', () {
      final full = _full(12, base: 2550, proposed: 2050, set: 2050);
      expect(checkInChangeParts(_record(5, 2600, 2100, 2100), full), isNull);
      expect(checkInChangeParts(full, _record(19, 2600, 2100, 2100)), isNull);
      final noBasis = CheckInRecord(
        date: DateTime(2026, 10, 5),
        expenditureKcal: 2600,
        proposedKcal: 2100,
        acceptedKcal: 2100,
        goalRateKgPerWeek: -0.5,
      );
      expect(checkInChangeParts(noBasis, full), isNull);
    });
  });

  testWidgets('a tap shows why the target moved', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CheckInHistoryScreen(
          store: _Store([
            _record(1, 2600, 2100, 2100),
            _full(5, base: 2600, proposed: 2100, set: 2100),
            _full(
              12,
              base: 2550,
              proposed: 2300,
              set: 2300,
              rate: -0.25,
              basis: 'profile',
            ),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tappable = find.byKey(const ValueKey('check-in-2026-10-12'));
    expect(
      tester.getSemantics(tappable),
      isSemantics(hint: 'Shows why it moved', hasTapAction: true),
    );
    // The first full record follows an older one: no split.
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('check-in-2026-10-05')))
          .onTap,
      isNull,
    );

    await tester.tap(tappable);
    await tester.pumpAndSettle();
    expect(find.text('Why it moved from Oct 5'), findsOneWidget);
    expect(find.text('Your estimate moved'), findsOneWidget);
    expect(find.text('\u221250 kcal'), findsOneWidget);
    expect(find.text("Goal's pace or the plan"), findsOneWidget);
    expect(find.text('+250 kcal'), findsOneWidget);
    // Parts that round to nothing are left out.
    expect(find.text('Counted activity'), findsNothing);
    expect(find.text('You edited it'), findsNothing);
    expect(find.text('In all'), findsOneWidget);
    expect(
      find.text('Pace went from \u22120.5 to \u22120.25 kg a week.'),
      findsOne,
    );
    expect(
      find.text('How activity or a kg is counted changed in Settings.'),
      findsOne,
    );
    expect(find.textContaining('Target weight'), findsNothing);
  });

  Future<void> open(WidgetTester tester, _Store store) async {
    AdaptiveStore.settings.value = const AdaptiveSettings(adaptiveTarget: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdaptiveSettingsTile(store: store)),
      ),
    );
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expenditure-settings')));
    await tester.pumpAndSettle();
    final history = find.byKey(const ValueKey('check-in-history'));
    // Far down a lazy list: built only once scrolled to.
    await tester.scrollUntilVisible(
      history,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(history);
    await tester.pumpAndSettle();
  }

  testWidgets('newest first, with the change and an edited proposal', (
    tester,
  ) async {
    await open(
      tester,
      _Store([
        _record(5, 2600, 2100, 2100),
        _record(12, 2550, 2050, 2150),
        _record(19, 2560, 2150, 2150),
      ]),
    );

    final rows = tester
        .widgetList<ListTile>(
          find.descendant(
            of: find.byType(CheckInHistoryScreen),
            matching: find.byType(ListTile),
          ),
        )
        .map((t) => (t.key as ValueKey<String>).value)
        .toList();
    expect(rows, [
      'check-in-2026-10-19',
      'check-in-2026-10-12',
      'check-in-2026-10-05',
    ]);
    expect(find.text('2150 kcal'), findsNWidgets(2));
    expect(
      find.text('Oct 12, 2026 · expenditure 2550 kcal · proposed 2050 kcal'),
      findsOneWidget,
    );
    expect(find.text('+50 kcal'), findsOneWidget);
    expect(find.text('no change'), findsOneWidget);
    expect(find.text('Oct 5, 2026 · expenditure 2600 kcal'), findsOneWidget);
  });

  testWidgets('says when there are none yet', (tester) async {
    await open(tester, _Store([]));
    expect(find.textContaining('No check-ins yet'), findsOneWidget);
    // The first is due as soon as the target is on, not a week later.
    expect(
      find.textContaining('The first is ready on Home once the adaptive'),
      findsOneWidget,
    );
  });

  testWidgets(
    'the history at 200% text: nothing cut, the targets and contrast',
    (tester) async {
      await checkScreen(
        tester,
        CheckInHistoryScreen(
          store: _Store([
            _record(20, 2500, 2100, 2000),
            _record(13, 2480, 2050, 2050),
          ]),
        ),
      );
    },
  );

  testWidgets(
    'tappable rows at 200% text: nothing cut, the targets and contrast',
    (tester) async {
      await checkScreen(
        tester,
        CheckInHistoryScreen(
          store: _Store([
            _full(13, base: 2480, proposed: 2050, set: 2050),
            _full(20, base: 2500, proposed: 2100, set: 2000),
          ]),
        ),
      );
    },
  );
}
