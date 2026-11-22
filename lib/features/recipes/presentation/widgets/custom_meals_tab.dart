// [fork] S481 thumb-sized-decode: no File left here
// import 'dart:io';
// [/fork]

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
// [fork] S481 thumb-sized-decode: SizedFileImage looks the path up
// import 'package:opennutritracker/core/utils/user_image_storage.dart';
// [/fork]
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/edit_meal/presentation/edit_meal_screen.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/custom_meals_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';
// [fork] S142 custom-food-rows
import 'package:opennutritracker/core/utils/meal_type_suggester.dart';
import 'package:opennutritracker/features/meal_detail/meal_detail_screen.dart';
import 'package:opennutritracker/fork/recipe/recipe_list.dart' show macroSpans;
import 'package:opennutritracker/fork/units/energy_text.dart';
// [/fork]
// [fork] S481 thumb-sized-decode
import 'package:opennutritracker/fork/display/sized_file_image.dart';
// [/fork]
// [fork] S438 custom-food-delete-undo
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/recipe/recipe_delete.dart';
// [/fork]
// [fork] S560 custom-food-per-serving
import 'package:opennutritracker/fork/custom_food/serving_mode.dart';
// [/fork]
// [fork] S561 custom-food-search
import 'package:opennutritracker/fork/custom_food/custom_food_search.dart';
// [/fork]
// [fork] S568 recipes-audit-p3
import 'package:opennutritracker/fork/display/contrast.dart' show chartSafe;
// [/fork]

/// Embeddable list of user-created custom meals (formerly the body of
/// CustomMealsScreen in Settings). Hosted inside RecipesPage's TabBarView.
class CustomMealsTab extends StatelessWidget {
  final bool usesImperialUnits;

  const CustomMealsTab({super.key, required this.usesImperialUnits});

