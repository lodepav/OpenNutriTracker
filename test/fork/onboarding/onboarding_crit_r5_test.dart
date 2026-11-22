import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/onboarding/domain/entity/user_activity_selection_entity.dart';
import 'package:opennutritracker/features/onboarding/domain/entity/user_gender_selection_entity.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/onboarding_activity_page_body.dart';
import 'package:opennutritracker/features/settings/domain/export_import_failure.dart';
import 'package:opennutritracker/fork/backup/onboarding_restore.dart';
import 'package:opennutritracker/fork/goal/goal_planner.dart';
import 'package:opennutritracker/fork/goal/planner_screen.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/screens/onboarding/onboarding_about_you_page_body.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../helpers/test_l10n.dart';

class _FailingRestore extends OnboardingRestore {
  final Object error;
  _FailingRestore(this.error);

  @override
  Future<bool> importBackup() async => throw error;
}

Widget _app(Widget home) => ChangeNotifierProvider(
  create: (_) => EnergyUnitProvider(usesKilojoules: false),
  child: MaterialApp(
    localizationsDelegates: const [
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: S.supportedLocales,
    home: home,
  ),
);

/// The first-run critique of 2026-11-22, round 5.
void main() {
  testWidgets('the activity cards are one group with the chosen one checked', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: OnboardingActivityPageBody(
            setButtonContent: (_, _) {},
            initialActivity: UserActivitySelectionEntity.active,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(
        find.bySemanticsIdentifier('onboarding-activity-active'),
      ),
      isSemantics(
        isInMutuallyExclusiveGroup: true,
        hasCheckedState: true,
        isChecked: true,
      ),
    );
    expect(
      tester.getSemantics(
        find.bySemanticsIdentifier('onboarding-activity-low'),
      ),
      isSemantics(
        isInMutuallyExclusiveGroup: true,
        hasCheckedState: true,
        isChecked: false,
      ),
    );
  });

  testWidgets('an incomplete birthday keeps the chosen gender', (tester) async {
    UserGenderSelectionEntity? gender;
    bool? active;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: OnboardingAboutYouPageBody(
            setPageContent: (a, g, _, _) {
              active = a;
              gender = g;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ChoiceChip).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '12');
    await tester.pumpAndSettle();
    expect(active, isFalse);
    expect(gender, UserGenderSelectionEntity.genderMale);
  });

  testWidgets('a restore that fails for a known reason says which', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: RestoreBackupButton(
            acceptedPolicy: true,
            acceptedDataCollection: false,
            restore: _FailingRestore(
              const ExportImportFailure(
                ExportImportFailureReason.unreadableOrWrongFormat,
                'test',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('fork-onboarding-restore')));
    await tester.pumpAndSettle();
    expect(find.text(l10nEn.exportImportErrorUnreadableLabel), findsOneWidget);
  });

  testWidgets('a planner save that throws leaves Save on and says so', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final hold = GoalDraft(
      kind: PhaseKind.maintain,
      startKg: 80,
      start: DateTime(2026, 10, 5),
      maintainWeeks: 8,
    ).toPlan();
    await tester.pumpWidget(
      _app(
        GoalPlannerScreen(
          setup: PlannerSetup(
            nowKg: 80,
            unit: BodyWeightUnit.kg,
            expenditureKcal: 2600,
            bodyFatPercent: 22,
            running: hold,
          ),
          draft: GoalDraft.of(hold, 80).copyWith(startKg: 80),
          editing: hold,
          today: DateTime(2026, 10, 20),
          onStart: (_) async => throw StateError('store down'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save plan'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save plan'))
          .onPressed,
      isNotNull,
    );
    expect(find.textContaining('Not saved'), findsOneWidget);
  });
}
