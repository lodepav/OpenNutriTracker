import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/kcal_goal_breakdown_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/usecase/delete_all_user_data_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_breakdown_usecase.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/onboarding/presentation/onboarding_intro_page_body.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/onboarding_overview_page_body.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/export_import_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/kcal_goal_info_screen.dart';
import 'package:opennutritracker/fork/display/contrast.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../helpers/test_l10n.dart';
import '../../helpers/ux_checks.dart';

/// The audit of the six uncovered page groups, round 4 (2026-11-22).

const _yellow = Color(0xFFFDD835);
final _light = AppPalette.light.withAccent(_yellow);

Widget _app(Widget home) => ChangeNotifierProvider<EnergyUnitProvider>(
  create: (_) => EnergyUnitProvider(usesKilojoules: false),
  child: MaterialApp(
    theme: buildAppTheme(_light),
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

class _Breakdown extends Fake implements GetKcalGoalBreakdownUsecase {
  final KcalGoalBreakdownEntity breakdown;
  _Breakdown(this.breakdown);

  @override
  Future<KcalGoalBreakdownEntity> getBreakdown() async => breakdown;
}

/// An import whose picker is still open.
class _PendingImport extends Fake implements ExportImportBloc {
  final _states = StreamController<ExportImportState>.broadcast();

  void finish() => _states.add(ExportImportInitial());

  @override
  Stream<ExportImportState> get stream => _states.stream;

  @override
  void add(ExportImportEvent event) {}

  @override
  Future<void> close() => _states.close();
}

/// A demo wipe that has not finished.
class _PendingWipe extends Fake implements DeleteAllUserDataUsecase {
  final done = Completer<void>();

  @override
  Future<void> deleteAll() => done.future;
}

KcalGoalBreakdownEntity _breakdown() {
  final yesterday = DateTime.now().subtract(const Duration(days: 1));
  return KcalGoalBreakdownEntity.compute(
    user: UserEntity(
      birthday: DateTime(yesterday.year - 30, yesterday.month, yesterday.day),
      heightCM: 180,
      weightKG: 80,
      gender: UserGenderEntity.male,
      goal: UserWeightGoalEntity.loseWeight,
      pal: UserPALEntity.active,
    ),
    userKcalAdjustment: 0,
    totalKcalActivities: 0,
  );
}

Color _colourOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!.color!;

void main() {
  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'OpenBite',
      packageName: 'test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('the calorie goal figure on a yellow accent', () {
    testWidgets('Overview reads at 4.5:1 on the canvas', (tester) async {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: SingleChildScrollView(
              child: OnboardingOverviewPageBody(
                setButtonActive: (_) {},
                calorieGoalDayString: '2345',
                carbsGoalString: '250',
                fatGoalString: '70',
                proteinGoalString: '150',
              ),
            ),
          ),
        ),
      );
      expect(
        contrastRatio(_colourOf(tester, '2345'), _light.canvas),
        greaterThanOrEqualTo(4.5),
      );
    });

    testWidgets('How your goal is calculated reads at 4.5:1 on its card', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 4500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final breakdown = _breakdown();
      await tester.pumpWidget(
        _app(
          KcalGoalInfoScreen(usecase: _Breakdown(breakdown), equations: true),
        ),
      );
      await tester.pumpAndSettle();
      // The figure is the last text in the row the result label starts.
      final row = find.ancestor(
        of: find.text(l10nEn.kcalGoalInfoResultSection),
        matching: find.byType(Row),
      );
      final colour = tester
          .widgetList<Text>(
            find.descendant(of: row.first, matching: find.byType(Text)),
          )
          .last
          .style!
          .color!;
      expect(contrastRatio(colour, _light.surface), greaterThanOrEqualTo(4.5));
    });
  });

  group('Restore a backup and Try demo', () {
    Finder demo() =>
        find.widgetWithText(OutlinedButton, l10nEn.onboardingTryDemoLabel);
    Finder restore() => find.byKey(const Key('fork-onboarding-restore'));
    bool live(WidgetTester tester, Finder button) =>
        tester.widget<OutlinedButton>(button).onPressed != null;

    Future<void> pumpIntro(WidgetTester tester) => pumpOnPhone(
      tester,
      OnboardingIntroPageBody(
        setPageContent: (_, _) {},
        initialAcceptedPolicy: true,
      ),
      textScale: 1,
    );

    testWidgets('Try demo is off while a restore runs', (tester) async {
      final bloc = _PendingImport();
      locator.registerSingleton<ExportImportBloc>(bloc);
      addTearDown(() => locator.unregister<ExportImportBloc>());
      await pumpIntro(tester);
      await tester.ensureVisible(restore());
      await tester.tap(restore());
      await tester.pump();
      expect(live(tester, restore()), isFalse);
      expect(live(tester, demo()), isFalse);

      bloc.finish();
      await tester.pump();
      await tester.pump();
      expect(live(tester, restore()), isTrue);
      expect(live(tester, demo()), isTrue);
    });

    testWidgets('Restore a backup is off while the demo seeds', (tester) async {
      final wipe = _PendingWipe();
      locator.registerSingleton<DeleteAllUserDataUsecase>(wipe);
      addTearDown(() => locator.unregister<DeleteAllUserDataUsecase>());
      await pumpIntro(tester);
      await tester.ensureVisible(demo());
      await tester.tap(demo());
      await tester.pump();
      expect(live(tester, demo()), isFalse);
      expect(live(tester, restore()), isFalse);

      // The seed fails past the wipe (nothing else is registered), which
      // hands the page back.
      wipe.done.complete();
      await tester.pump();
      await tester.pump();
      expect(live(tester, demo()), isTrue);
      expect(live(tester, restore()), isTrue);
    });
  });
}