  static String _keyFor(MealEntity meal) => meal.code ?? meal.name ?? '';

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CustomMealsBloc, CustomMealsState>(
      listenWhen: (prev, curr) => curr is CustomMealsMergedState,
      listener: (context, state) {
        if (state is CustomMealsMergedState) {
          final s = S.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                state.rewrittenIntakeCount == 1
                    ? s.customMealsMergeSuccessSnackbarOne(
                        state.winnerDisplayName,
                      )
                    : s.customMealsMergeSuccessSnackbarOther(
                        state.rewrittenIntakeCount,
                        state.winnerDisplayName,
                      ),
              ),
            ),
          );
        }
      },
      builder: (context, state) {
        if (state is CustomMealsLoadingState ||
            state is CustomMealsInitial) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is CustomMealsLoadedState) {
          if (state.meals.isEmpty) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final palette = isDark ? AppPalette.dark : AppPalette.light;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(Dimens.spacing32),
                // [fork] S429 custom-foods-empty: say what a custom food is
                // and how to add one (H10)
                // child: Text(
                //   S.of(context).customMealsEmptyLabel,
                //   textAlign: TextAlign.center,
                //   style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: palette.textMuted),
                // ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      // upstream's says meals; the list and its button say foods
                      'No custom foods yet.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: palette.textMuted),
                    ),
                    const SizedBox(height: Dimens.spacing8),
                    Text(
                      'A custom food is your own food with its nutrition, '
                      'logged like any other. Add one with New custom food.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
                    ),
                  ],
                ),
                // [/fork]
              ),
            );
          }
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final palette = isDark ? AppPalette.dark : AppPalette.light;
          final textTheme = Theme.of(context).textTheme;
          // [fork] S561 custom-food-search: the list under a search by
          // name, as Recipes has (H7)
          // return ListView.builder(
          return CustomFoodSearch(
            meals: state.meals,
            list: (context, shown) => ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: Dimens.spacing8),
            // itemCount: state.meals.length,
            itemCount: shown.length,
            itemBuilder: (context, index) {
              // final meal = state.meals[index];
              final meal = shown[index];
              // [/fork]
              final canMerge = state.meals.length >= 2;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing16, vertical: Dimens.spacing4),
                child: AppCard(
                  padding: EdgeInsets.zero,
                  child: InkWell(
                    borderRadius: Dimens.borderRadiusL,
                    onTap: () => _openFoodPage(context, meal), // [fork] S142
                    child: Padding(
                      padding: const EdgeInsets.all(Dimens.spacing12),
                      child: Row(
                        children: [
                          _MealLeadingThumbnail(meal: meal),
                          const SizedBox(width: Dimens.spacing12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  meal.name ?? '',
                                  maxLines: 2, // [fork] S486 two-line-names: as recipe rows (A6)
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                // [fork] S142 custom-food-rows: what it holds,
                                // as a recipe row says (H7)
                                const SizedBox(height: Dimens.spacing4),
                                // S560: a food typed per serving says so
                                // (H2); S568: the unit spoken in words
                                ValueListenableBuilder<Set<String>>(
                                  valueListenable: CustomFoodModes.perServing,
                                  builder: (context, perServing, _) => Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text:
                                            '${energyText(context, meal.nutriments.energyKcal100 ?? 0)} '
                                            '${perServing.contains(CustomFoodModes.keyOf(meal)) ? 'per serving' : 'per 100 ${meal.isLiquid ? 'ml' : 'g'}'}\n',
                                        semanticsLabel:
                                            '${energyText(context, meal.nutriments.energyKcal100 ?? 0)} '
                                            '${perServing.contains(CustomFoodModes.keyOf(meal)) ? 'per serving' : 'per 100 ${meal.isLiquid ? 'millilitres' : 'grams'}'}, ',
                                      ),
                                      ...macroSpans(context, (
                                        kcal: meal.nutriments.energyKcal100 ?? 0,
                                        carbs: meal.nutriments.carbohydrates100 ?? 0,
                                        fat: meal.nutriments.fat100 ?? 0,
                                        protein: meal.nutriments.proteins100 ?? 0,
                                      ), small: true),
                                    ],
                                  ),
                                  style: textTheme.bodySmall?.copyWith(color: palette.textMuted),
                                ),
                                ), // S560: the mode's listener
                                // [/fork]
                                if (meal.brands != null) ...[
                                  const SizedBox(height: Dimens.spacing4),
                                  Text(
                                    meal.brands!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.bodyMedium?.copyWith(color: palette.textMuted),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          // [fork] S142 custom-food-rows: a tap logs, so
                          // editing moves into the menu
                          Semantics(
                              identifier: 'custom-foods-merge-open',
                              child: PopupMenuButton<String>(
                                icon: Icon(Icons.more_vert_rounded, color: palette.textMuted),
                                tooltip: S.of(context).customMealsRowMoreTooltip,
                                onSelected: (value) {
                                  if (value == 'merge') {
                                    _startMerge(context, meal, state.meals);
                                  }
                                  if (value == 'edit') _openEditMeal(context, meal);
                                },
                                itemBuilder: (ctx) => [
                                  PopupMenuItem<String>(
                                    value: 'edit',
                                    child: Text(S.of(context).editMealLabel),
                                  ),
                                  if (canMerge)
                                  PopupMenuItem<String>(
                                    value: 'merge',
                                    child: Text(
                                      S.of(context).customMealsMergeAction,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          // [fork] S568 recipes-audit-p3: More and Delete
                          // targets apart (A1)
                          const SizedBox(width: Dimens.spacing8),
                          // [/fork]
                          IconButton(
                            icon: Icon(Icons.delete_outline_rounded, color: palette.textMuted),
                            tooltip: 'Delete ${meal.name ?? ''}', // [fork] S132 A3
                            onPressed: () => _confirmDelete(context, meal),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ), // [fork] S561: the search's list
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  // [fork] S142 custom-food-rows: a tap opens the food's page to log it,
  // to the meal the + sheet opened Recipes for or the time's; its pencil
  // edits it
  Future<void> _openFoodPage(BuildContext context, MealEntity meal) async {
    final bloc = context.read<CustomMealsBloc>();
    final args = ModalRoute.of(context)?.settings.arguments;
    await Navigator.of(context).pushNamed(
      NavigationOptions.mealDetailRoute,
      arguments: MealDetailScreenArguments(
        meal,
        args is IntakeTypeEntity
            ? args
            : MealTypeSuggester.suggestFromTime(DateTime.now()),
        DateTime.now(),
        usesImperialUnits,
      ),
    );
    bloc.add(LoadCustomMealsEvent());
  }
  // [/fork]

  Future<void> _openEditMeal(BuildContext context, MealEntity meal) async {
    final bloc = context.read<CustomMealsBloc>();
    await Navigator.of(context).pushNamed(
      NavigationOptions.editMealRoute,
      arguments: EditMealScreenArguments(
        DateTime.now(),
        meal,
        IntakeTypeEntity.breakfast,
        usesImperialUnits,
        editOnly: true,
      ),
    );
    bloc.add(LoadCustomMealsEvent());
  }

  Future<void> _confirmDelete(BuildContext context, MealEntity meal) async {
    final bloc = context.read<CustomMealsBloc>();
    // [fork] S438 custom-food-delete-undo: the recipe delete's confirm, by
    // name and in red, and an Undo bar that writes the stored rows back
    // (H3, H4)
    // final confirmed = await showDialog<bool>(
    //   context: context,
    //   builder: (ctx) => AlertDialog(
    //     title: Text(S.of(context).customMealsDeleteConfirmTitle),
    //     content: Text(S.of(context).customMealsDeleteConfirmContent),
    //     actions: [
    //       TextButton(
    //         onPressed: () => Navigator.of(ctx).pop(false),
    //         child: Text(S.of(context).dialogCancelLabel),
    //       ),
    //       TextButton(
    //         onPressed: () => Navigator.of(ctx).pop(true),
    //         child: Text(S.of(context).dialogDeleteLabel),
    //       ),
    //     ],
    //   ),
    // );
    // if (confirmed == true) {
    //   bloc.add(DeleteCustomMealEvent(meal.code ?? meal.name ?? ''));
    // }
    final key = _keyFor(meal);
    final messenger = ScaffoldMessenger.of(context);
    if (!await confirmDeleteCustomFood(context, meal.name ?? '')) return;
    final stored = locator<CustomMealDataSource>()
        .getAllCustomMeals()
        .where((m) => (m.code ?? m.name) == key)
        .toList();
    bloc.add(DeleteCustomMealEvent(key));
    // The bar waits for the delete, so Undo cannot run before it
    final after = await bloc.stream.firstWhere(
      (s) => s is CustomMealsLoadedState || s is CustomMealsFailedState,
    );
    if (after is! CustomMealsLoadedState) return;
    showCustomFoodDeleted(
      messenger,
      meal.name ?? '',
      stored,
      onRestored: () => bloc.add(LoadCustomMealsEvent()),
    );
    // [/fork]
  }

  /// Two-step flow: pick the partner to merge with, then choose which of
  /// the two stays as the survivor. The row the menu was opened from is
  /// pre-selected as the survivor so the default behaviour matches the
  /// gesture (you tapped the "good" entry, then picked the duplicate).
  Future<void> _startMerge(
    BuildContext context,
    MealEntity tappedFrom,
    List<MealEntity> allMeals,
  ) async {
    final bloc = context.read<CustomMealsBloc>();
    final candidates = allMeals
        .where((m) => _keyFor(m) != _keyFor(tappedFrom))
        .toList();
    if (candidates.isEmpty) return;

    final partner = await showModalBottomSheet<MealEntity>(
      context: context,
      builder: (ctx) {
        return Semantics(
          identifier: 'custom-foods-merge-picker',
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Dimens.spacing16, Dimens.spacing24, Dimens.spacing16, Dimens.spacing8),
                  child: Text(
                    S.of(context).customMealsMergePickerTitle,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: candidates.length,
                    itemBuilder: (ctx2, i) {
                      final m = candidates[i];
                      return ListTile(
                        leading: _MealLeadingThumbnail(meal: m),
                        title: Text(
                          m.name ?? '',
                          style: Theme.of(ctx2).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        subtitle: m.brands != null ? Text(m.brands!) : null,
                        onTap: () => Navigator.of(ctx).pop(m),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (partner == null || !context.mounted) return;

    final winner = await _chooseSurvivor(context, tappedFrom, partner);
    if (winner == null || !context.mounted) return;
    final loser = _keyFor(winner) == _keyFor(tappedFrom) ? partner : tappedFrom;

    final confirmed = await _confirmMerge(context, loser: loser, winner: winner);
    if (confirmed != true) return;

    bloc.add(
      MergeCustomMealsEvent(
        loserKey: _keyFor(loser),
        winnerKey: _keyFor(winner),
      ),
    );
  }

  Future<MealEntity?> _chooseSurvivor(
    BuildContext context,
    MealEntity a,
    MealEntity b,
  ) async {
    MealEntity selected = a;
    return showDialog<MealEntity>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setState) => AlertDialog(
            title: Text(S.of(context).customMealsMergeChooseSurvivorTitle),
            // Flutter 3.32 deprecated the per-tile `groupValue` / `onChanged`
            // pattern in favour of a single `RadioGroup` ancestor that owns
            // the selected value and the change callback. The tiles now
            // just declare their `value`.
            content: RadioGroup<MealEntity>(
              groupValue: selected,
              onChanged: (v) => setState(() => selected = v ?? selected),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    identifier: 'custom-foods-merge-successor-a',
                    child: RadioListTile<MealEntity>(
                      title: Text(a.name ?? ''),
                      value: a,
                    ),
                  ),
                  Semantics(
                    identifier: 'custom-foods-merge-successor-b',
                    child: RadioListTile<MealEntity>(
                      title: Text(b.name ?? ''),
                      value: b,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              Semantics(
                identifier: 'custom-foods-merge-cancel',
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(S.of(context).dialogCancelLabel),
                ),
              ),
              Semantics(
                identifier: 'custom-foods-merge-confirm',
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(selected),
                  child: Text(S.of(context).customMealsMergeContinueAction),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool?> _confirmMerge(
    BuildContext context, {
    required MealEntity loser,
    required MealEntity winner,
  }) {
    final s = S.of(context);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.customMealsMergeConfirmTitle),
        content: Text(
          s.customMealsMergeConfirmContent(
            loser.name ?? '',
            winner.name ?? '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.dialogCancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.customMealsMergeConfirmAction),
          ),
        ],
      ),
    );
  }
}

/// Leading avatar for a custom meal row. Shows the user-attached photo
/// when one exists, otherwise a soft fallback icon matching the recipe
/// list's visual rhythm. Resolution is async because the absolute path
/// is recomposed against the documents directory at render time —
/// see [UserImageStorage.absolutePath] for the reasoning.
class _MealLeadingThumbnail extends StatelessWidget {
  final MealEntity meal;

  const _MealLeadingThumbnail({required this.meal});

  static const double _size = 52;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final relative = meal.localImagePath;
    final fallback = Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: Dimens.borderRadiusS,
      ),
      // [fork] S568 recipes-audit-p3: the icon at 3:1 on its tint, as the
      // recipe rows' (A2)
      // child: Icon(Icons.restaurant_rounded, color: accent, size: 24),
      child: Icon(
        Icons.restaurant_rounded,
        color: chartSafe(
          accent,
          Color.alphaBlend(accent.withValues(alpha: 0.14), paletteOf(context).surface),
        ),
        size: 24,
      ),
      // [/fork]
    );
    if (relative == null) return fallback;
    // [fork] S481 thumb-sized-decode: decoded at the tile's size, the path
    // looked up once, no file check on the UI thread
    // return FutureBuilder<String>(
    //   future: UserImageStorage.absolutePath(relative),
    //   builder: (context, snapshot) {
    //     if (!snapshot.hasData) return fallback;
    //     final file = File(snapshot.data!);
    //     if (!file.existsSync()) return fallback;
    //     return ClipRRect(
    //       borderRadius: Dimens.borderRadiusS,
    //       child: Image.file(file, width: _size, height: _size, fit: BoxFit.cover),
    //     );
    //   },
    // );
    return ClipRRect(
      borderRadius: Dimens.borderRadiusS,
      child: SizedFileImage(
        relativePath: relative,
        size: _size,
        fallback: (_) => fallback,
      ),
    );
    // [/fork]
  }
}
