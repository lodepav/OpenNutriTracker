import 'package:opennutritracker/fork/food/sauce_serving.dart';

/// What a cooked main dish with no stated amount and no serving starts at: a
/// plate (S98), the 300 g of a soup's bowl and of the fork's own plov. 100 g,
/// every other food's start, is a third of a plate: a photo's spaghetti
/// bolognese logged 85 kcal against 510, its plov's pilaf 167 against 753.
const dishServingGrams = 300.0;

/// The same in ounces, for an imperial profile.
const dishServingOz = 10.5;

final _dish = RegExp(
  r'\b(pilaf|pilau|plov|risotto|paella|biryani|jambalaya|bolognese|'
  r'carbonara|lasagn[ae]|goulash|stews?|curry|casserole|stroganoff|'
  r'ragout|rag[uù]|moussaka|chili con carne|fried rice|pad thai|lo mein|'
  r'chow mein|mac(aroni)? (and|&|n) cheese|shepherd.?s pie|cottage pie|'
  r'porridge|stuffed cabbage|cabbage rolls?|golubtsy|'
  r'(macaroni|pasta|spaghetti|penne|noodles) (with|in|and))\b',
  caseSensitive: false,
);

/// What a dish's name holds when it is not a plate of it: something to
/// make it with, a sausage with the dish's spice ("Curry-Bratwurst"), a
/// baby's jar or a sweet bake.
final _notTheDish = RegExp(
  r'\b(seasoning|paste|powder|mix|dry|dehydrated|concentrate|'
  r'spices?|cubes?|granules|kit|babyfood|toddler|chocolate|sweet|dessert)\b|'
  r'wurst|sausage',
  caseSensitive: false,
);

/// Whether [name] is a cooked main dish a plate of is the usual amount.
/// A sauce for one is not ("Bolognese sauce"); pasta in one is ("pasta
/// with meat sauce").
bool isMainDish(String? name) =>
    name != null &&
    _dish.hasMatch(name) &&
    !_notTheDish.hasMatch(name) &&
    !isSauce(name);
