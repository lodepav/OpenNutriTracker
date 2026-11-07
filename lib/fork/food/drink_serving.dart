/// What a drink with no stated amount starts at, in ml: a glass or a mug
/// (S98). 100 ml, every other food's start, is a third of a glass: a
/// photo's juice and tea logged at 100 each.
const drinkServingMl = 250.0;

/// The same in fluid ounces, for an imperial profile: a cup.
const drinkServingFlOz = 8.0;

final _drink = RegExp(
  r'\b(juices?|tea|coffee|cocoa|hot chocolate|lemonade|soda|cola|smoothies?|'
  r'kefir|kompot|kvass|beer|cider|water|milkshakes?|latte|cappuccino)\b',
  caseSensitive: false,
);

/// What a drink's name holds when it is not the drink: a cake, the dry
/// leaves or beans, a powder.
final _notTheDrink = RegExp(
  r'\b(cakes?|biscuits?|cookies?|buns?|bread|ice cream|jelly|powder|'
  r'granules|beans|leaves|bags?|chestnuts?|crackers?|ground|instant)\b',
  caseSensitive: false,
);

/// A food served in a drink is the food ("Rice, cooked in water").
final _servedIn = RegExp(
  r'\b(with|in|cooked|boiled|from)\b[^,]*',
  caseSensitive: false,
);

/// Whether [name] is a drink a glass or mug of is the usual amount.
bool isDrink(String? name) {
  if (name == null) return false;
  final food = name.replaceAll(_servedIn, '');
  return _drink.hasMatch(food) && !_notTheDrink.hasMatch(name);
}
