import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/dbo/tracked_day_dbo.dart';
import 'package:opennutritracker/core/data/dbo/user_dbo.dart';
import 'package:opennutritracker/core/data/dbo/weight_log_dbo.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/profile_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_profiles_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/profile/presentation/screens/manage_profiles_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../helpers/fake_hive_db_provider.dart';

// S565 (G3-7): Manage profiles asks for today's goal for the active profile
// that has no tracked day yet, so a new profile's card is not "—".

final _sam = ProfileEntity(
  id: 'sam',
  name: 'Sam',
  createdAt: DateTime(2026, 11, 22),
  boxSuffix: '',
);

class _Profiles extends Fake implements GetProfilesUsecase {
  @override
  List<ProfileEntity> getProfiles() => [_sam];

  @override
  String get activeProfileId => 'sam';
}

class _Goal extends Fake implements GetKcalGoalUsecase {
  @override
  Future<double> getKcalGoal({
    UserEntity? userEntity,
    double? totalKcalActivitiesParam,
    double? kcalUserAdjustment,
  }) async => 2363;
}

class _Config extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      const ConfigEntity(true, true, false, AppThemeEntity.system);
}

void main() {
  tearDown(() async {
    await locator.reset();
    await Hive.close();
  });

  testWidgets('a new profile\'s card shows today\'s goal', (tester) async {
    await tester.runAsync(() async {
      Hive.init(Directory.systemTemp.createTempSync('manage_goal').path);
      locator
        ..registerSingleton<HiveDBProvider>(
          FakeHiveDBProvider(
            activeProfileId: 'sam',
            userBox: await Hive.openBox<UserDBO>('u'),
            trackedDayBox: await Hive.openBox<TrackedDayDBO>('t'),
            weightLogBox: await Hive.openBox<WeightLogDBO>('w'),
          ),
        )
        ..registerSingleton<GetProfilesUsecase>(_Profiles())
        ..registerSingleton<GetKcalGoalUsecase>(_Goal())
        ..registerSingleton<GetConfigUsecase>(_Config());
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<EnergyUnitProvider>(
        create: (_) => EnergyUnitProvider(),
        child: const MaterialApp(
          localizationsDelegates: [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: S.supportedLocales,
          home: ManageProfilesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2363'), findsOneWidget);
  });
}
