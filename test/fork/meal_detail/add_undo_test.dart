import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/data/data_source/remote_search_cache_data_source.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/meal_detail_bottom_sheet.dart';
import 'package:opennutritracker/fork/add/logged_bar.dart';
import 'package:opennutritracker/fork/copy/copy_entries.dart' show Placed;
import 'package:opennutritracker/generated/l10n.dart';

final _day = DateTime(2026, 10, 5);

final _toast = MealEntity(
  code: 'toast',
  name: 'Toast',
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: 'g',
  servingSize: null,
  nutriments: const MealNutrimentsEntity(
    energyKcal100: 200,
    carbohydrates100: 40,
    fat100: 2,
    proteins100: 6,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  ),
  source: MealSourceEntity.custom,
);

IntakeEntity _intake(String id) => IntakeEntity(
  id: id,
  unit: 'g',
  amount: 100,
  type: IntakeTypeEntity.breakfast,
  meal: _toast,
  dateTime: _day,
);

/// Toast is already in breakfast that day, which upstream asks about.
class _ToastLogged extends Fake implements GetIntakeUsecase {
  @override
  Future<List<IntakeEntity>> getBreakfastIntakeByDay(
    DateTime day, {
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) async => [_intake('earlier')];
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

class _A extends Fake implements AddIntakeUsecase {}

class _B extends Fake implements AddTrackedDayUsecase {}

class _C extends Fake implements GetKcalGoalUsecase {}

class _D extends Fake implements GetMacroGoalUsecase {}

class _E extends Fake implements GetTrackedDayUsecase {}

class _F extends Fake implements ProductsRepository {}

class _G extends Fake implements RemoteSearchCacheDataSource {}

class _Bloc extends MealDetailBloc {
  final writes = <IntakeEntity>[];

  _Bloc() : super(_A(), _B(), _C(), _D(), _E(), _F(), _G());

  @override
  Future<IntakeEntity?> addIntake(
    BuildContext context,
    String unit,
    String amountText,
    IntakeTypeEntity type,
    MealEntity meal,
    DateTime day,
  ) async {
    final written = _intake('new');
    writes.add(written);
    return written;
  }
}

Future<_Bloc> _addToast(WidgetTester tester) async {
  final bloc = _Bloc();
  addTearDown(bloc.close);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [S.delegate],
      supportedLocales: S.supportedLocales,
      home: Scaffold(
        body: MealDetailBottomSheet(
          product: _toast,
          day: _day,
          intakeTypeEntity: IntakeTypeEntity.breakfast,
          quantityTextController: TextEditingController(text: '100'),
          mealDetailBloc: bloc,
          selectedUnit: 'g',
          onQuantityOrUnitChanged: (_, _) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.add_rounded));
  await tester.pumpAndSettle();
  return bloc;
}

void main() {
  setUp(() {
    GetIt.instance
      ..registerFactory<GetIntakeUsecase>(_ToastLogged.new)
      ..registerFactory<HomeBloc>(_Home.new)
      ..registerFactory<DiaryBloc>(_Diary.new)
      ..registerFactory<CalendarDayBloc>(_Calendar.new);
  });

  tearDown(() => GetIt.instance.reset());

  testWidgets('a food already in the meal that day is added without asking', (
    tester,
  ) async {
    final bloc = await _addToast(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(bloc.writes, hasLength(1));
  });

  testWidgets('Undo on the bar takes the entry back off its day', (
    tester,
  ) async {
    final undo = undoLogged;
    final undone = <Placed>[];
    undoLogged = (placed, {required startedOn}) async {
      undone.add(placed);
      return true;
    };
    addTearDown(() => undoLogged = undo);

    final bloc = await _addToast(tester);
    expect(find.text('Added to Breakfast'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(undone, hasLength(1));
    expect(undone.single.day, _day);
    expect(undone.single.written, [bloc.writes.single]);
  });
}
