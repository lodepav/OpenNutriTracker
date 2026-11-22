import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
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
import 'package:opennutritracker/features/activity_detail/presentation/widget/activity_detail_bottom_sheet.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../fixture/physical_activity_entity_fixtures.dart';

// Custom activity: Add stays off at no energy, and the screen's own Scaffold
// paints behind the system bars.

class _FakeActivityDetailBloc extends Fake implements ActivityDetailBloc {}

/// Never answers, so the screen stays on its loading state.
class _PendingUser extends Fake implements GetUserUsecase {
  @override
  Future<UserEntity> getUserData() => Completer<UserEntity>().future;
}

Widget _app(Widget child) => ChangeNotifierProvider<EnergyUnitProvider>(
  create: (_) => EnergyUnitProvider(),
  child: MaterialApp(
    localizationsDelegates: const [S.delegate],
    supportedLocales: S.supportedLocales,
    home: child,
  ),
);

void main() {
  group('Add', () {
    late TextEditingController quantity;

    Future<void> pumpSheet(WidgetTester tester) async {
      quantity = TextEditingController(text: '0');
      addTearDown(quantity.dispose);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: ActivityDetailBottomSheet(
              activityEntity: PhysicalActivityFixtures.moderateBicycling,
              quantityTextController: quantity,
              activityDetailBloc: _FakeActivityDetailBloc(),
              onAddButtonPressed:
                  (_, {templateName, saveAsTemplate = false}) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    bool addEnabled(WidgetTester tester) =>
        tester
            .widget<ButtonStyleButton>(
              find.ancestor(
                of: find.byIcon(Icons.add_rounded),
                matching: find.bySubtype<ButtonStyleButton>(),
              ),
            )
            .onPressed !=
        null;

    testWidgets('is off at 0 and empty, on once there is an amount', (
      tester,
    ) async {
      await pumpSheet(tester);
      expect(addEnabled(tester), isFalse);

      quantity.text = '30';
      await tester.pump();
      expect(addEnabled(tester), isTrue);

      quantity.text = '';
      await tester.pump();
      expect(addEnabled(tester), isFalse);
    });
  });

  testWidgets('the Scaffold is outside the SafeArea', (tester) async {
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
                PhysicalActivityFixtures.moderateBicycling,
                DateTime(2026, 11, 21),
              ),
            ),
            builder: (_) => const ActivityDetailScreen(),
          ),
        ),
      ),
    );
    await tester.pump();

    final screen = find.byType(ActivityDetailScreen);
    final scaffold = find
        .descendant(of: screen, matching: find.byType(Scaffold))
        .first;
    expect(
      find.ancestor(
        of: scaffold,
        matching: find.descendant(of: screen, matching: find.byType(SafeArea)),
      ),
      findsNothing,
    );
  });
}

class _AddActivity extends Fake implements AddUserActivityUsecase {}

class _AddTrackedDay extends Fake implements AddTrackedDayUsecase {}

class _KcalGoal extends Fake implements GetKcalGoalUsecase {}

class _MacroGoal extends Fake implements GetMacroGoalUsecase {}

class _AddTemplate extends Fake implements AddCustomActivityTemplateUsecase {}

class _Templates extends Fake implements GetCustomActivityTemplatesUsecase {}
