import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/profile_entity.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/profile_switcher_sheet.dart';
import 'package:opennutritracker/fork/profile/profiles_view.dart';
import 'package:opennutritracker/generated/l10n.dart';

// Seams S301 and S302: the delete confirm names the profile and what goes
// with it; Add profile waits for a name; one day logged is singular.

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: const [
    S.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: S.supportedLocales,
  home: Scaffold(body: child),
);

Future<void> _tapOpen(
  WidgetTester tester,
  Future<void> Function(BuildContext) open,
) async {
  await tester.pumpWidget(
    _app(
      Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => open(context),
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('one day logged is singular', (tester) async {
    final alex = ProfileEntity(
      id: 'alex',
      name: 'Alex',
      createdAt: DateTime(2026, 3, 2),
      boxSuffix: '',
    );
    await tester.pumpWidget(
      _app(
        ProfilesView(
          profiles: [alex],
          activeId: 'alex',
          stats: {
            'alex': (goal: null, kcalGoal: null, trendKg: null, daysLogged: 1),
          },
          weightUnit: BodyWeightUnit.kg,
          onEdit: (_) {},
          onSwitch: (_) {},
          onDelete: (_) {},
        ),
      ),
    );
    expect(find.text('day logged'), findsOneWidget);
    expect(find.text('days logged'), findsNothing);
  });

  testWidgets('the delete confirm names the profile and its days', (
    tester,
  ) async {
    bool? result;
    await _tapOpen(tester, (context) async {
      result = await confirmDeleteProfile(
        context,
        name: 'Alex Demo',
        daysLogged: 365,
      );
    });
    expect(find.text('Delete Alex Demo?'), findsOneWidget);
    expect(
      find.text(
        'Its 365 days of logged food, weigh-ins and recipes are deleted for good.',
      ),
      findsOneWidget,
    );
    final delete = find.widgetWithText(FilledButton, 'Delete');
    final context = tester.element(delete);
    expect(
      tester.widget<FilledButton>(delete).style!.backgroundColor!.resolve({}),
      Theme.of(context).colorScheme.error,
    );
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('without its days the confirm says it generally', (tester) async {
    await _tapOpen(
      tester,
      (context) => confirmDeleteProfile(context, name: 'Sam'),
    );
    expect(find.text('Delete Sam?'), findsOneWidget);
    expect(
      find.text('Its logged food, weigh-ins and recipes are deleted for good.'),
      findsOneWidget,
    );
  });

  testWidgets('Add profile stays off until a name is typed', (tester) async {
    await _tapOpen(tester, showAddProfileDialog);
    TextButton add() => tester.widget<TextButton>(
      find.descendant(
        of: find.bySemanticsIdentifier('profile-add-confirm'),
        matching: find.byType(TextButton),
      ),
    );
    expect(add().onPressed, isNull);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(add().onPressed, isNull);
    await tester.enterText(find.byType(TextField), ' Sam ');
    await tester.pump();
    expect(add().onPressed, isNotNull);
  });
}
