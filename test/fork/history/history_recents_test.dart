import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/data_source/intake_data_source.dart';
import 'package:opennutritracker/core/data/data_source/recipe_data_source.dart';
import 'package:opennutritracker/core/data/dbo/intake_dbo.dart';
import 'package:opennutritracker/core/data/dbo/recipe_dbo.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/data/repository/recipe_repository.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/fork/history/history_file.dart';
import 'package:opennutritracker/fork/history/history_import.dart';

import '../../fixture/intake_entity_fixtures.dart';
import '../../helpers/fake_hive_db_provider.dart';
import '../../helpers/hive_test_setup.dart';

void main() {
  test('an imported day is no food among the recents', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Hive.init('.');
    registerHiveAdaptersOnce();
    final provider = FakeHiveDBProvider(
      intakeBox: await Hive.openBox<IntakeDBO>('history_recents_intake'),
      recipeBox: await Hive.openBox<RecipeDBO>('history_recents_recipe'),
    );
    addTearDown(Hive.deleteFromDisk);
    final intakes = IntakeRepository(IntakeDataSource(provider));
    final day = DateTime(2026, 10, 20);
    final plan = planImport(
      HistoryFile(
        food: {
          day: {null: FoodTotals()..add(2000, 150, 200, 70)},
        },
        weightsKg: const {},
        weightUnit: BodyWeightUnit.kg,
        weightUnitStated: false,
      ),
      existing: const HistoryExisting(),
      today: day,
      source: 'MacroFactor',
    );
    final imported = plan.intakes[day]!.single;
    final oats = intakeOf('oats', 50);
    await intakes.addIntake(imported);
    await intakes.addIntake(oats);

    final recents = await GetIntakeUsecase(
      intakes,
      RecipeRepository(RecipeDataSource(provider)),
    ).getRecentIntake();

    expect(isImportedHistory(imported), isTrue);
    expect(recents.map((i) => i.id), [oats.id]);
  });
}
