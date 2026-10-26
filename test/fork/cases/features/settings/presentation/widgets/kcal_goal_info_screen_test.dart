// Fork cases moved out of test/features/settings/presentation/widgets/kcal_goal_info_screen_test.dart (they test the fork's changes).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/calories_profile_entity.dart';
import 'package:opennutritracker/core/domain/entity/kcal_goal_breakdown_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_breakdown_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/kcal_goal_info_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';
import '../../../../../../helpers/test_l10n.dart';

/// Renders the transparency screen against breakdowns computed by the real
/// [KcalGoalBreakdownEntity.compute] and asserts the *displayed strings*
/// equal independently hand-computed values. This pins the whole chain —
/// math, formatting, and rounding conventions (truncation, matching the
/// dashboard) — so the screen cannot silently drift from the numbers the
/// rest of the app shows.
class _FakeBreakdownUsecase extends Fake
    implements GetKcalGoalBreakdownUsecase {
  final KcalGoalBreakdownEntity breakdown;

  _FakeBreakdownUsecase(this.breakdown);

  @override
  Future<KcalGoalBreakdownEntity> getBreakdown() async => breakdown;
}

UserEntity _buildUser({
  UserGenderEntity gender = UserGenderEntity.male,
  CaloriesProfileEntity? caloriesProfile,
  UserWeightGoalEntity goal = UserWeightGoalEntity.loseWeight,
  UserPALEntity pal = UserPALEntity.active,
  double? weeklyWeightGoalKg,
  double? targetWeightKg,
  bool taperEnabled = false,
  double weightKG = 80.0,
}) {
  // Yesterday (not `day - 1`) so the date stays valid on the 1st of the
  // month; captured once so components can't straddle a midnight rollover.
  final yesterday = DateTime.now().subtract(const Duration(days: 1));
  return UserEntity(
    birthday: DateTime(yesterday.year - 30, yesterday.month, yesterday.day),
    heightCM: 180.0,
    weightKG: weightKG,
    gender: gender,
    goal: goal,
    pal: pal,
    caloriesProfile: caloriesProfile,
    weeklyWeightGoalKg: weeklyWeightGoalKg,
    targetWeightKg: targetWeightKg,
    caloriesTaperEnabled: taperEnabled,
  );
}

Widget _wrap(
  KcalGoalBreakdownEntity breakdown, {
  bool usesKilojoules = false,
  bool equations = true,
}) {
  return ChangeNotifierProvider(
    create: (_) => EnergyUnitProvider(usesKilojoules: usesKilojoules),
    child: MaterialApp(
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.supportedLocales,
      // these tests read the page of every step
      home: KcalGoalInfoScreen(
        usecase: _FakeBreakdownUsecase(breakdown),
        equations: equations,
      ),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  KcalGoalBreakdownEntity breakdown, {
  bool usesKilojoules = false,
  bool equations = true,
}) async {
  // Tall viewport so the lazy ListView inflates every card — the tests
  // assert content across the whole screen, including the last cards.
  tester.view.physicalSize = const Size(1200, 4500);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _wrap(breakdown, usesKilojoules: usesKilojoules, equations: equations),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the overview', () {
    KcalGoalBreakdownEntity breakdown() => KcalGoalBreakdownEntity.compute(
      user: _buildUser(),
      userKcalAdjustment: 150,
      totalKcalActivities: 320,
    );

    testWidgets('three steps add up to the goal, each with its math', (
      tester,
    ) async {
      await _pump(tester, breakdown(), equations: false);

      expect(find.text("Today's goal"), findsOneWidget);
      expect(find.textContaining('3134', findRichText: true), findsOneWidget);
      expect(find.text('3164 kcal'), findsOneWidget);
      // The weight goal's −500 and the own +150 are one step.
      expect(find.text('−350 kcal'), findsOneWidget);
      expect(find.text('+320 kcal'), findsOneWidget);

      expect(find.text('1.27'), findsNothing);
      await tester.tap(find.text('Show the math').first);
      await tester.pumpAndSettle();
      expect(find.text('1.27'), findsOneWidget);
    });

    testWidgets('The equations opens the page of every step', (tester) async {
      await _pump(tester, breakdown(), equations: false);
      expect(find.text(l10nEn.kcalGoalInfoIntro), findsNothing);

      await tester.tap(find.byKey(const Key('goal-equations')));
      await tester.pumpAndSettle();
      expect(find.text(l10nEn.kcalGoalInfoIntro), findsOneWidget);
    });
  });
}
