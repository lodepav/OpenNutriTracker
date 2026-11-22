import 'dart:async';

import 'package:flutter/material.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/repository/recipe_repository.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/undo/undo_delete.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// The Recipes list's delete confirm (seam S425): one recipe by name, several
/// by count, and Delete in the error colour as the profile delete's.
Future<bool> confirmDeleteRecipes(
  BuildContext context,
  List<RecipeEntity> recipes,
) {
  final s = S.of(context);
  return _confirmDelete(
    context,
    title: recipes.length == 1
        ? 'Delete ${recipes.single.name}?'
        : s.deleteSelectedRecipesConfirmTitle(recipes.length),
    content: s.recipeDeleteConfirmContent,
  );
}

/// The custom food bin's confirm (seam S438): the food by name, and Delete
/// in the error colour as a recipe's.
Future<bool> confirmDeleteCustomFood(BuildContext context, String name) =>
    _confirmDelete(
      context,
      title: 'Delete $name?',
      content: 'Past diary entries logged from it will be kept.',
    );

Future<bool> _confirmDelete(
  BuildContext context, {
  required String title,
  required String content,
}) async {
  final s = S.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(s.dialogCancelLabel),
        ),
        FilledButton(
          style: destructiveFilledStyle(ctx),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(s.dialogDeleteLabel),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// A filled button that loses work (Delete, Discard) in the error colour.
ButtonStyle destructiveFilledStyle(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return FilledButton.styleFrom(
    backgroundColor: scheme.error,
    foregroundColor: scheme.onError,
  );
}

/// "Recipe deleted · Undo" after the list's delete. Undo writes the recipes
/// back as they were (id, ingredients, photo and dates), so a starred one
/// resolves to its library entry again. Recipes are shared by every profile,
/// so a profile switch in between does not matter.
void showRecipesDeleted(
  ScaffoldMessengerState messenger,
  List<RecipeEntity> recipes, {
  required VoidCallback onRestored,
}) {
  if (recipes.isEmpty) return;
  messenger.removeCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      persist: undoBarPersists(messenger.context),
      // Twice the default, as a diary delete's: a lot of work to rebuild
      duration: const Duration(seconds: 8),
      content: Text(
        recipes.length == 1
            ? '${recipes.single.name} deleted'
            : '${recipes.length} recipes deleted',
      ),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => unawaited(_restore(messenger, recipes, onRestored)),
      ),
    ),
  );
}

Future<void> _restore(
  ScaffoldMessengerState messenger,
  List<RecipeEntity> recipes,
  VoidCallback onRestored,
) async {
  try {
    final repository = locator<RecipeRepository>();
    for (final recipe in recipes) {
      await repository.saveRecipe(recipe);
    }
  } catch (_) {
    if (messenger.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not restore the recipes.')),
      );
    }
  } finally {
    onRestored();
  }
}

/// "`name` deleted · Undo" after a custom food's delete. [stored] are the
/// rows as the library held them, so Undo writes them back unchanged (photo,
/// data version and all). The library is shared by every profile.
void showCustomFoodDeleted(
  ScaffoldMessengerState messenger,
  String name,
  List<MealDBO> stored, {
  required VoidCallback onRestored,
}) {
  if (stored.isEmpty) return;
  messenger.removeCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      persist: undoBarPersists(messenger.context),
      duration: const Duration(seconds: 8), // as a recipe's bar
      content: Text('$name deleted'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () =>
            unawaited(_restoreFood(messenger, stored, onRestored)),
      ),
    ),
  );
}

Future<void> _restoreFood(
  ScaffoldMessengerState messenger,
  List<MealDBO> stored,
  VoidCallback onRestored,
) async {
  try {
    final library = locator<CustomMealDataSource>();
    // shortcut: the row comes back under a new box key, so it moves to the
    // end of the list; keep the key if the list order starts to matter.
    for (final meal in stored) {
      await library.saveCustomMeal(meal);
    }
  } catch (_) {
    if (messenger.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not restore the food.')),
      );
    }
  } finally {
    onRestored();
  }
}
