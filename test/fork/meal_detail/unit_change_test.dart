import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/data_source/remote_search_cache_data_source.dart';
import 'package:opennutritracker/core/domain/usecase/add_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/meal_detail/unit_change.dart';

MealEntity _food(double serving) => MealEntity(
  code: 'x',
  name: 'x',
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: serving,
  servingUnit: 'g',
  servingSize: null,
  nutriments: MealNutrimentsEntity.empty(),
  source: MealSourceEntity.custom,
);

class _Add extends Fake implements AddIntakeUsecase {}

class _Tracked extends Fake implements AddTrackedDayUsecase {}

class _Kcal extends Fake implements GetKcalGoalUsecase {}

class _Macro extends Fake implements GetMacroGoalUsecase {}

class _Day extends Fake implements GetTrackedDayUsecase {}

class _Products extends Fake implements ProductsRepository {}

class _Cache extends Fake implements RemoteSearchCacheDataSource {}

void main() {
  test('a unit picked with the amount blank is the one kept', () async {
    final bloc = MealDetailBloc(
      _Add(),
      _Tracked(),
      _Kcal(),
      _Macro(),
      _Day(),
      _Products(),
      _Cache(),
    );
    addTearDown(bloc.close);
    bloc.add(
      UpdateKcalEvent(
        meal: _food(180),
        totalQuantity: '',
        selectedUnit: 'serving',
      ),
    );
    await bloc.stream.first;
    expect(bloc.state.selectedUnit, 'serving');
  });

  test('a unit change keeps what the amount weighs', () {
    final food = _food(180);
    expect(amountInUnit('180', 'g', 'serving', food), '1');
    expect(amountInUnit('1', 'serving', 'g', food), '180');
    expect(amountInUnit('30', 'g', 'serving', food), '0.2');
    expect(amountInUnit('1', 'oz', 'g', food), '28');
  });

  test('a small amount never keeps its number under the new unit', () {
    expect(amountInUnit('4', 'g', 'serving', _food(100)), '0.04');
    expect(amountInUnit('0.1', 'g', 'serving', _food(100)), '0.01');
  });

  test('what is no amount converts to nothing', () {
    expect(amountInUnit('', 'g', 'serving', _food(100)), isNull);
    expect(amountInUnit('0', 'g', 'serving', _food(100)), isNull);
  });
}
