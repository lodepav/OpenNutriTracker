import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/data_source/tracked_day_data_source.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/utils/demo/demo_seeder.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:opennutritracker/fork/startup.dart';

import '../upgrade/boot_app.dart';

// S276: a profile edit rewrites today's kcal goal; the Diary's macro goals
// must follow it to what Home computes from that goal.
void main() {
  test('a weight edit leaves today\'s stored macros equal to Home\'s', () async {
    await bootApp(Directory.systemTemp.createTempSync('day_macros'));
    await forkStartup();
    await seedDemoData(DemoSeedOptions.onboarding);

    final user = await locator<GetUserUsecase>().getUserData();
    user.weightKG = 85.9;
    await locator<ProfileBloc>().updateUser(user);

    // What Home shows: the macros of today's live kcal goal.
    final kcal = await locator<GetKcalGoalUsecase>().getKcalGoal(
      userEntity: await locator<GetUserUsecase>().getUserData(),
    );
    final macros = locator<GetMacroGoalUsecase>();
    final now = DateTime.now();
    final row = await locator<TrackedDayDataSource>().getTrackedDay(
      DateTime(now.year, now.month, now.day),
    );

    expect(row!.calorieGoal, closeTo(kcal, 1e-6));
    expect(row.carbsGoal, closeTo(await macros.getCarbsGoal(kcal), 1e-6));
    expect(row.fatGoal, closeTo(await macros.getFatsGoal(kcal), 1e-6));
    expect(row.proteinGoal, closeTo(await macros.getProteinsGoal(kcal), 1e-6));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
