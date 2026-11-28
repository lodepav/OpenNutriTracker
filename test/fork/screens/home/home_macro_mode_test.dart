import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/fork/adaptive/activity_credit.dart';
import 'package:opennutritracker/fork/display/display_prefs.dart';
import 'package:opennutritracker/fork/screens/home/dashboard_widget.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

Widget _app() => ChangeNotifierProvider(
  create: (_) => EnergyUnitProvider(usesKilojoules: false),
  child: MaterialApp(
    localizationsDelegates: const [
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: S.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        child: DashboardWidget(
          totalKcalSupplied: 1500,
          totalKcalBurned: 0,
          totalKcalDaily: 2500,
          totalKcalLeft: 1000,
          totalCarbsIntake: 100,
          totalFatsIntake: 30,
          totalProteinsIntake: 120,
          totalCarbsGoal: 375,
          totalFatsGoal: 69,
          totalProteinsGoal: 93,
          loadCredit: () async => ActivityCredit.added,
          homeLoads: const Stream.empty(),
        ),
      ),
    ),
  ),
);

Finder _macro(String id) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.identifier == id,
);

double? _bar(WidgetTester tester, String id) => tester
    .widget<LinearProgressIndicator>(
      find.descendant(
        of: _macro(id),
        matching: find.byType(LinearProgressIndicator),
      ),
    )
    .value;

String? _label(WidgetTester tester, String id) =>
    tester.widget<Semantics>(_macro(id)).properties.label;

void main() {
  tearDown(() => DisplayPrefs.homeShowsEaten.value = false);

  testWidgets('on Left the macros say what is left and their bars drain', (
    tester,
  ) async {
    DisplayPrefs.homeShowsEaten.value = false;
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('39 g left', findRichText: true), findsOneWidget);
    expect(_bar(tester, 'home-macro-fat'), closeTo(39 / 69, 1e-9));
    expect(_label(tester, 'home-macro-fat'), 'Fat: 39 g left');
    // over the goal: nothing left to drain
    expect(find.text('27 g over', findRichText: true), findsOneWidget);
    expect(_bar(tester, 'home-macro-protein'), 0);
    expect(_label(tester, 'home-macro-protein'), 'Protein: 27 g over');
  });

  testWidgets('on Eaten the macros say what was eaten and their bars fill', (
    tester,
  ) async {
    DisplayPrefs.homeShowsEaten.value = true;
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('30 of 69 g', findRichText: true), findsOneWidget);
    expect(_bar(tester, 'home-macro-fat'), closeTo(30 / 69, 1e-9));
    expect(_label(tester, 'home-macro-fat'), 'Fat: 30 of 69 g eaten');
    expect(
      find.text('120 of 93 g', findRichText: true),
      findsOneWidget,
    );
    expect(_bar(tester, 'home-macro-protein'), 1);
    expect(
      _label(tester, 'home-macro-protein'),
      'Protein: 120 of 93 g eaten, 27 g over',
    );
  });
}
