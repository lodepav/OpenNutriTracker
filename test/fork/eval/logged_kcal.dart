// What the bulk-add screen would log, in kcal: shared by the photo and the
// typed-meal calorie checks (calorie_eval_test.dart, text_eval_test.dart).
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/features/add_meal/data/model_meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/data/model_meal_text_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_photo_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_text_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/meal_detail/util/meal_quantity_converter.dart';
import 'package:opennutritracker/fork/dish/break_down_dish_usecase.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';

import 'eval_model.dart';

/// A bulk-add bloc on [api] and [resolver]. One per read: a bloc that
/// loaded the same rows twice would not emit the second time.
BulkAddBloc evalBulkAddBloc(
  MealItemsApi api,
  ResolveParsedMealsUseCase resolver,
) {
  final credentials = AiCredentialStorage();
  return BulkAddBloc(
    resolver,
    ReadMealTextUseCase(credentials, (_) => ModelMealTextInterpreter(api)),
    ReadMealPhotoUseCase(credentials, (_) => ModelMealPhotoInterpreter(api)),
  );
}

/// The state [bloc] settles on after a read, within 100 seconds: past the
/// eval client's own 90, so a slow model fails as the client says.
Future<BulkAddState> settled(BulkAddBloc bloc) => bloc.stream
    .firstWhere(
      (s) =>
          s is BulkAddLoadedState ||
          s is BulkAddErrorState ||
          s is BulkAddPhotoErrorState,
    )
    .timeout(const Duration(seconds: 100));

/// The rows of a read as a user who accepts them would log them.
typedef Logged = ({double kcal, int guessed, List<String> cells});

/// [state]'s rows in kcal, each at the amount the screen starts it at. A
/// dish the table does not have is broken down (D9) into one serving, as
/// the app does, whatever count the model gave the dish. Null while a
/// breakdown's answer is not in yet.
Future<Logged?> loggedKcal(
  BulkAddLoadedState state,
  MealItemsApi api,
  LocalFoodDataSource foods,
) async {
  var kcal = 0.0;
  var guessed = 0;
  final cells = <String>[];
  for (final row in state.rows) {
    final meal = row.meal;
    if (meal == null) {
      final dish = row.resolved.parsed;
      final broken = await _breakDown(api, foods, dish.query);
      if (broken == null) return null;
      kcal += broken;
      cells.add(
        '${dish.quantity == null ? '' : '${_n(dish.quantity!)}× '}'
        '${dish.query} → breakdown ${broken.round()}',
      );
      continue;
    }
    final amount = double.tryParse(row.amountText.replaceAll(',', '.')) ?? 0;
    final rowKcal = kcalForQuantity(amount, row.effectiveUnit, meal) ?? 0;
    final isGuess =
        row.amountNeedsCheck ||
        (row.resolved.parsed.quantity == null && meal.servingQuantity == null);
    if (isGuess) guessed++;
    kcal += rowKcal;
    cells.add(
      '${row.resolved.parsed.query} → ${meal.name} '
      '${_n(amount)} ${row.effectiveUnit.split('.').last}'
      '${isGuess ? ' (guess)' : ''} ${rowKcal.round()}',
    );
  }
  return (kcal: kcal, guessed: guessed, cells: cells);
}

/// One serving of [dish] broken down by the fork's prompt, in kcal, or null
/// while the answer is not in yet.
Future<double?> _breakDown(
  MealItemsApi api,
  LocalFoodDataSource foods,
  String dish,
) async {
  try {
    final reply = await api.requestItems(
      content: MealTextContent(BreakDownDishUseCase.contentFor(dish)),
      system: BreakDownDishUseCase.systemPrompt,
    );
    var kcal = 0.0;
    for (final item in reply.items) {
      final row = await tableMatch(foods, item.query);
      final per100 = row?.nutriments.energyKcal100;
      if (per100 == null || item.quantity == null) continue;
      kcal += per100 * item.quantity! / 100;
    }
    return kcal;
  } on MealInterpreterException {
    return null;
  }
}

String _n(double v) =>
    v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);

/// Logged kcal against a reference, over a model's reads.
class KcalScore {
  final offs = <double>[];
  var logged = 0.0, reference = 0.0;
  var guessed = 0;

  void add(double kcal, double referenceKcal, int guessedRows) {
    offs.add((kcal / referenceKcal - 1).abs());
    logged += kcal;
    reference += referenceKcal;
    guessed += guessedRows;
  }

  static const header =
      '| Model | Meals | Within 25% | Median off | Logged / reference, total '
      '| Rows at a guessed amount |\n'
      '|---|---|---|---|---|---|\n';

  String row(String name) {
    final sorted = [...offs]..sort();
    return '| $name | ${offs.length} '
        '| ${offs.where((o) => o <= 0.25).length}/${offs.length} '
        '| ${(sorted[sorted.length ~/ 2] * 100).round()}% '
        '| ${(logged / reference * 100).round()}% | $guessed |';
  }
}
