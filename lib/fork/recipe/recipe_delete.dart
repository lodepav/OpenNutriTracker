import 'dart:async';

import 'package:flutter/material.dart';
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
) async {
  final s = S.of(context);
  final scheme = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        recipes.length == 1
            ? 'Delete ${recipes.single.name}?'
            : s.deleteSelectedRecipesConfirmTitle(recipes.length),
      ),
      content: Text(s.recipeDeleteConfirmContent),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(s.dialogCancelLabel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(s.dialogDeleteLabel),
        ),
      ],
    ),
  );
  return confirmed == true;
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
