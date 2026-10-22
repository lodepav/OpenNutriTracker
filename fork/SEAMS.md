# Seams — every place the fork edits an upstream file

The fork's code lives in `fork/`, `lib/fork/` and `test/fork/`. Upstream files are edited
**only** at the seams below. Each seam is wrapped in markers so `git grep -n "\[fork\]"`
finds it:

```dart
// [fork] <seam id>: <one line on why>
...fork lines...
// [/fork]
```

(Gradle and XML use their own comment syntax.)

Add the row in the same commit that adds the seam. A seam that is no longer needed (for example
because upstream merged the feature) gets removed, and so does its row.

| Id | File | What the seam does | Status |
|---|---|---|---|
| S1 | `lib/core/utils/locator.dart` | Registers `LocalFoodDataSource` (`lib/fork/food/`) as the `SpFoodDataSource`, so search and AI matching use the bundled tables (D11), and registers the tables' licence credits; with `FORK_FAKE_AI` (debug runs only) swaps the HTTP client for `FakeAiClient` (`lib/fork/dev/`). Two blocks: the imports and the registration. | active |
| S2 | `pubspec.yaml` | Bundles `assets/fork/` (the food table from `fork/tools/build_food_db.py`). | active |
| S3 | `lib/features/add_meal/presentation/bloc/bulk_add_bloc.dart` | Handles `ReplaceRowWithBreakdownEvent` (`lib/fork/dish/`): swaps a dish row for its ingredient rows (D12). Two blocks: the import and the handler. | active |
| S4 | `lib/features/add_meal/presentation/screens/bulk_add_screen.dart` | Runs `DishBreakdownController` (`lib/fork/dish/`): the "Ingredients" and "Save recipe" row actions, the in-progress and "AI estimate" row labels, its disposal. Five blocks. | active |
| S5 | `lib/features/add_meal/domain/usecase/search_products_usecase.dart` | Custom meals and recipes also match when every search word is a word of the name, up to an ending (`nameHasQueryWords`, `lib/fork/dish/recipe_search.dart`), beside upstream's substring match. Upstream PR candidate. Three blocks: the import and the two filters. | active |
| S6 | `lib/main.dart` | Saves the four Latvian starter recipes once per install (`StarterRecipeSeeder`, `lib/fork/dish/starter_recipes.dart`), unawaited after the cache prune; with `FORK_FAKE_AI` also sets a dummy Anthropic key. Two blocks: the imports and the calls. | active |
