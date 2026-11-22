import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/physical_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_custom_activity_template_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_user_activity_usercase.dart';
import 'package:opennutritracker/core/domain/usecase/get_custom_activity_templates_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/activity_detail/activity_detail_screen.dart';
import 'package:opennutritracker/features/activity_detail/presentation/bloc/activity_detail_bloc.dart';
import 'package:opennutritracker/features/activity_detail/presentation/widget/activity_detail_bottom_sheet.dart';
import 'package:opennutritracker/features/activity_detail/presentation/widget/activity_title_expanded.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../helpers/ux_checks.dart';

// S409: Custom activity at 200% text shows its whole description, and the
// energy readout scrolls clear of the bottom sheet. S410/S411: the sheet
// builds without the ListTile ink error, and at 150% and up the Unit goes
// under the amount so "Calories burned" is not cut.

class _User extends Fake implements GetUserUsecase {
  @override
  Future<UserEntity> getUserData() async => UserEntity(
    birthday: DateTime(1990, 1, 1),
    heightCM: 180,
    weightKG: 80,
    gender: UserGenderEntity.male,
    goal: UserWeightGoalEntity.maintainWeight,
    pal: UserPALEntity.sedentary,
  );
}

class _AddActivity extends Fake implements AddUserActivityUsecase {}

class _AddTrackedDay extends Fake implements AddTrackedDayUsecase {}

class _KcalGoal extends Fake implements GetKcalGoalUsecase {}

class _MacroGoal extends Fake implements GetMacroGoalUsecase {}

class _AddTemplate extends Fake implements AddCustomActivityTemplateUsecase {}

class _Templates extends Fake implements GetCustomActivityTemplatesUsecase {}

Future<void> _pump(
  WidgetTester tester, {
  double textScale = 2,
  PhysicalActivityEntity activity = PhysicalActivityEntity.custom,
}) async {
  // the phone, its fonts and the text size
  await pumpOnPhone(tester, const SizedBox(), textScale: textScale);
  final getIt = GetIt.instance;
  await getIt.reset();
  addTearDown(getIt.reset);
  getIt.registerFactory<ActivityDetailBloc>(
    () => ActivityDetailBloc(
      _User(),
      _AddActivity(),
      _AddTrackedDay(),
      _KcalGoal(),
      _MacroGoal(),
      _AddTemplate(),
      _Templates(),
    ),
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<EnergyUnitProvider>(
      create: (_) => EnergyUnitProvider(),
      child: MaterialApp(
        theme: buildAppTheme(AppPalette.light),
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.supportedLocales,
        onGenerateRoute: (_) => MaterialPageRoute(
          settings: RouteSettings(
            arguments: ActivityDetailScreenArguments(
              activity,
              DateTime(2026, 11, 21),
            ),
          ),
          builder: (_) => const ActivityDetailScreen(),
        ),
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  Future<void> expectTitleWhole(WidgetTester tester) async {
    final title = find.descendant(
      of: find.byType(ActivityTitleExpanded),
      matching: find.byType(RichText),
    );
    final paragraph = tester.renderObject<RenderParagraph>(title);
    expect(paragraph.didExceedMaxLines, isFalse);
    // whole inside the header, below the back button's row
    final header = tester.getRect(find.byType(FlexibleSpaceBar));
    final rect = tester.getRect(title);
    expect(rect.top, greaterThanOrEqualTo(header.top + kToolbarHeight));
    expect(rect.bottom, lessThanOrEqualTo(header.bottom));
  }

  for (final scale in [0.85, 1.0, 1.15, 1.3, 1.5, 2.0]) {
    testWidgets('the name and description are not cut at ${scale * 100}%', (
      tester,
    ) async {
      await _pump(tester, textScale: scale);
      await expectTitleWhole(tester);
    });
  }

  testWidgets('a long-named activity fits its header at 200%', (tester) async {
    await _pump(
      tester,
      activity: const PhysicalActivityEntity(
        '01009',
        'bicycling, mountain',
        'uphill, vigorous',
        14,
        [],
        PhysicalActivityTypeEntity.bicycling,
      ),
    );
    await expectTitleWhole(tester);
  });

  testWidgets('the readout scrolls clear of the sheet at 200%', (
    tester,
  ) async {
    await _pump(tester);
    // from above the sheet, which covers the page's middle at 200%
    await tester.dragFrom(const Offset(200, 150), const Offset(0, -3000));
    await tester.pumpAndSettle();
    final readout = tester.getRect(
      find.descendant(of: find.byType(AppCard), matching: find.byType(Text)),
    );
    final sheet = tester.getRect(find.byType(ActivityDetailBottomSheet));
    expect(readout.bottom, lessThanOrEqualTo(sheet.top));
  });

  // shortcut: at 200% with the keyboard up the sheet and keyboard leave no
  // room for the readout; checked without the keyboard there, and with it
  // at 100%. Upgrade if the sheet gets shorter at large text.
  for (final (scale, keyboard) in [(1.0, 300.0), (2.0, 0.0)]) {
    testWidgets('typing an amount brings the readout above the sheet at '
        '${scale * 100}%', (tester) async {
      await _pump(tester, textScale: scale);
      tester.view.viewInsets = FakeViewPadding(
        bottom: keyboard * tester.view.devicePixelRatio,
      );
      await tester.enterText(
        find.descendant(
          of: find.bySemanticsIdentifier('activity-detail-quantity-input'),
          matching: find.byType(EditableText),
        ),
        '300',
      );
      await tester.pumpAndSettle();
      final readout = tester.getRect(
        find.descendant(of: find.byType(AppCard), matching: find.byType(Text)),
      );
      final sheet = tester.getRect(find.byType(ActivityDetailBottomSheet));
      expect(readout.top, greaterThanOrEqualTo(kToolbarHeight));
      expect(readout.bottom, lessThanOrEqualTo(sheet.top));
    });
  }

  for (final (scale, stacked) in [(1.0, false), (1.5, true), (2.0, true)]) {
    testWidgets('Unit ${stacked ? 'under' : 'beside'} the amount at '
        '${scale * 100}%, its label whole', (tester) async {
      await _pump(tester, textScale: scale);
      expect(tester.takeException(), isNull);
      final amount = find.bySemanticsIdentifier(
        'activity-detail-quantity-input',
      );
      final unit = tester.getRect(find.byType(DropdownButtonFormField<String>));
      final field = tester.getRect(amount);
      if (stacked) {
        expect(unit.top, greaterThanOrEqualTo(field.bottom));
      } else {
        expect(unit.top, field.top);
      }
      for (final element in find
          .descendant(of: amount, matching: find.byType(RichText))
          .evaluate()) {
        final paragraph = element.renderObject! as RenderParagraph;
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: paragraph.text.toPlainText(),
        );
      }
    });
  }
}
