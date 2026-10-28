// What the bulk-add screen would log, in kcal: shared by the photo and the
// typed-meal calorie checks (calorie_eval_test.dart, text_eval_test.dart).
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/features/add_meal/data/model_meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/data/model_meal_text_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_photo_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_text_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/bulk_add_bloc.dart';
import 'package:opennutritracker/features/meal_detail/util/meal_quantity_converter.dart';
import 'package:opennutritracker/fork/dish/break_down_dish_usecase.dart';
import 'package:opennutritracker/fork/dish/dish_breakdown_controller.dart';
import 'package:opennutritracker/fork/dish/dish_breakdown_rows.dart';
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

/// The state [bloc] settles on after a read: past the longest a call can
/// take with its 429 waits, so a slow model fails as the client says.
Future<BulkAddState> settled(BulkAddBloc bloc) => bloc.stream
    .firstWhere(
      (s) =>
          s is BulkAddLoadedState ||
          s is BulkAddErrorState ||
          s is BulkAddPhotoErrorState,
    )
    .timeout(BackoffClient.budget + const Duration(seconds: 10));

/// The rows of a read as a user who accepts them would log them.
typedef Logged = ({double kcal, int guessed, List<String> cells});

/// [state]'s rows in kcal, each at the amount the screen starts it at. A
/// dish the table does not have is broken down (D9) as the app's
/// `DishBreakdownController` does it: for the amount the row states, with
/// [photo] when the row was read off it, and swapped for its ingredient
/// rows by the bloc's own `replaceRowWithBreakdown`. Null while a
/// breakdown's answer is not in yet.
Future<Logged?> loggedKcal(
  BulkAddLoadedState state,
  MealItemsApi api,
  LocalFoodDataSource foods,
  ResolveParsedMealsUseCase resolver, {
  MealPhoto? photo,
}) async {
  final breakDown = evalBreakDown(api, resolver);
  // The dish each breakdown replaced, with the amount it was asked for.
  final dishes = <Object, String>{};
  for (final row in [...state.rows]) {
    if (row.meal != null) continue;
    final dish = row.resolved.parsed;
    final amount = statedAmount(row);
    final DishBreakdown? broken;
    try {
      broken = await breakDown(
        dish.query,
        amount: amount,
        photo: row.fromPhoto ? photo : null,
      );
    } on MealInterpreterException {
      return null;
    }
    final next = replaceRowWithBreakdown(
      state,
      ReplaceRowWithBreakdownEvent(row.resolved, broken!),
    );
    if (identical(next, state)) continue;
    state = next;
    final group = state.rows
        .map((r) => r.dishIngredient?.group)
        .firstWhere((g) => g != null && !dishes.containsKey(g));
    dishes[group!] = '${amount == null ? '' : '$amount '}${dish.query}';
  }

  var kcal = 0.0;
  var guessed = 0;
  final cells = <String>[];
  final dishKcal = <Object, double>{};
  for (final row in state.rows) {
    final meal = row.meal;
    // A dish the model returned nothing for: the app keeps the row, which
    // logs nothing until the user picks a food.
    if (meal == null) {
      cells.add('${row.resolved.parsed.query} → no breakdown 0');
      continue;
    }
    final amount = double.tryParse(row.amountText.replaceAll(',', '.')) ?? 0;
    final rowKcal = kcalForQuantity(amount, row.effectiveUnit, meal) ?? 0;
    final isGuess =
        row.amountNeedsCheck ||
        (row.resolved.parsed.quantity == null && meal.servingQuantity == null);
    if (isGuess) guessed++;
    kcal += rowKcal;
    if (row.dishIngredient case final ingredient?) {
      dishKcal.update(
        ingredient.group,
        (k) => k + rowKcal,
        ifAbsent: () => rowKcal,
      );
      continue;
    }
    cells.add(
      '${row.resolved.parsed.query} → ${meal.name} '
      '${_n(amount)} ${row.effectiveUnit.split('.').last}'
      '${isGuess ? ' (guess)' : ''} ${rowKcal.round()}',
    );
  }
  for (final MapEntry(key: group, value: dish) in dishes.entries) {
    cells.add('$dish → breakdown ${(dishKcal[group] ?? 0).round()}');
  }
  return (kcal: kcal, guessed: guessed, cells: cells);
}

/// The app's breakdown (`BreakDownDishUseCase`) on [api] and [resolver],
/// with a model always configured.
BreakDown evalBreakDown(MealItemsApi api, ResolveParsedMealsUseCase resolver) =>
    BreakDownDishUseCase(_Configured(), (_) => api, resolver).call;

/// Credentials that always name a model: [evalBreakDown]'s api ignores
/// which.
class _Configured implements AiCredentialStorage {
  @override
  Future<AiSelection?> readSelection() async =>
      const AiSelection(provider: AiProvider.anthropic, apiKey: 'eval');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
