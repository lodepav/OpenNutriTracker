import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/physical_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_physical_activity_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_activity_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/log_user_activity_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/screens/activity/add_activity_screen.dart';
import 'package:opennutritracker/features/add_activity/presentation/bloc/activities_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

// Seam S128: the screen logs on the screen's day, refreshes, and Undo
// takes the entry and its goal back off that day.

const _yoga = PhysicalActivityEntity(
  '02160',
  'yoga',
  'general',
  4,
  [],
  PhysicalActivityTypeEntity.conditioningExercise,
);

final _user = UserEntity(
  birthday: DateTime(1990, 1, 1),
  heightCM: 180,
  weightKG: 80,
  gender: UserGenderEntity.male,
  goal: UserWeightGoalEntity.maintainWeight,
  pal: UserPALEntity.sedentary,
);

class _Activities extends Fake implements GetPhysicalActivityUsecase {
  @override
  Future<List<PhysicalActivityEntity>> getAllPhysicalActivities() async => [
    _yoga,
  ];
}

class _Users extends Fake implements GetUserUsecase {
  @override
  Future<UserEntity> getUserData() async => _user;
}

class _Config extends Fake implements ConfigEntity {
  @override
  BodyWeightUnit get bodyWeightUnit => BodyWeightUnit.kg;
}

class _ConfigRepository extends Fake implements ConfigRepository {
  @override
  Future<ConfigEntity> getConfig() async => _Config();
}

class _Recent extends Fake implements GetUserActivityUsecase {
  @override
  Future<List<UserActivityEntity>> getRecentUserActivity() async => [
    UserActivityEntity('old', 45, 1, DateTime(2026), _yoga),
    // Imported with no minutes: nothing to log again.
    UserActivityEntity(
      'sync',
      0,
      120,
      DateTime(2026),
      const PhysicalActivityEntity(
        '01015',
        'bicycling',
        'general',
        7.5,
        [],
        PhysicalActivityTypeEntity.bicycling,
      ),
    ),
  ];
}

class _Log extends Fake implements LogUserActivityUsecase {
  final logged = <(UserActivityEntity, DateTime)>[];

  @override
  Future<void> logActivity(
    UserActivityEntity activity, {
    required DateTime day,
  }) async => logged.add((activity, day));
}

class _Home extends Fake implements HomeBloc {
  var loads = 0;

  @override
  void add(HomeEvent event) => loads++;
}

class _Diary extends Fake implements DiaryBloc {
  @override
  void add(DiaryEvent event) {}
}

class _Calendar extends Fake implements CalendarDayBloc {
  final deleted = <(UserActivityEntity, DateTime)>[];

  @override
  void add(CalendarDayEvent event) {}

  @override
  Future<void> deleteUserActivityItem(
    BuildContext context,
    UserActivityEntity activityEntity,
    DateTime day,
  ) async => deleted.add((activityEntity, day));
}

void main() {
  final day = DateTime(2026, 10, 20);
  late _Log log;
  late _Home home;
  late _Calendar calendar;

  setUp(() {
    log = _Log();
    home = _Home();
    calendar = _Calendar();
    locator
      ..registerFactory<ActivitiesBloc>(() => ActivitiesBloc(_Activities()))
      ..registerSingleton<GetUserUsecase>(_Users())
      ..registerSingleton<ConfigRepository>(_ConfigRepository())
      ..registerSingleton<GetUserActivityUsecase>(_Recent())
      ..registerSingleton<LogUserActivityUsecase>(log)
      ..registerSingleton<HomeBloc>(home)
      ..registerSingleton<DiaryBloc>(_Diary())
      ..registerSingleton<CalendarDayBloc>(calendar);
  });

  tearDown(() => GetIt.instance.reset());

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => EnergyUnitProvider(usesKilojoules: false),
        child: MaterialApp(
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: S.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    settings: RouteSettings(
                      arguments: AddActivityScreenArguments(day: day),
                    ),
                    builder: (_) => const AddActivityScreen(),
                  ),
                ),
                child: const Text('main'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('main'));
    await tester.pumpAndSettle();
  }

  testWidgets('a row logs its minutes on the day, back on the dashboard', (
    tester,
  ) async {
    await open(tester);
    expect(
      find.text('Based on 80 kg. Tap a row to pick the duration.'),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsIdentifier('add-activity-row-02160'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('activity-duration-60'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('activity-duration-add'));
    await tester.pumpAndSettle();

    expect(log.logged, hasLength(1));
    final (entry, on) = log.logged.single;
    expect(entry.duration, 60);
    expect(entry.burnedKcal, 320);
    expect(entry.date, day);
    expect(on, day);
    expect(home.loads, 1);
    expect(find.byType(AddActivityScreen), findsNothing);
    expect(find.text('Added 60 min yoga'), findsOneWidget);
    expect(calendar.deleted, isEmpty);
  });

  testWidgets('Undo takes it back off the same day', (tester) async {
    await open(tester);
    // A recent with no minutes is left out.
    expect(
      find.bySemanticsIdentifier('add-activity-recent-01015'),
      findsNothing,
    );
    await tester.tap(find.bySemanticsIdentifier('add-activity-recent-02160'));
    await tester.pumpAndSettle();
    expect(find.text('Added 45 min yoga'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    final (logged, _) = log.logged.single;
    expect(calendar.deleted, [(logged, day)]);
    expect(home.loads, 2);
  });
}
