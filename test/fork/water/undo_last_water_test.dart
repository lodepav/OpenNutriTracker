import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/water_intake_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_water_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_user_activity_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_water_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_activity_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_water_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/update_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/update_user_activity_usecase.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';

// Seam S550: Undo last deletes the drink logged last, even with a sample
// drink timed later in the day.

class _Config extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      const ConfigEntity(true, true, false, AppThemeEntity.system);
}

class _Water extends Fake implements GetWaterIntakeUsecase {
  final List<WaterIntakeEntity> today;
  _Water(this.today);

  @override
  Future<List<WaterIntakeEntity>> getTodayEntries({
    required int dayStartOffsetTotalMinutes,
  }) async => [...today];
}

class _Delete extends Fake implements DeleteWaterIntakeUsecase {
  final deleted = <String>[];

  @override
  Future<void> deleteEntry(String id) async => deleted.add(id);
}

class _F1 extends Fake implements AddConfigUsecase {}

class _F2 extends Fake implements GetIntakeUsecase {}

class _F3 extends Fake implements DeleteIntakeUsecase {}

class _F4 extends Fake implements UpdateIntakeUsecase {}

class _F5 extends Fake implements GetUserActivityUsecase {}

class _F6 extends Fake implements DeleteUserActivityUsecase {}

class _F7 extends Fake implements AddTrackedDayUsecase {}

class _F8 extends Fake implements GetKcalGoalUsecase {}

class _F9 extends Fake implements GetMacroGoalUsecase {}

class _F10 extends Fake implements UpdateUserActivityUsecase {}

class _F11 extends Fake implements GetUserUsecase {}

class _F12 extends Fake implements AddWaterIntakeUsecase {}

// The reload after the undo reads use cases this test fakes away.
class _Home extends HomeBloc {
  _Home(
    super.a,
    super.b,
    super.c,
    super.d,
    super.e,
    super.f,
    super.g,
    super.h,
    super.i,
    super.j,
    super.k,
    super.l,
    super.m,
    super.n,
    super.o,
  );

  @override
  void add(HomeEvent event) {}
}

void main() {
  test('Undo last deletes the drink just logged, not a later-timed one',
      () async {
    final delete = _Delete();
    final now = DateTime.now();
    final bloc = _Home(
      _Config(),
      _F1(),
      _F2(),
      _F3(),
      _F4(),
      _F5(),
      _F6(),
      _F7(),
      _F8(),
      _F9(),
      _F10(),
      _F11(),
      _Water([
        WaterIntakeEntity(
          id: 'sample-uuid',
          dateTime: now.add(const Duration(hours: 3)),
          amountMl: 400,
        ),
        WaterIntakeEntity(
          id: 'water-${now.microsecondsSinceEpoch}',
          dateTime: now,
          amountMl: 250,
        ),
      ]),
      _F12(),
      delete,
    );
    addTearDown(bloc.close);

    expect(await bloc.undoLastWaterIntake(), isTrue);
    expect(delete.deleted, ['water-${now.microsecondsSinceEpoch}']);
  });
}
