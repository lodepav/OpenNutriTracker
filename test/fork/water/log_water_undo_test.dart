import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/water_intake_entity.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/home/presentation/widgets/log_water_dialog.dart';

import '../../helpers/ux_checks.dart';

// Log water: Undo last says what it removed and closes, so OK can't log the
// drink again; the title wraps at 200%.

class _Home extends Fake implements HomeBloc {
  @override
  final HomeState state;
  final List<int> added = [];
  var undone = 0;

  _Home(this.state);

  @override
  Future<void> addWaterIntake(int amountMl) async => added.add(amountMl);

  @override
  Future<bool> undoLastWaterIntake() async {
    undone++;
    return true;
  }
}

HomeLoadedState _loaded(List<WaterIntakeEntity> drinks) => HomeLoadedState(
  showDisclaimerDialog: false,
  totalKcalDaily: 2400,
  totalKcalLeft: 0,
  totalKcalSupplied: 0,
  totalKcalBurned: 0,
  totalCarbsIntake: 0,
  totalFatsIntake: 0,
  totalProteinsIntake: 0,
  totalCarbsGoal: 250,
  totalFatsGoal: 80,
  totalProteinsGoal: 150,
  userActivityList: const [],
  breakfastIntakeList: const [],
  lunchIntakeList: const [],
  dinnerIntakeList: const [],
  snackIntakeList: const [],
  usesImperialUnits: false,
  bodyWeightUnit: BodyWeightUnit.kg,
  userWeightKg: 80,
  breakfastKcalTarget: 0,
  lunchKcalTarget: 0,
  dinnerKcalTarget: 0,
  snackKcalTarget: 0,
  breakfastSharePct: 25,
  lunchSharePct: 25,
  dinnerSharePct: 25,
  snackSharePct: 25,
  userGender: UserGenderEntity.male,
  userCaloriesProfile: null,
  waterMlToday: drinks.fold(0, (sum, d) => sum + d.amountMl),
  waterGoalMl: 2000,
  waterIntakes: drinks,
);

WaterIntakeEntity _drink(int hour, int ml) => WaterIntakeEntity(
  id: 'w$hour',
  dateTime: DateTime(2026, 11, 21, hour),
  amountMl: ml,
);

Widget _launcher({bool imperial = false}) => Builder(
  builder: (context) => ElevatedButton(
    onPressed: () => showDialog<void>(
      context: context,
      builder: (_) => LogWaterDialog(usesImperialUnits: imperial),
    ),
    child: const Text('Open'),
  ),
);

void main() {
  late _Home home;

  setUp(() {
    // The latest drink is listed first, so the dialog has to sort by time.
    home = _Home(_loaded([_drink(15, 250), _drink(9, 500), _drink(12, 700)]));
    locator.registerSingleton<HomeBloc>(home);
  });

  tearDown(() async => locator.reset());

  testWidgets('Undo last closes and says what it removed', (tester) async {
    await pumpOnPhone(tester, _launcher(), textScale: 1);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier('log-water-undo'));
    await tester.pumpAndSettle();

    expect(home.undone, 1);
    expect(find.byType(LogWaterDialog), findsNothing);
    expect(find.text('Removed 250 ml · today 1200 ml'), findsOneWidget);
    expect(home.added, isEmpty);
  });

  testWidgets('in fl oz with imperial units', (tester) async {
    await pumpOnPhone(tester, _launcher(imperial: true), textScale: 1);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier('log-water-undo'));
    await tester.pumpAndSettle();

    expect(find.text('Removed 8 fl oz · today 41 fl oz'), findsOneWidget);
  });

  testWidgets('the title wraps at 200%', (tester) async {
    await pumpOnPhone(tester, _launcher());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(cutText(tester), isNot(contains('Log water intake')));
  });
}
