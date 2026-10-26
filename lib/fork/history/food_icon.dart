import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/fork/history/history_file.dart';

/// The thumbnail icon of a day's totals another app logged (seam S100):
/// an import has no photo, so they show their meal's icon. Null for
/// anything else, and for one entry for the whole day, so the usual icon
/// stays.
IconData? importedFoodIcon(IntakeEntity intake) {
  if (!isImportedHistory(intake)) return null;
  // One entry for the whole day has no meal.
  return intake.meal.code!.endsWith('-day') ? null : intake.type.getIconData();
}

/// The emoji of a food another app logged: the kind its name says,
/// roughly, in color like a searched food's. Null for anything else, and
/// for a name that says nothing.
String? importedFoodEmoji(IntakeEntity intake) {
  if (!wasImported(intake) || isImportedHistory(intake)) return null;
  final name = intake.meal.name?.toLowerCase() ?? '';
  for (final (pattern, emoji) in _kinds) {
    if (pattern.hasMatch(name)) return emoji;
  }
  return null;
}

RegExp _words(String words) => RegExp('\\b($words)(e?s)?\\b');

// The first that matches wins, so "whey chocolate" is a shake, "beef
// soup" a soup and "fruit juice" a drink.
final _kinds = [
  (_words('whey|casein|protein|isolate|gainer|shake|smoothie'), '🥤'),
  (_words('coffee|espresso|latte|cappuccino|americano'), '☕'),
  (_words('tea'), '🍵'),
  (_words('beer|kvass|cider'), '🍺'),
  (_words('wine|champagne|prosecco'), '🍷'),
  (_words('vodka|whisky|whiskey|rum|gin|liqueur|brandy'), '🥃'),
  (_words('ice cream|gelato|sorbet'), '🍨'),
  (
    _words(
      'cake|pie|muffin|pastry|pastries|donut|brownie|cheesecake|waffle|pancake',
    ),
    '🍰',
  ),
  (
    _words(
      'cookie|biscuit|cracker|chocolate|candy|candies|praline|sweets|marzipan|bonbon|jelly|gummy|gummies|sugar|honey|jam',
    ),
    '🍪',
  ),
  (_words('pizza'), '🍕'),
  (_words('burger|cheeseburger|hamburger|sandwich|wrap|hot dog'), '🍔'),
  (_words('fries|chips|nugget|popcorn'), '🍟'),
  (_words('soup|broth|borscht|ramen|noodle'), '🍜'),
  (
    _words('pasta|penne|spaghetti|macaroni|lasagna|lasagne|fusilli|ravioli'),
    '🍝',
  ),
  (
    _words(
      'rice|risotto|buckwheat|oat|oatmeal|porridge|cereal|flake|granola|muesli|quinoa|couscous',
    ),
    '🍚',
  ),
  (
    _words('bread|toast|bagel|naan|pita|bun|roll|croissant|baguette|tortilla'),
    '🍞',
  ),
  (_words('egg|omelet|omelette'), '🥚'),
  (
    _words(
      'fish|salmon|tuna|cod|herring|mackerel|trout|shrimp|prawn|sushi|seafood',
    ),
    '🐟',
  ),
  (
    _words(
      'chicken|beef|pork|duck|turkey|steak|ham|sausage|bacon|lamb|veal|schnitzel|cutlet|kebab|meat|mince|meatball',
    ),
    '🍖',
  ),
  (
    _words('milk|kefir|yogurt|yoghurt|juice|soda|cola|lemonade|drink|water'),
    '🥛',
  ),
  (
    _words(
      'apple|banana|orange|plum|peach|pear|grape|mango|pineapple|berry|berries|strawberry|strawberries|blueberry|blueberries|cherry|cherries|melon|watermelon|kiwi|fruit|apricot|lemon|lime',
    ),
    '🍎',
  ),
  (
    _words(
      'salad|lettuce|spinach|carrot|tomato|tomatoes|cucumber|broccoli|cabbage|coleslaw|vegetable|veggie|pepper|beetroot|potato|potatoes|lentil|bean|pea|onion|zucchini',
    ),
    '🥗',
  ),
];
