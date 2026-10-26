import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/share_qr_dialog.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/meal_detail/meal_detail_screen.dart';
import 'package:opennutritracker/features/recipes/domain/entity/shared_recipe_payload.dart';
import 'package:opennutritracker/features/recipes/presentation/bloc/recipe_detail_bloc.dart';
import 'package:opennutritracker/features/recipes/presentation/screens/recipe_builder_screen.dart';
// [fork] S126 recipe-page: in place of the summary card and upstream's rows
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/fork/basket/basket_ui.dart';
import 'package:opennutritracker/fork/recipe/recipe_page.dart';
import 'package:opennutritracker/core/utils/meal_type_suggester.dart';
import 'package:opennutritracker/fork/copy/copy_ui.dart' show mealLabel;
// [/fork]
import 'package:opennutritracker/generated/l10n.dart';

class RecipeDetailArguments {
  final String recipeId;
  // [fork] S126 recipe-page: the meal the + sheet was on, if it led here
  final IntakeTypeEntity? meal;
  const RecipeDetailArguments({required this.recipeId, this.meal});
  // [/fork]
}

// [fork] S126 recipe-page: another amount, on the meal detail
enum _RecipeMenuAction { otherAmount, duplicate, delete }
// [/fork]

class RecipeDetailScreen extends StatefulWidget {
  const RecipeDetailScreen({super.key});

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  late RecipeDetailBloc _bloc;
  bool _initialized = false;
  // [fork] S126 recipe-page: servings, or whole recipes, to log
  double _count = 1;
  // The meal Log goes to: the + sheet's, else the time of day's (U7).
  late IntakeTypeEntity _meal;
  // [/fork]

  @override
  void initState() {
    super.initState();
    _bloc = locator<RecipeDetailBloc>();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final args = ModalRoute.of(context)?.settings.arguments
          as RecipeDetailArguments;
      // [fork] S126 recipe-page
      _meal = args.meal ?? MealTypeSuggester.suggestFromTime(DateTime.now());
      // [/fork]
      _bloc.add(LoadRecipeEvent(args.recipeId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<RecipeDetailBloc, RecipeDetailState>(
      bloc: _bloc,
      listener: (context, state) {
        if (state is RecipeDetailDeleted || state is RecipeDetailMissing) {
          Navigator.of(context).pop();
        }
      },
      builder: (context, state) {
        if (state is RecipeDetailLoaded) {
          return _buildLoaded(context, state.recipe);
        }
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }

  Widget _buildLoaded(BuildContext context, RecipeEntity recipe) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        // [fork] S126 recipe-page: the name is the page's header below
        title: null,
        // [/fork]
        actions: [
          IconButton(
            tooltip: S.of(context).shareRecipeLabel,
            icon: const Icon(Icons.share_outlined),
            onPressed: () {
              final code = SharedRecipePayload.fromRecipe(recipe).toJsonString();
              showDialog(
                context: context,
                builder: (_) => ShareQrDialog(
                  title: S.of(context).shareRecipeLabel,
                  code: code,
                  fileBaseName: 'recipe_qr',
                ),
              );
            },
          ),
          IconButton(
            tooltip: S.of(context).editRecipeTitle,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              await Navigator.of(context).pushNamed(
                NavigationOptions.recipeBuilderRoute,
                arguments: RecipeBuilderArguments(existing: recipe),
              );
              if (mounted) _bloc.add(LoadRecipeEvent(recipe.id));
            },
          ),
          PopupMenuButton<_RecipeMenuAction>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (action) => _onMenuSelected(context, action, recipe),
            itemBuilder: (context) => [
              // [fork] S126 recipe-page
              const PopupMenuItem(
                value: _RecipeMenuAction.otherAmount,
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded),
                    SizedBox(width: Dimens.spacing12),
                    Text('Log another amount'),
                  ],
                ),
              ),
              // [/fork]
              PopupMenuItem(
                value: _RecipeMenuAction.duplicate,
                child: Row(
                  children: [
                    const Icon(Icons.copy_outlined),
                    const SizedBox(width: Dimens.spacing12),
                    Text(S.of(context).duplicateRecipeLabel),
                  ],
                ),
              ),
              PopupMenuItem(
                value: _RecipeMenuAction.delete,
                child: Row(
                  children: [
                    const Icon(Icons.delete_outline_rounded),
                    const SizedBox(width: Dimens.spacing12),
                    Text(S.of(context).dialogDeleteLabel),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      // [fork] S126 recipe-page: ingredients first, a stepper beside Log
      body: ListView(
        padding: const EdgeInsets.all(Dimens.spacing16),
        children: [
          RecipeHeader(recipe: recipe),
          const SizedBox(height: Dimens.spacing12),
          RecipeTotalsStrip(portion: RecipePortion(recipe, _count)),
          const SizedBox(height: Dimens.spacing16),
          Text(
            S.of(context).recipeIngredientsLabel,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: Dimens.spacing4),
          for (final (i, ingredient) in recipe.ingredients.indexed) ...[
            if (i > 0) Divider(height: 1, color: palette.border),
            RecipeIngredientRow(ingredient: ingredient),
          ],
          const SizedBox(height: Dimens.spacing16),
        ],
      ),
      bottomNavigationBar: RecipeLogBar(
        portion: RecipePortion(recipe, _count),
        onCount: (count) => setState(() => _count = count),
        meal: _meal,
        onMeal: (meal) => setState(() => _meal = meal),
        onLog: () => _logPortion(context, RecipePortion(recipe, _count)),
      ),
      // [/fork]
    );
  }

  // [fork] S126 recipe-page: the portion straight into the meal picked
  Future<void> _logPortion(BuildContext context, RecipePortion portion) async {
    final type = _meal;
    final written = await locator<MealDetailBloc>().addIntake(
      context,
      'g',
      portion.grams.toStringAsFixed(1), // [fork] S142 one decimal
      type,
      portion.recipe.toMealEntity(),
      DateTime.now(),
    );
    if (written == null || !context.mounted) return;
    refreshAfterLogging();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${portion.label} of ${portion.recipe.name} added to '
          '${mealLabel(context, type)}',
        ),
      ),
    );
  }
  // [/fork]

