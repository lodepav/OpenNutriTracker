import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/profile_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_profiles_usecase.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/presentation/widgets/activity_card.dart';
import 'package:opennutritracker/features/diary/presentation/widgets/day_info_widget.dart';
import 'package:opennutritracker/fork/copy/copy_ui.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../fixture/physical_activity_entity_fixtures.dart';
import '../../helpers/test_l10n.dart';

final _today = DateTime(2026, 6, 16);
final _walk = UserActivityEntity(
  'walk',
  30,
  150,
  _today.add(const Duration(hours: 8)),
  PhysicalActivityFixtures.moderateBicycling,
);

Future<void> _pumpToday(
  WidgetTester tester, {
  required void Function(UserActivityEntity) onDelete,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => EnergyUnitProvider(),
      child: MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: DayInfoWidget(
              selectedDay: _today,
              currentDay: _today,
              trackedDayEntity: null,
              userActivities: [_walk],
              breakfastIntake: const [],
              lunchIntake: const [],
              dinnerIntake: const [],
              snackIntake: const [],
              usesImperialUnits: false,
              showActivityTracking: true,
              onDeleteIntake: (_, _) {},
              onDeleteActivity: (activity, _) => onDelete(activity),
              onCopyIntake: (_, _, _) {},
              onCopyActivity: (_, _) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

class _MealDetailBloc extends Fake implements MealDetailBloc {}

class _HomeBloc extends Fake implements HomeBloc {}

class _Profiles extends Fake implements GetProfilesUsecase {
  static final _me = ProfileEntity(
    id: 'p1',
    name: 'Me',
    createdAt: DateTime(2026),
    boxSuffix: '',
  );

  @override
  List<ProfileEntity> getProfiles() => [_me];

  @override
  String get activeProfileId => 'p1';

  @override
  ProfileEntity? getActiveProfile() => _me;
}

void main() {
  setUpAll(() {
    GetIt.instance
      ..registerFactory<MealDetailBloc>(_MealDetailBloc.new)
      ..registerFactory<HomeBloc>(_HomeBloc.new)
      ..registerFactory<GetProfilesUsecase>(_Profiles.new);
  });
  tearDownAll(GetIt.instance.reset);

  testWidgets("today's activity offers a copy, and deleting it still asks", (
    tester,
  ) async {
    final deleted = <UserActivityEntity>[];
    await _pumpToday(tester, onDelete: deleted.add);

    await tester.longPress(find.byType(ActivityCard));
    await tester.pumpAndSettle();
    expect(
      find.text('${l10nEn.copyActionLabel}…'.toUpperCase()),
      findsOneWidget,
    );
    await tester.tap(find.text(l10nEn.dialogDeleteLabel.toUpperCase()));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10nEn.dialogOKLabel));
    await tester.pumpAndSettle();

    expect(deleted, [_walk]);
  });

  testWidgets('the activity copy asks only for a day', (tester) async {
    CopyTarget? picked;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await showDialog<CopyTarget>(
              context: context,
              builder: (_) =>
                  CopyTargetDialog(initialDay: _today, activitiesOnly: true),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButton), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
    await tester.tap(find.text(l10nEn.dialogOKLabel));
    await tester.pumpAndSettle();
    expect(picked?.day, _today);
  });
}
