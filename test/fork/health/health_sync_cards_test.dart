import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/health/health_sync_cards.dart';
import 'package:opennutritracker/fork/health/weight_import_ui.dart';
import 'package:opennutritracker/generated/l10n.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: const [S.delegate],
  supportedLocales: S.supportedLocales,
  home: Scaffold(body: ListView(children: [child])),
);

HealthImportTile _weightTile({
  required Future<bool> Function() isOn,
  required Future<int?> Function() turnOn,
  required Future<void> Function() turnOff,
}) => HealthImportTile(
  available: true,
  icon: Icons.monitor_weight_outlined,
  identifier: 'health-sync-weight',
  title: 'Weight in',
  detail: 'from your smart scale',
  what: 'weight',
  disclosureTitle: 'Import weight?',
  disclosure: 'OpenBite will read your weight.',
  offMessage: 'Weight import off',
  done: (days) => 'Imported $days days',
  isOn: isOn,
  turnOn: turnOn,
  turnOff: turnOff,
);

void main() {
  testWidgets('an import is a card: a box to tick, its permission asked', (
    tester,
  ) async {
    var on = false;
    var asked = 0;
    await tester.pumpWidget(
      _app(
        _weightTile(
          isOn: () async => on,
          turnOn: () async {
            asked++;
            on = true;
            return 3;
          },
          turnOff: () async => on = false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text('Weight in'), findsOneWidget);
    expect(find.text('from your smart scale'), findsOneWidget);

    await tester.tap(find.bySemanticsIdentifier('health-sync-weight'));
    await tester.pumpAndSettle();
    expect(asked, 0, reason: 'the disclosure comes before the permission');
    expect(find.text('Import weight?'), findsOneWidget);
    expect(find.text('OpenBite will read your weight.'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(asked, 1);
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isTrue,
    );
    expect(find.text('Imported 3 days'), findsOneWidget);
  });

  testWidgets('Cancel on the disclosure asks nothing and leaves it off', (
    tester,
  ) async {
    var asked = 0;
    await tester.pumpWidget(
      _app(
        _weightTile(
          isOn: () async => false,
          turnOn: () async {
            asked++;
            return 3;
          },
          turnOff: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('health-sync-weight'));
    await tester.pumpAndSettle();
    // A tap outside is not consent either.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Import weight?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(asked, 0);
    expect(find.text('Import weight?'), findsNothing);
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a card that can not change is greyed, not tappable', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const HealthSyncCard(
          identifier: 'health-sync-auto-import',
          icon: Icons.directions_run_rounded,
          title: 'Workouts in',
          detail: 'Burned energy adds to your budget',
          value: false,
          onChanged: null,
        ),
      ),
    );
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).onChanged,
      isNull,
    );
  });

  testWidgets('the footer: the last import, and Import now', (tester) async {
    var imported = 0;
    await tester.pumpWidget(
      _app(
        HealthSyncFooter(
          lastImport: 'Last import Oct 25, 07:12',
          onImport: () => imported++,
        ),
      ),
    );
    expect(find.text('Last import Oct 25, 07:12'), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier('health-sync-import-now'));
    expect(imported, 1);
    expect(
      tester.getSize(find.byType(FilledButton)).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('the heading says what to pick', (tester) async {
    await tester.pumpWidget(_app(const HealthSyncHeading()));
    expect(find.text('What should sync?'), findsOneWidget);
  });

  testWidgets('a greyed Import now says why', (tester) async {
    await tester.pumpWidget(
      _app(
        const HealthSyncFooter(
          lastImport: 'No workouts imported yet',
          onImport: null,
          why: 'Tick Workouts in to import and set the credit',
        ),
      ),
    );
    expect(
      find.text('Tick Workouts in to import and set the credit'),
      findsOneWidget,
    );
  });
}