  Future<void> _onMenuSelected(
    BuildContext context,
    _RecipeMenuAction action,
    RecipeEntity recipe,
  ) async {
    switch (action) {
      // [fork] S126 recipe-page
      case _RecipeMenuAction.otherAmount:
        await _onLogPressed(context, recipe);
      // [/fork]
      case _RecipeMenuAction.duplicate:
        // Open the builder with a copy: drop the id (so save() assigns a new
        // one) and append the localized "(copy)" suffix to the name. The
        // user can rename before saving — common workflow is "tweak one
        // ingredient and save as new".
        final suffix = S.of(context).duplicateRecipeNameSuffix;
        final draft = recipe.copyWith(
          id: '',
          name: '${recipe.name} $suffix',
        );
        // copyWith on RecipeEntity always carries the id forward; we want a
        // fresh one. The builder treats an empty id as a "create new"
        // sentinel: it generates a UUID at save time.
        final fresh = RecipeEntity(
          id: '',
          name: draft.name,
          description: draft.description,
          ingredients: draft.ingredients,
          totalWeightG: draft.totalWeightG,
          aggregatedNutrimentsPer100: draft.aggregatedNutrimentsPer100,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          servingsCount: draft.servingsCount,
          tags: draft.tags,
        );
        await Navigator.of(context).pushNamed(
          NavigationOptions.recipeBuilderRoute,
          arguments: RecipeBuilderArguments(existing: fresh),
        );
        if (mounted) _bloc.add(LoadRecipeEvent(recipe.id));
      case _RecipeMenuAction.delete:
        await _confirmDelete(context);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.of(context).recipeDeleteConfirmTitle),
        content: Text(S.of(context).recipeDeleteConfirmContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(S.of(context).dialogCancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(S.of(context).dialogDeleteLabel),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _bloc.add(const DeleteRecipeFromDetailEvent());
    }
  }

  Future<void> _onLogPressed(BuildContext context, RecipeEntity recipe) async {
    final intakeType = await _pickIntakeType(context);
    if (intakeType == null || !context.mounted) return;
    final config = await locator<GetConfigUsecase>().getConfig();
    if (!context.mounted) return;
    Navigator.of(context).pushNamed(
      NavigationOptions.mealDetailRoute,
      arguments: MealDetailScreenArguments(
        recipe.toMealEntity(),
        intakeType,
        DateTime.now(),
        config.usesImperialFoodUnits,
      ),
    );
  }

  Future<IntakeTypeEntity?> _pickIntakeType(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    return showModalBottomSheet<IntakeTypeEntity>(
      context: context,
      builder: (ctx) {
        Widget tile(IntakeTypeEntity type, String label) {
          final accent = Theme.of(ctx).colorScheme.primary;
          return ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: Dimens.borderRadiusS,
              ),
              child: Icon(type.getIconData(), color: accent, size: 22),
            ),
            title: Text(
              label,
              style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            onTap: () => Navigator.of(ctx).pop(type),
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: Dimens.spacing12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: Dimens.spacing8),
              tile(IntakeTypeEntity.breakfast, s.breakfastLabel),
              tile(IntakeTypeEntity.lunch, s.lunchLabel),
              tile(IntakeTypeEntity.dinner, s.dinnerLabel),
              tile(IntakeTypeEntity.snack, s.snackLabel),
            ],
          ),
        );
      },
    );
  }
}
