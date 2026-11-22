import 'package:flutter/material.dart';
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
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/activity_detail/activity_detail_screen.dart';
import 'package:opennutritracker/features/add_activity/presentation/widgets/quick_add_activity_bottom_sheet.dart';
import 'package:opennutritracker/features/activity_detail/presentation/bloc/activity_detail_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import 'package:opennutritracker/fork/activity/entry_hints.dart';

import '../../helpers/ux_checks.dart';

// G2-24: Quick add and Custom activity stay two ways in, with the same
// field names, units and hints, and a line each saying when to use it.

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

const _shared = [
  'Name (optional)',
  'e.g. Evening bike commute',
  'Energy burned',
  'e.g. 250',
];

void main() {
  testWidgets('Custom activity names its fields as Quick add does', (
    tester,
  ) async {
    await _pump(tester, textScale: 1);
    for (final text in _shared) {
      expect(find.textContaining(text), findsWidgets, reason: text);
    }
    expect(find.text(customActivityWhen), findsOneWidget);
    // the unit beside the field, as Quick add's label names it
    expect(find.text('kcal'), findsWidgets);
  });

  testWidgets('Quick add names its fields as Custom activity does', (
    tester,
  ) async {
    await pumpOnPhone(
      tester,
      ChangeNotifierProvider<EnergyUnitProvider>(
        create: (_) => EnergyUnitProvider(),
        child: QuickAddActivityBottomSheet(day: DateTime(2026, 11, 22)),
      ),
      textScale: 1,
    );
    for (final text in _shared) {
      expect(find.textContaining(text), findsWidgets, reason: text);
    }
    expect(find.text(quickAddActivityWhen), findsOneWidget);
  });
}
