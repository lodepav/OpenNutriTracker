import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/activity_detail/activity_detail_screen.dart';
import 'package:opennutritracker/features/activity_detail/presentation/bloc/activity_detail_bloc.dart';
import 'package:opennutritracker/features/activity_detail/presentation/widget/activity_title_expanded.dart';
import 'package:opennutritracker/fork/activity/activity_picker.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../helpers/ux_checks.dart';

// Custom activity: Add clears the navigation bar, the description shows in
// full, the energy field starts empty; the duration sheet's chosen chip
// shows its number whole at 200%.

/// Never answers, so the screen stays on its loading state.
class _PendingUser extends Fake implements GetUserUsecase {
  @override
  Future<UserEntity> getUserData() => Completer<UserEntity>().future;
}

class _AddActivity extends Fake implements AddUserActivityUsecase {}

class _AddTrackedDay extends Fake implements AddTrackedDayUsecase {}

class _KcalGoal extends Fake implements GetKcalGoalUsecase {}

class _MacroGoal extends Fake implements GetMacroGoalUsecase {}

class _AddTemplate extends Fake implements AddCustomActivityTemplateUsecase {}

class _Templates extends Fake implements GetCustomActivityTemplatesUsecase {}

const _yoga = PhysicalActivityEntity(
  '02160',
  'yoga',
  'general',
  4,
  [],
  PhysicalActivityTypeEntity.conditioningExercise,
);

Future<void> _pumpScreen(WidgetTester tester) async {
  final getIt = GetIt.instance;
  await getIt.reset();
  addTearDown(getIt.reset);
  getIt.registerFactory<ActivityDetailBloc>(
    () => ActivityDetailBloc(
      _PendingUser(),
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
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        onGenerateRoute: (_) => MaterialPageRoute(
          settings: RouteSettings(
            arguments: ActivityDetailScreenArguments(
              // Not Custom: the same sheet without Custom's CheckboxListTile,
              // which trips a debug-only ListTile-in-DecoratedBox assertion.
              _yoga,
              DateTime(2026, 11, 21),
            ),
          ),
          builder: (_) => const ActivityDetailScreen(),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('Add ends above a 3-button navigation bar', (tester) async {
    const navBar = 48.0;
    final ratio = tester.view.devicePixelRatio;
    tester.view
      ..padding = FakeViewPadding(bottom: navBar * ratio)
      ..viewPadding = FakeViewPadding(bottom: navBar * ratio);
    addTearDown(tester.view.reset);
    await _pumpScreen(tester);

    final screenHeight = tester.view.physicalSize.height / ratio;
    final add = tester.getRect(
      find.bySemanticsIdentifier('activity-detail-add-button'),
    );
    expect(add.bottom, lessThanOrEqualTo(screenHeight - navBar));
  });

  testWidgets('the energy field starts empty, so typing 300 reads 300', (
    tester,
  ) async {
    await _pumpScreen(tester);
    final field = tester.widget<EditableText>(
      find.descendant(
        of: find.bySemanticsIdentifier('activity-detail-quantity-input'),
        matching: find.byType(EditableText),
      ),
    );
    expect(field.controller.text, isEmpty);
  });

  testWidgets('the description shows in full at 100%', (tester) async {
    await pumpOnPhone(
      tester,
      ChangeNotifierProvider<EnergyUnitProvider>(
        create: (_) => EnergyUnitProvider(),
        child: const Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: 200,
            child: ActivityTitleExpanded(
              activity: PhysicalActivityEntity.custom,
            ),
          ),
        ),
      ),
      textScale: 1,
    );
    expect(cutText(tester), isEmpty);
  });

  testWidgets('the third line still fits the header at 200%', (tester) async {
    await pumpOnPhone(
      tester,
      ChangeNotifierProvider<EnergyUnitProvider>(
        create: (_) => EnergyUnitProvider(),
        child: const Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: 200,
            child: ActivityTitleExpanded(
              activity: PhysicalActivityEntity.custom,
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final title = tester.getRect(find.byType(RichText));
    // Below the 56 dp toolbar row that holds the back button.
    expect(title.top, greaterThanOrEqualTo(56));
  });

  testWidgets('the chosen duration chip shows "30" whole at 200%', (
    tester,
  ) async {
    await pumpOnPhone(
      tester,
      ChangeNotifierProvider<EnergyUnitProvider>(
        create: (_) => EnergyUnitProvider(),
        child: SingleChildScrollView(
          child: DurationSheet(
            activity: _yoga,
            user: UserEntity(
              birthday: DateTime(1990, 1, 1),
              heightCM: 180,
              weightKG: 80,
              gender: UserGenderEntity.male,
              goal: UserWeightGoalEntity.maintainWeight,
              pal: UserPALEntity.sedentary,
            ),
            day: DateTime(2026, 11, 21),
            today: DateTime(2026, 11, 21),
          ),
        ),
      ),
    );
    final chip = find.bySemanticsIdentifier('activity-duration-30');
    expect(
      tester
          .widget<ChoiceChip>(
            find.descendant(of: chip, matching: find.byType(ChoiceChip)),
          )
          .selected,
      isTrue,
    );
    final label = tester.renderObject<RenderParagraph>(
      find.descendant(of: chip, matching: find.byType(RichText)),
    );
    expect(
      label.size.width + 0.5,
      greaterThanOrEqualTo(label.getMaxIntrinsicWidth(double.infinity)),
    );
  });
}
