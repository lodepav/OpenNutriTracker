import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:opennutritracker/core/data/repository/recipe_repository.dart';
import 'package:opennutritracker/core/utils/locator.dart';

/// How many saved dish names a photo read carries, the latest first.
const savedDishesLimit = 60;

/// The user's recipe names, latest changed first, for the photo prompt
/// (S172). A photo names a regional dish generically ("dumplings", "stuffed
/// pie"), which misses the user's own "Pelmeni"; the eval found photo to
/// saved recipe the weak spot for every model.
/// Empty when the recipes cannot be read: the photo is read without them.
List<String> savedDishNames() {
  try {
    final recipes = locator<RecipeRepository>().getAllRecipes()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return [for (final r in recipes) r.name];
  } catch (e, stackTrace) {
    Logger('savedDishNames').warning('Recipes unreadable', e, stackTrace);
    return const [];
  }
}

/// The line the photo prompt gets for [names], or null for none.
String? savedDishesPrompt(List<String> names) {
  final seen = <String>{};
  final unique = [
    for (final name in names.map((n) => n.trim()))
      if (name.isNotEmpty && seen.add(name.toLowerCase())) name,
  ].take(savedDishesLimit).toList();
  if (unique.isEmpty) return null;
  return 'The user has saved these dishes: '
      '${unique.map(jsonEncode).join(', ')}. When the photo clearly shows one '
      'of them, use its name exactly as the query; otherwise name the food '
      'as usual.';
}
