import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/quick_add_bottom_sheet.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/fork/launch/launch_actions.dart';
import 'package:opennutritracker/generated/l10n.dart';

class _Config extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async => _Metric();
}

class _Metric extends Fake implements ConfigEntity {
  @override
  bool get usesImperialFoodUnits => false;
  @override
  Map<String, int> get mealKcalSharesPct => const {};
}

class _Add extends Fake implements AddIntakeUsecase {
  @override
  Future<void> addIntake(IntakeEntity intake) async {}
}

class _Tracked implements AddTrackedDayUsecase {
  @override
  Future<bool> hasTrackedDay(DateTime day) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _Home extends Fake implements HomeBloc {
  @override
  void add(HomeEvent event) {}
}

class _Diary extends Fake implements DiaryBloc {
  @override
  void add(DiaryEvent event) {}
}

class _Calendar extends Fake implements CalendarDayBloc {
  @override
  void add(CalendarDayEvent event) {}
}

void main() {
  setUp(() {
    locator
      ..registerSingleton<GetConfigUsecase>(_Config())
      ..registerSingleton<AddIntakeUsecase>(_Add())
      ..registerSingleton<AddTrackedDayUsecase>(_Tracked())
      ..registerSingleton<HomeBloc>(_Home())
      ..registerSingleton<DiaryBloc>(_Diary())
      ..registerSingleton<CalendarDayBloc>(_Calendar());
  });
  tearDown(locator.reset);

  testWidgets('quick add from a shortcut closes only its sheet, the screen '
      'under it kept', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        routes: {NavigationOptions.mainRoute: (_) => const Text('fresh Home')},
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () =>
                        openLaunchAction(context, const QuickAddAction()),
                    child: const Text('shortcut'),
                  ),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    // A screen open, as the app was left, when the shortcut comes in.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('shortcut'));
    await tester.pumpAndSettle();
    expect(find.byType(QuickAddBottomSheet), findsOne);

    await tester.enterText(
      find.descendant(
        of: find.bySemanticsIdentifier('quick-add-energy'),
        matching: find.byType(TextField),
      ),
      '450',
    );
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.bySemanticsIdentifier('quick-add-submit'),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(QuickAddBottomSheet), findsNothing);
    expect(find.text('shortcut'), findsOne);
    expect(find.text('fresh Home'), findsNothing);
  });
}
