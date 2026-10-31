// Fork-owned copy of test/features/home/presentation/widgets/dashboard_widget_test.dart (D23); upstream's later changes to it
// are ported by hand: fork/tools/upstream-copies.sh.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/kcal_goal_breakdown_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_breakdown_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/home/presentation/screens/nutrient_contributions_screen.dart';
import 'package:opennutritracker/fork/screens/home/dashboard_widget.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/kcal_goal_info_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:provider/provider.dart';

import '../../../fixture/intake_entity_fixtures.dart';
import '../../../fixture/user_entity_fixtures.dart';

class _FakeBreakdownUsecase extends Fake
    implements GetKcalGoalBreakdownUsecase {
  final KcalGoalBreakdownEntity breakdown;

  _FakeBreakdownUsecase(this.breakdown);

  @override
  Future<KcalGoalBreakdownEntity> getBreakdown() async => breakdown;
}

Widget _wrap(Widget child) {
  return ChangeNotifierProvider(
    create: (_) => EnergyUnitProvider(usesKilojoules: false),
    child: MaterialApp(
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  setUp(() {
    // The gauge navigates to KcalGoalInfoScreen, which pulls its usecase
    // from the locator when none is injected.
    locator.registerSingleton<GetKcalGoalBreakdownUsecase>(
      _FakeBreakdownUsecase(
        KcalGoalBreakdownEntity.compute(
          user: UserEntityFixtures.youngSedentaryMaleWantingToMaintainWeight,
          totalKcalActivities: 0,
        ),
      ),
    );
  });

  tearDown(() {
    GetIt.instance.reset();
  });

  DashboardWidget dashboardWidget({required double totalKcalLeft}) {
    return DashboardWidget(
      totalKcalSupplied: 2800,
      totalKcalBurned: 200,
      totalKcalDaily: 2500,
      totalKcalLeft: totalKcalLeft,
      totalCarbsIntake: 100,
      totalFatsIntake: 30,
      totalProteinsIntake: 60,
      totalCarbsGoal: 375,
      totalFatsGoal: 69,
      totalProteinsGoal: 93,
    );
  }

  testWidgets('left is the shown goal less the shown eaten', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(500, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _wrap(
        const DashboardWidget(
          totalKcalSupplied: 2896.6,
          totalKcalBurned: 0,
          totalKcalDaily: 3097.4,
          totalKcalLeft: 200.8,
          totalCarbsIntake: 100,
          totalFatsIntake: 30,
          totalProteinsIntake: 60,
          totalCarbsGoal: 375,
          totalFatsGoal: 69,
          totalProteinsGoal: 93,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('3097'), findsOneWidget);
    expect(find.text('2897'), findsOneWidget);
    // 3097 − 2897, as shown, though 200.8 is left
    expect(find.bySemanticsLabel(RegExp(r'^200 ')), findsWidgets);
    semantics.dispose();
  });

  testWidgets('at 2x the ring\'s figure and label stay inside its stroke', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: _wrap(dashboardWidget(totalKcalLeft: -1648)),
      ),
    );
    await tester.pumpAndSettle();
    final ring = tester.getRect(find.byType(CircularPercentIndicator));
    final inside = ring.deflate(10);
    for (final text
        in find
            .descendant(
              of: find.byType(CircularPercentIndicator),
              matching: find.byType(Text),
            )
            .evaluate()) {
      final rect = tester.getRect(find.byWidget(text.widget));
      expect(rect.left, greaterThanOrEqualTo(inside.left));
      expect(rect.right, lessThanOrEqualTo(inside.right));
    }
  });

  testWidgets(
    'kcal gauge uses the error color when intake exceeds the daily goal',
    (tester) async {
      await tester.pumpWidget(_wrap(dashboardWidget(totalKcalLeft: -300)));
      await tester.pumpAndSettle();

      final gauge = tester.widget<CircularPercentIndicator>(
        find.byType(CircularPercentIndicator),
      );

      expect(gauge.progressColor, ThemeData().colorScheme.error);
    },
  );

  testWidgets(
    'kcal gauge exposes a semantic tap action that opens the goal screen '
    '(regression: excludeSemantics stripped the GestureDetector tap, so '
    'screen readers announced a button that could not be activated)',
    (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      await tester.binding.setSurfaceSize(const Size(500, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrap(dashboardWidget(totalKcalLeft: 1900)));
      await tester.pumpAndSettle();

      final gauge = tester.widget<CircularPercentIndicator>(
        find.byType(CircularPercentIndicator),
      );
      expect(gauge.progressColor, ThemeData().colorScheme.primary);

      final gaugeFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.identifier == 'home-kcal-gauge',
      );
      expect(gaugeFinder, findsOneWidget);

      final node = tester.getSemantics(gaugeFinder);
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
        reason:
            'excludeSemantics drops the GestureDetector\'s tap action, '
            'so the Semantics node must register its own onTap',
      );

      // Activate the node the way TalkBack/VoiceOver do — via the semantic
      // action, not a pointer tap.
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pumpAndSettle();

      expect(find.byType(KcalGoalInfoScreen), findsOneWidget);

      semanticsHandle.dispose();
    },
  );

  testWidgets(
    'tapping a macro tile lists the foods its total came from (#1266)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(
          DashboardWidget(
            totalKcalSupplied: 2800,
            totalKcalBurned: 200,
            totalKcalDaily: 2500,
            totalKcalLeft: 1900,
            totalCarbsIntake: 100,
            totalFatsIntake: 30,
            totalProteinsIntake: 60,
            totalCarbsGoal: 375,
            totalFatsGoal: 69,
            totalProteinsGoal: 93,
            intakes: [
              intakeOf('Oats', 80, protein100: 13, carbs100: 60),
              intakeOf('Chicken breast', 150, protein100: 23),
              intakeOf('Apple', 150, carbs100: 12),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.identifier == 'home-macro-protein',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NutrientContributionsScreen), findsOneWidget);
      // the foods page's summary and title
      expect(find.text('60'), findsOneWidget);
      expect(find.text('of 93 g protein'), findsOneWidget);
      expect(find.text("Today's foods"), findsOneWidget);
      expect(find.text('Apple'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Chicken breast')).dy,
        lessThan(tester.getTopLeft(find.text('Oats')).dy),
      );
      expect(find.text('35 g'), findsOneWidget);
    },
  );
}
