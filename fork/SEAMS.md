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
| S6 | `lib/main.dart` | Saves the four Latvian starter recipes once per install (`StarterRecipeSeeder`, `lib/fork/dish/starter_recipes.dart`), unawaited after the cache prune; loads the active profile's trend and target switches and reloads them on a profile switch (`AdaptiveStore.start`, `lib/fork/adaptive/`, awaited); deletes meal photos over 24 hours old (`MealPhotoCache.prune`, `lib/fork/leftovers/`); with `FORK_FAKE_AI` also sets a dummy Anthropic key. Two blocks: the imports and the calls. | active |
| S7 | `lib/features/meal_detail/presentation/bloc/meal_detail_bloc.dart` | `addIntake` returns the entry it wrote (was `Future<void>`), so a bulk save can group its entries (D14). Two blocks; the fake in `test/features/add_meal/presentation/bulk_add_screen_test.dart` follows (two blocks). | active |
| S8 | `lib/features/add_meal/presentation/screens/bulk_add_screen.dart` | Records the entries one save wrote as a meal, with the photo it was read from if any (`recordMealGroup`, `lib/fork/leftovers/meal_groups.dart`). Nine blocks: the import, the photo field, reading the keep-photos setting and swapping the photo sheet's "keeps no copy" sentence while it is on, clearing the photo on a text read, keeping it on a photo read, the id list, collecting each id, the record call. | active |
| S9 | `lib/features/diary/diary_page.dart` | Tapping an entry of a meal asks "Just this item" or "Whole meal", and the whole meal opens the group leftovers dialog (`editMealGroupLeftovers`, `lib/fork/leftovers/group_leftovers.dart`). Two blocks: the import and the call. | active |
| S10 | `lib/features/home/home_page.dart` | The same as S9 on the home screen. Two blocks. | active |
| S11 | `lib/features/settings/settings_screen.dart` | "Keep meal photos for 24 hours" in the privacy dialog (`KeepMealPhotosSwitch`, `lib/fork/leftovers/meal_photo_cache.dart`). Two blocks: the import and the switch. | active |
| S12 | `lib/core/domain/usecase/get_kcal_goal_usecase.dart` | While "Adaptive calorie target" is on, the goal is the last accepted check-in's target (`adaptiveTargetKcal`, `lib/fork/adaptive/adaptive_service.dart`), without logged activities or the kcal adjustment (D13). An optional constructor argument takes another profile's store (S16). Four blocks: the imports, the field, the constructor argument, the early return. | active |
| S13 | `lib/features/home/home_page.dart` | The weekly check-in card under the dashboard while a check-in is due (`AdaptiveCheckInCard`, `lib/fork/adaptive/adaptive_ui.dart`). Two blocks: the import and the card. | active |
| S14 | `lib/features/settings/settings_screen.dart` | "Trend and adaptive target" in Goals: the smoothed-trend, adaptive-target and monthly-cycle switches (`AdaptiveSettingsTile`). Two blocks: the import and the tile. | active |
| S15 | `lib/features/profile/presentation/widgets/weight_trend_chart.dart` | The smoothed trend in place of the 7-day average when chosen (`smoothedTrendPoints`, `lib/fork/adaptive/trend_points.dart`). Three blocks: the import, computing it, using it. | active |
| S16 | `lib/core/domain/usecase/send_intake_to_profiles_usecase.dart`, `lib/core/utils/hive_db_provider.dart` | The adaptive box (`AdaptiveStore.boxName`) is per-profile: a meal copied into another profile takes that profile's adaptive target, and deleting a profile deletes its check-ins (`perProfileBoxNames`). Two blocks in each: the import and the use. | active |
| S17 | `lib/features/settings/presentation/widgets/kcal_goal_info_screen.dart` | Atop "How your goal is calculated", while the adaptive target is on, the check-in's target and expenditure, and that the formula below is not used (`AdaptiveGoalNote`, `lib/fork/adaptive/adaptive_ui.dart`). Not in onboarding. Two blocks. | active |
| S18 | `lib/dev/main_dev.dart` | Loads the adaptive switches, as `main.dart`'s S6 does (`AdaptiveStore.start`). Two blocks. | active |

## Carried upstream changes

Upstream-bound work (rule 1) is built on a branch off `develop`, cherry-picked (`-x`) into a
`fork/<topic>` branch, and carried without markers until upstream merges it; then the release
merge brings it in and its row goes.

| Branch | What it changes | Upstream |
|---|---|---|
| `feat/photo-note` | Text typed in the bulk-add box goes with a meal photo as a note, in all three clients; an amount survives only when the note states it. | PR not opened yet |
| `feat/leftovers` | The entry edit dialog takes an amount left over, or ¼ ⅓ ½ ¾ of it, off the logged amount. | PR not opened yet |
| `feat/nutrient-contributions` | Tapping carbs, fat or protein on Home lists the day's foods by how much of it each gave (#1266). | PR not opened yet |
