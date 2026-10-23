import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_ui.dart';

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

void main() {
  tearDown(() => AdaptiveStore.settings.value = const AdaptiveSettings());

  Future<void> open(WidgetTester tester, _Store store) async {
    AdaptiveStore.settings.value = const AdaptiveSettings(adaptiveTarget: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdaptiveSettingsTile(store: store)),
      ),
    );
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('check-in-history')));
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
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.key as ValueKey<String>).value)
        .toList();
    expect(rows, [
      'check-in-2026-10-19',
      'check-in-2026-10-12',
      'check-in-2026-10-05',
    ]);
    expect(find.text('12 Oct 2026: 2150 kcal'), findsOneWidget);
    expect(
      find.text('Expenditure 2550 kcal · proposed 2050 kcal'),
      findsOneWidget,
    );
    expect(find.text('+50 kcal'), findsOneWidget);
    expect(find.text('no change'), findsOneWidget);
    expect(find.text('Expenditure 2600 kcal'), findsOneWidget);
  });

  testWidgets('says when there are none yet', (tester) async {
    await open(tester, _Store([]));
    expect(find.textContaining('No check-ins yet'), findsOneWidget);
  });
}
