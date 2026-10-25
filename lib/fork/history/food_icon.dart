import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/utils/custom_icons.dart';
import 'package:opennutritracker/fork/history/history_file.dart';

/// The thumbnail icon of an entry another app logged (seam S100): an import
/// has no photo, so a day's totals show their meal's icon and a food the
/// kind its name says, roughly. Null for anything else, and for a name that
/// says nothing, so the usual icon stays.
IconData? importedFoodIcon(IntakeEntity intake) {
  if (!wasImported(intake)) return null;
  if (isImportedHistory(intake)) {
    // One entry for the whole day has no meal.
    return intake.meal.code!.endsWith('-day')
        ? null
        : intake.type.getIconData();
  }
  final name = intake.meal.name?.toLowerCase() ?? '';
  for (final (pattern, icon) in _kinds) {
    if (pattern.hasMatch(name)) return icon;
  }
  return null;
}

RegExp _words(String words) => RegExp('\\b($words)(e?s)?\\b');

// The first that matches wins, so "whey chocolate" is a shake, "beef
// soup" a soup and "fruit juice" a drink.
final _kinds = [
  (
    _words('whey|casein|protein|isolate|gainer|shake|smoothie'),
    Icons.blender_rounded,
  ),
  (
    _words('coffee|espresso|latte|cappuccino|americano'),
    Icons.local_cafe_rounded,
  ),
  (_words('tea'), Icons.emoji_food_beverage_rounded),
  (_words('beer|kvass|cider'), Icons.sports_bar_rounded),
  (_words('wine|champagne|prosecco'), Icons.wine_bar_rounded),
  (_words('vodka|whisky|whiskey|rum|gin|liqueur|brandy'), Icons.liquor_rounded),
  (_words('ice cream|gelato|sorbet'), Icons.icecream_rounded),
  (
    _words(
      'cake|pie|muffin|pastry|pastries|donut|brownie|cheesecake|waffle|pancake',
    ),
    Icons.cake_rounded,
  ),
  (
    _words(
      'cookie|biscuit|cracker|chocolate|candy|candies|praline|sweets|marzipan|bonbon|jelly|gummy|gummies|sugar|honey|jam',
    ),
    Icons.cookie_rounded,
  ),
  (_words('pizza'), Icons.local_pizza_rounded),
  (
    _words('burger|cheeseburger|hamburger|sandwich|wrap|hot dog'),
    Icons.lunch_dining_rounded,
  ),
  (_words('fries|chips|nugget|popcorn'), Icons.fastfood_rounded),
  (_words('soup|broth|borscht|ramen|noodle'), Icons.ramen_dining_rounded),
  (
    _words('pasta|penne|spaghetti|macaroni|lasagna|lasagne|fusilli|ravioli'),
    Icons.dinner_dining_rounded,
  ),
  (
    _words(
      'rice|risotto|buckwheat|oat|oatmeal|porridge|cereal|flake|granola|muesli|quinoa|couscous',
    ),
    Icons.rice_bowl_rounded,
  ),
  (
    _words('bread|toast|bagel|naan|pita|bun|roll|croissant|baguette|tortilla'),
    Icons.bakery_dining_rounded,
  ),
  (_words('egg|omelet|omelette'), Icons.egg_alt_rounded),
  (
    _words(
      'fish|salmon|tuna|cod|herring|mackerel|trout|shrimp|prawn|sushi|seafood',
    ),
    Icons.set_meal_rounded,
  ),
  (
    _words(
      'chicken|beef|pork|duck|turkey|steak|ham|sausage|bacon|lamb|veal|schnitzel|cutlet|kebab|meat|mince|meatball',
    ),
    Icons.kebab_dining_rounded,
  ),
  (
    _words('milk|kefir|yogurt|yoghurt|juice|soda|cola|lemonade|drink|water'),
    Icons.local_drink_rounded,
  ),
  (
    _words(
      'apple|banana|orange|plum|peach|pear|grape|mango|pineapple|berry|berries|strawberry|strawberries|blueberry|blueberries|cherry|cherries|melon|watermelon|kiwi|fruit|apricot|lemon|lime',
    ),
    CustomIcons.food_apple_outline,
  ),
  (
    _words(
      'salad|lettuce|spinach|carrot|tomato|tomatoes|cucumber|broccoli|cabbage|coleslaw|vegetable|veggie|pepper|beetroot|potato|potatoes|lentil|bean|pea|onion|zucchini',
    ),
    Icons.eco_rounded,
  ),
];
