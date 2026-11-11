/// The row a bare name means where the table's own order misses it (S75).
/// Every "Egg" and "Pizza" row ties on the title, and the shortest-name key
/// picked the odd ones: "egg" logged "Egg, creamed", "eggs" a yolk,
/// "pizza" "Pizza, no cheese, thin crust". Other names find the row a
/// word holds rather than the food: "fries" logged "Yuca fries", "tomato
/// sauce" a steak sauce, "granola" a cookie. Some name the food in words
/// its row does not use: "coke" found nothing, "unsalted butter" a pretzel
/// ("Butter, without salt"), "porridge" a savoury BLS one (oatmeal). The
/// data source adds the row by its name, and the resolver takes it as the
/// match.
///
/// A key also stands for its other spellings: its words with any commas
/// ("pork cutlet, breaded, fried" for "pork, cutlet, breaded, fried", a
/// karbonāde that found minced pork patties), "boiled" for "cooked"
/// ("spaghetti, boiled" found spaghetti squash, which holds both words), and
/// the state before the food ("cooked spaghetti" for "spaghetti, cooked") or
/// after it ("eggs, scrambled" for "scrambled eggs").
String? everydayRowName(String query) {
  final key = query.trim().toLowerCase();
  final words = _words(key);
  if (_byWords[words] case final name?) return name;
  final cooked = words.replaceAll(_boiled, 'cooked');
  if (_byWords[cooked] case final name?) return name;
  if (_stateFirst.firstMatch(cooked) case final m?) {
    if (_byWords['${m[2]} ${m[1]}'] case final name?) return name;
  }
  // and the state after the food, as a model names it: "eggs, scrambled"
  // is scrambled eggs, which found the frozen mixture
  for (final form in {words, cooked}) {
    if (_stateLast.firstMatch(form) case final m?) {
      if (_byWords['${m[2]} ${m[1]}'] case final name?) return name;
    }
  }
  if (_plainMeat.firstMatch(key) case final m?) {
    // a chop the table has fried as such: "pork chop, pan-fried" is the
    // pan-fried chop, not one of any cooking
    if (m[1] == 'pork chop' && _fried.hasMatch(key)) return null;
    return _meats[m[1]! + (m[2] == null ? '' : ' ground')];
  }
  return null;
}

/// [text]'s words, one space apart.
String _words(String text) => text
    .split(RegExp(r'[^\p{L}\p{N}-]+', unicode: true))
    .where((w) => w.isNotEmpty)
    .join(' ');

final _byWords = {
  for (final MapEntry(:key, :value) in _everyday.entries) _words(key): value,
};

/// A meat named with only how it was cooked or cut: "beef, cooked",
/// "pork, cooked, roasted", "cooked sliced beef", "beef, ground, cooked,
/// pan-browned", "pork chop, grilled". Its rows add the part or the
/// product to those words, and the shortest one picked was the odd one:
/// "beef, cooked" logged beef bacon at 449 kcal per 100 g in a stuffed
/// pepper and a solyanka, "pork, cooked, roasted" fatty backribs, "pork
/// chop" a stuffed one, "pork, cooked, stir-fried" pan-fried bacon. The
/// generic row is the meat as a dish holds it.
final _plainMeat = RegExp(
  r'^(?:(?:cooked|roasted|boiled|stewed|braised|sliced|grilled|baked|'
  r'fried|stir[- ]fried|pan[- ]fried|saut[eé]ed)[ ,]+)*'
  r'(beef|pork chop|pork|lamb|turkey)s?'
  r'(?:,? (ground|minced|mince))?'
  r'(?:(?:,\s*| )(?:cooked|roasted|boiled|stewed|braised|sliced|grilled|'
  r'baked|pan-browned|simmered|meat|lean|fried|stir[- ]fried|pan[- ]fried|'
  r'saut[eé]ed))*$',
);

const _meats = {
  'beef': 'Beef, NFS',
  'pork': 'Pork, NFS',
  'pork chop': 'Pork, chop, NS as to fat eaten',
  'lamb': 'Lamb, NS as to cut',
  'turkey': 'Turkey, NFS',
  'beef ground': 'Beef, ground, unspecified fat content, cooked',
  'pork ground': 'Pork, fresh, ground, cooked',
};

final _boiled = RegExp(r'\bboiled\b');
final _fried = RegExp(r'\bfried\b|saut[eé]ed');

/// "cooked spaghetti": a state word, then the food.
final _stateFirst = RegExp(r'^(cooked|fried|grilled|baked|roasted) (.+)$');

/// "eggs scrambled": the food, then a state word.
final _stateLast = RegExp(
  r'^(.+) (cooked|boiled|fried|grilled|baked|roasted|scrambled)$',
);

/// Whether [name] is the row [query] means (see [everydayRowName]).
bool isEverydayRow(String? name, String query) =>
    name != null && everydayRowName(query) == name;

const _everyday = {
  'egg': 'Egg, whole, raw, fresh',
  // a frozen mixture at 1 oz, 37 kcal for a plate's eggs
  'scrambled eggs': _scrambledEgg,
  'scrambled egg': _scrambledEgg,
  // "Tea, ginger" is the shortest tea
  'tea': _blackTea,
  'black tea': _blackTea,
  'eggs': 'Eggs, Grade A, Large, egg whole',
  'pizza': _cheesePizza,
  'cheese pizza': _cheesePizza,
  'fries': _fries,
  'french fries': _fries,
  'chips': _fries,
  // A dish that holds the words won: chicken "with sauce, skin eaten", a beef
  // stew in a sauce, a baby food.
  'grilled chicken breast':
      'Chicken breast, grilled without sauce, skin not eaten',
  'mushroom cream sauce':
      'Button mushroom sauce, from white basic sauce, cream and white wine',
  'baby potatoes': _boiledPotato,
  'cutlet': 'Veal, leg, top round, cap off, cutlet, boneless, cooked, grilled',
  'tomato sauce': 'Tomato products, canned, sauce',
  'tomato paste': _tomatoPaste,
  'potato': _boiledPotato,
  'potatoes': _boiledPotato,
  'boiled potato': _boiledPotato,
  'boiled potatoes': _boiledPotato,
  'porridge': _oatmeal,
  'oatmeal': _oatmeal,
  'oat porridge': _oatmeal,
  'oatmeal porridge': _oatmeal,
  // a Nordic and Baltic breakfast: rice cooked in milk, often with jam
  'rice porridge': 'Rice pudding sweetened, with milk 3.5 % fat',
  'milk rice porridge': 'Rice pudding sweetened, with milk 3.5 % fat',
  // Latvian maizes zupa: rye bread soup with raisins and apple, served with
  // cream.
  'bread soup': 'Bread soup (brown bread), with raisins, apple and sour cream',
  'maizes zupa': 'Bread soup (brown bread), with raisins, apple and sour cream',
  'maizes zupa ar putukrējumu':
      'Bread soup (brown bread), with raisins, apple and sour cream',
  // a Latvian karbonāde is a breaded pork schnitzel
  'karbonāde': 'Pork schnitzel breaded, fried',
  'panēta karbonāde': 'Pork schnitzel breaded, fried',
  'karbonade': 'Pork schnitzel breaded, fried',
  // Baltic smoked sprats in oil, from the tin
  'šprotes': 'Sprat, in oil, canned, drained',
  'sprotes': 'Sprat, in oil, canned, drained',
  'шпроты': 'Sprat, in oil, canned, drained',
  'shproty': 'Sprat, in oil, canned, drained',
  'sprats': 'Sprat, in oil, canned, drained',
  'sprats in oil': 'Sprat, in oil, canned, drained',
  'golubtsi': 'Stuffed cabbage rolls with beef and rice',
  'kāpostu tīteņi': 'Stuffed cabbage rolls with beef and rice',
  'голубцы': 'Stuffed cabbage rolls with beef and rice',
  'cabbage rolls': 'Stuffed cabbage rolls with beef and rice',
  'draniki': 'Potato pancake',
  'kartupeļu pankūkas': 'Potato pancake',
  'драники': 'Potato pancake',
  // "pita" found pita chips, 3 g a chip
  'pita': 'Bread, pita',
  'pitas': 'Bread, pita',
  // a Bavarian lye pretzel; "pretzel" found the 3 g snack
  'pretzel': 'Pretzel, salted',
  'pretzels': 'Pretzel, salted',
  // "kiwi" found the stewed one, without a piece
  'kiwi': 'Kiwi fruit, raw',
  'kiwis': 'Kiwi fruit, raw',
  'weisswurst': 'Bavarian white sausage',
  'weißwurst': 'Bavarian white sausage',
  'weisswürste': 'Bavarian white sausage',
  'weißwürste': 'Bavarian white sausage',
  'butter, unsalted': _unsaltedButter,
  'unsalted butter': _unsaltedButter,
  'cola': _cola,
  'coke': _cola,
  'coca cola': _cola,
  'coca-cola': _cola,
  'diet coke': _dietCola,
  'coke zero': _dietCola,
  'diet cola': _dietCola,
  'pepsi max': _dietCola,
  'greek yogurt': _greekYogurt,
  'greek yoghurt': _greekYogurt,
  'granola': 'Cereal, granola',
  // "gravy, brown" logged the dry granules, then a brown rice with gravy,
  // which holds both words.
  'gravy, brown': _gravy,
  // "meatball" logged a dish in sauce; see _meatballs.
  'meatball': _meatballs,
  'fried meatballs': _meatballs,
  'meatballs, fried': _meatballs,
  'brown gravy': _gravy,
  'gravy, meat': _gravy,
  // fried rice, by the shorter name
  'rice': _longGrainRice,
  'rice, cooked': _longGrainRice,
  'basmati rice': _longGrainRice,
  'jasmine rice': _longGrainRice,
  // A soup's broth, which found canned chicken "with broth" and a dry
  // bouillon cube at 170 kcal per 100 g, tripling a bowl of soup. Ready to
  // serve, not home-made stock (36 kcal per 100 ml): on 17 soups the median
  // miss fell from 24% to 20%.
  'chicken broth': _chickenStock,
  'chicken stock': _chickenStock,
  'beef broth': _beefStock,
  'beef stock': _beefStock,
  'vegetable broth': 'Soup, vegetable broth, ready to serve',
  'vegetable stock': 'Soup, vegetable broth, ready to serve',
  // a curry's or soup's coconut milk, which found the carton drink at 31
  // kcal per 100 ml; the photo path is for meals, not drinks
  'coconut milk': _cannedCoconutMilk,
  'coconut milk, canned': _cannedCoconutMilk,
  'coconut milk, full fat': _cannedCoconutMilk,
  // a burger's bun, which found a whole hamburger
  'hamburger bun': _burgerBun,
  'hamburger bun, plain': _burgerBun,
  'burger bun': _burgerBun,
  'bread, hamburger bun': _burgerBun,
  'bun, hamburger': _burgerBun,
  'roll, hamburger': _burgerBun,
  // a spinach or protein-fortified one, by the shorter name
  'spaghetti': _pasta,
  'spaghetti, cooked': _pasta,
  'spaghetti, cooked, enriched': _pasta,
  'spaghetti, whole-wheat, cooked': _wholeWheatPasta,
  'pasta, whole-wheat, cooked': _wholeWheatPasta,
  // glutinous rice, at half the energy of fried
  'fried rice': _friedRice,
  'rice, fried': _friedRice,
  'rice, white, fried': _friedRice,
  'rice, white, cooked, fried': _friedRice,
  // a frozen bag, unprepared
  'potatoes, roasted': _roastPotato,
  'potato, roasted': _roastPotato,
  'roasted potatoes': _roastPotato,
  'roast potatoes': _roastPotato,
  // a frozen bag, unprepared
  'potatoes, fried': _fries,
  'potato, fried': _fries,
  // A photo's pan-fried potatoes, as a person names them, logged french
  // fries (the table's names above stay fries).
  'fried potato': _homeFries,
  'fried potatoes': _homeFries,
  'pan-fried potatoes': _homeFries,
  'pan fried potatoes': _homeFries,
  'potatoes, pan-fried': _homeFries,
  'sauteed potatoes': _homeFries,
  'sautéed potatoes': _homeFries,
  'potatoes, sauteed': _homeFries,
  'home fries': _homeFries,
  // A photo's bacon logged a pan-fried row by its 3 oz serving; this one
  // counts in slices (`servingOverrides`).
  'fried bacon': _bacon,
  'bacon, fried': _bacon,
  'crispy bacon': _bacon,
  'bacon, crispy': _bacon,
  'bacon rashers': _bacon,
  'bacon strips': _bacon,
  'bacon slices': _bacon,
  // the only onion gravy is a dry mix, at six times the energy
  'gravy, onion': _gravy,
  'onion gravy': _gravy,
  'gravy': _gravy,
  // no vinaigrette row: a mayonnaise dressing was found
  'vinaigrette': _vinaigrette,
  'salad dressing, vinaigrette': _vinaigrette,
  'salad dressing, vinaigrette, regular': _vinaigrette,
  'balsamic vinaigrette': _vinaigrette,
  // a salad's or a soup's, not the light one the shortest name found
  'sour cream': 'Cream, sour, cultured',
  // a sauce cooked from tomatoes, which found herring in tomato sauce
  'tomato sauce, cooked': 'Tomato products, canned, sauce',
  // rice with soy sauce
  'white sauce': _bechamel,
  'white sauce, prepared with milk': _bechamel,
  'bechamel': _bechamel,
  // raw red lentils, at three times the energy
  'lentils, cooked': _cookedLentils,
  'lentils, red, cooked': _cookedLentils,
  'red lentils, cooked': _cookedLentils,
  // dry fried chow mein noodles, at three times the energy
  'noodles, chinese, cooked': _cookedNoodles,
  'noodles, wheat, cooked': _cookedNoodles,
  'noodles, ramen, cooked': _cookedNoodles,
  'ramen noodles, cooked': _cookedNoodles,
  'chow mein noodles, cooked': _cookedNoodles,
  'lo mein noodles, cooked': _cookedNoodles,
  // a mint julep
  'mint': _mint,
  'mint, fresh': _mint,
  'mint leaves': _mint,
  // fried chicken liver
  'chicken, fried': _friedChicken,
  'fried chicken': _friedChicken,
  // a baby food, or nothing
  'dumplings': _steamedDumpling,
  'dumplings, steamed': _steamedDumpling,
  'dumplings, vegetable, cooked': _steamedDumpling,
  'gyoza': _friedDumpling,
  'potstickers': _friedDumpling,
  'pot stickers': _friedDumpling,
  'tzatziki': _tzatziki,
  'tzatziki sauce': _tzatziki,
  // a spaghetti and meatballs plate
  'meatballs': _meatballs,
  'meatballs, cooked': _meatballs,
  'meatballs, beef and pork, cooked': _meatballs,
  // rye bread
  'bread, hamburger or hotdog bun, plain': _burgerBun,
  'bread, hamburger or hot dog bun': _burgerBun,
  // raw
  'eggplant, roasted': _cookedEggplant,
  'eggplant, grilled': _cookedEggplant,
  // boiled, no sugar
  'apple, baked': 'Apple, baked',
  'apples, baked': 'Apple, baked',
  'apples, cooked, baked, with sugar': 'Apple, baked',
  // a vegetable macaroni
  'macaroni, cooked': _pasta,
  'macaroni, cooked, enriched': _pasta,
  'sticky rice': 'Rice, white, cooked, glutinous',
  // one made from a dry mix
  'flan': 'Flan',
  'flan, caramel custard': 'Flan',
  // the brain, a Mexican stew of ground meat, or a frozen meal
  'beef, stewed': _stewBeef,
  'beef, cooked, simmered': _stewBeef,
  'beef, sliced, cooked': 'Beef, NFS',
  'pork and beef, ground, cooked':
      'Beef, ground, unspecified fat content, cooked',
  // chorizo
  'pork, ground, cooked, fried': 'Pork, fresh, ground, cooked',
  // rye bread, or a cracker at 412 kcal per 100 g
  'flatbread': _flatbread,
  'bread, flatbread': _flatbread,
  'bread, italian or french': 'Bread, Italian',
  // the low carbohydrate one, by the word regular
  'ice cream, vanilla, regular': 'Ice cream, vanilla',
  // red cabbage
  'cabbage, cooked': 'Cabbage, green, cooked, no added fat',
  // shark, the one batter-dipped fish
  'fish, battered, fried': _batteredFish,
  'fish, breaded, fried': _batteredFish,
  // Italian ice, at 128 kcal per 100 g; a shaved ice's syrup is its own
  'ice, shaved': 'Water, tap',
  // a pasta dish with fried onions
  'onions, cooked, fried': _sauteedOnions,
  // a lotus-seed pastry, or puff pastry
  'pastry, phyllo, baked': _phyllo,
  'pastry dough, phyllo, baked': _phyllo,
  'pastry, phyllo, dough': _phyllo,
  'phyllo dough, baked': _phyllo,
  'pastry, pie crust, baked': _pieCrust,
  // salt pork, at 748 kcal per 100 g
  'pork, cured, prosciutto': _prosciutto,
  'prosciutto': _prosciutto,
  // a pork chop with cheese
  'pork, cutlet, breaded, fried': _schnitzel,
  'pork schnitzel': _schnitzel,
  // frozen, unprepared
  'potatoes, french fried': _fries,
  'potatoes, french fried, salted': _fries,
  // dry rice noodles, at three times the energy
  'rice noodles, stir-fried': _cookedRiceNoodles,
  'noodles, rice, stir-fried': _cookedRiceNoodles,
  // nothing
  'snow peas, cooked': _cookedSnowPeas,
  'snow peas, stir-fried': _cookedSnowPeas,
  'soy sauce made from soybeans and wheat': 'Soy sauce',
  // frozen, unprepared
  'wontons, pork, cooked': _steamedDumpling,
  'wontons, cooked': _steamedDumpling,
  // A photo's herbs found "Pickles, dill" and Open Food Facts rows with no
  // serving, at 100 g.
  'dill': _dill,
  'fresh dill': _dill,
  'dill weed': _dill,
  'parsley': _parsley,
  'fresh parsley': _parsley,
  'cilantro': _cilantro,
  'fresh cilantro': _cilantro,
  'coriander': _cilantro,
  'fresh coriander': _cilantro,
  'green onion': _greenOnion,
  'green onions': _greenOnion,
  'spring onion': _greenOnion,
  'spring onions': _greenOnion,
  'scallion': _greenOnion,
  'scallions': _greenOnion,
  // an Open Food Facts tub with no serving, at 100 g
  'parmesan': _parmesan,
  'parmesan cheese': _parmesan,
  'grated parmesan': _parmesan,
  'grated parmesan cheese': _parmesan,
  // an Open Food Facts product with no serving: 3 peppers were 3 g
  'stuffed pepper': _stuffedPepper,
  'stuffed peppers': _stuffedPepper,
  'stuffed bell pepper': _stuffedPepper,
  'stuffed bell peppers': _stuffedPepper,
  // a butter product at 357 kcal per 100 g
  'mashed potatoes with butter': _butterMash,
  'mashed potato with butter': _butterMash,
  // no row names a baguette
  'baguette': _baguette,
  'toasted baguette': _toastedBaguette,
  // The shortest of each family, which a search for the family found:
  // salt pork at 748 kcal per 100 g, oat oil, a pasta with herb pesto.
  'pork, cured': _ham,
  'cured pork': _ham,
  'oil': _vegetableOil,
  'cooking oil': _vegetableOil,
  'herbs, fresh, mixed': _parsley,
  'herbs, fresh': _parsley,
  'fresh herbs': _parsley,
  'mixed herbs': _parsley,
  'mixed fresh herbs': _parsley,
  'fresh mixed herbs': _parsley,
  // chamomile tea, by "herb"
  'herbs': _parsley,
  'herbs, garnish': _parsley,
  'herbs, fresh, garnish': _parsley,
  'fresh herbs, garnish': _parsley,
  'herb garnish': _parsley,
  // no row names wheat berries; Open Food Facts found a whey protein
  'wheat berries': _wheatBerries,
  'wheat berries, cooked': _wheatBerries,
  'wheat berries, boiled': _wheatBerries,
  'cooked wheat berries': _wheatBerries,
  // the table's bell peppers are "sweet" or "bell", never both: nothing
  // was found, and online a jar of roasted strips
  'sweet bell pepper': _redPepper,
  'sweet bell pepper, raw': _redPepper,
  'sweet bell peppers': _redPepper,
  'sweet bell peppers, raw': _redPepper,
  'bell pepper, sweet, raw': _redPepper,
  // a pizza margherita, made with tomato sauce
  'tomato sauce, pizza': _pizzaSauce,
  'pizza sauce': _pizzaSauce,
  'sauce, pizza': _pizzaSauce,
  // a coleslaw dressing, which holds both words; "Sausage, NFS" for a
  // chicken one
  'coleslaw salad': 'Coleslaw',
  'salad, coleslaw': 'Coleslaw',
  'chicken apple sausage': _chickenSausage,
  'chicken and apple sausage': _chickenSausage,
  // a deli roll of pressed breast, by the shorter name
  'roasted chicken breast': _roastChickenBreast,
  'roast chicken breast': _roastChickenBreast,
  // Bread rolls by the kind of roll, which found rye bread on "bread" or a
  // bread dumpling. No row names ciabatta: a hard white roll is the nearest.
  'bread, multigrain roll': _multigrainRoll,
  'multigrain roll': _multigrainRoll,
  'multigrain bread roll': _multigrainRoll,
  'bread roll with seeds': _multigrainRoll,
  'seeded roll': _multigrainRoll,
  'seeded bread roll': _multigrainRoll,
  'bread roll, white': _whiteRoll,
  'white bread roll': _whiteRoll,
  'white roll': _whiteRoll,
  'bread roll': _whiteRoll,
  'ciabatta': _hardRoll,
  'ciabatta roll': _hardRoll,
  'ciabatta bread': _hardRoll,
  // no pizza crust row; a flatbread pizza is a thin one
  'flatbread pizza crust': _flatbread,
  'pizza crust, flatbread': _flatbread,
  // a moon cake, or a frozen turnover with egg and cheese
  'meat pastry': _meatPastry,
  'pastry filled with meat': _meatPastry,
  'pastry filled with meat and tomato': _meatPastry,
  'pastry filled with meat and vegetable': _meatPastry,
  'pastry filled with meat and vegetables': _meatPastry,
  'meat-filled pastry': _meatPastry,
  'meat turnover': _meatPastry,
  'meat turnovers': _meatPastry,
  // a pizza with no cheese, the shortest name
  'thin-crust pizza': _thinCrustPizza,
  'thin crust pizza': _thinCrustPizza,
  'pizza, thin crust': _thinCrustPizza,
  'pizza, thin-crust': _thinCrustPizza,
  'flatbread pizza': _thinCrustPizza,
  // falafel in a flatbread
  'falafel, fried': _falafel,
  'falafel, deep-fried': _falafel,
  'fried falafel': _falafel,
  // a dry cervelat with lamb at 371 kcal per 100 g
  'lamb sausage': _sausage,
  'lamb sausages': _sausage,
  'merguez': _sausage,
  'merguez sausage': _sausage,
  // liver spaetzle; the table's own spaetzle are raw dough
  'spaetzle': _eggNoodles,
  'spätzle': _eggNoodles,
  'spaetzle, cooked': _eggNoodles,
  // green tea, by "leaf" and "green"
  'leafy greens, cooked': _cookedGreens,
  'cooked leafy greens': _cookedGreens,
  'greens, cooked': _cookedGreens,
  'cooked greens': _cookedGreens,
  // a berry bar
  'mixed berries': _berries,
  'mixed berries, fresh': _berries,
  'fresh mixed berries': _berries,
  'berries, mixed': _berries,
  'mixed berries, frozen': 'Berries, frozen',
  // pork shoulder, by "butt"
  'butter, cooked': _butter,
  'butter, melted': _butter,
  'melted butter': _butter,
  // a frozen sweet potato, the only row with every word
  'potatoes, cooked, baked': _bakedPotato,
  'potato, cooked, baked': _bakedPotato,
  'baked potato': _bakedPotato,
  'baked potatoes': _bakedPotato,
  // raw cabbage; a lasagna al forno; red beans and rice
  'cabbage, sauerkraut': 'Sauerkraut',
  'pasta, lasagna sheets': _pasta,
  'lasagna sheets': _pasta,
  'lasagna noodles': _pasta,
  'lasagna sheets, cooked': _pasta,
  // no red rice cooked: brown rice is the nearest whole grain rice
  'rice, red, cooked': _brownRice,
  'red rice, cooked': _brownRice,
  'red rice': _brownRice,
  // a flourless one, by the shortest name
  'chocolate cake': _chocolateCake,
  'cake, chocolate': _chocolateCake,
  // a salad in lemon marinade at 116 kcal per 100 g
  'mixed salad': _salad,
  'salad, mixed': _salad,
  'green salad': _salad,
  'side salad': _salad,
  // the cooked groats row, named like the dry one: only a word for dry
  // names the dry product
  'buckwheat groats, dry': _dryBuckwheat,
  'buckwheat groats, raw': _dryBuckwheat,
  'buckwheat groats, uncooked': _dryBuckwheat,
  'dry buckwheat groats': _dryBuckwheat,
  'raw buckwheat groats': _dryBuckwheat,
  // chocolate milk
  'milk chocolate': _milkChocolate,
  'chocolate, milk': _milkChocolate,
  // a truffle pâté or torte
  'truffle': _truffles,
  'truffles': _truffles,
  'chocolate truffle': _truffles,
  'chocolate truffles': _truffles,
  // nothing, or olives at half the energy: kalamata are brine-cured and
  // denser than canned ripe olives
  'kalamata olives': _brinedOlives,
  'kalamata olive': _brinedOlives,
  'olives, kalamata': _brinedOlives,
  // a sweet pickle relish
  'pickled red onion': _pickledOnion,
  'pickled red onions': _pickledOnion,
  'pickled onion': _pickledOnion,
  'pickled onions': _pickledOnion,
  'red onion, pickled': _pickledOnion,
  'onions, pickled': _pickledOnion,
  // sweet and sour pork, a sweet roll, or nothing
  'sour sweets': _gummies,
  'fruit jelly sweets': _gummies,
  'jelly sweets': _gummies,
  'gummy sweets': _gummies,
  'gummies': _gummies,
  'gummy bears': _gummies,
  'gummy candy': _gummies,
  'jelly candy': _gummies,
  'jelly candies': _gummies,
  'wine gums': _gummies,
  'sour gummies': _gummies,
  // a no-bake marshmallow cookie; fortune cookies, by the shortest name
  'oat cookies': _oatmealCookie,
  'oat cookie': _oatmealCookie,
  'oatmeal cookies': _oatmealCookie,
  'oatmeal cookie': _oatmealCookie,
  'cookies': _cookie,
  'cookie': _cookie,
  // a sandwich spread
  'chicken salad': _chickenGardenSalad,
  // Canned sockeye, by "salmon": no row is glazed with teriyaki.
  'teriyaki salmon': _cookedSalmon,
  'salmon teriyaki': _cookedSalmon,
  'salmon, teriyaki': _cookedSalmon,
  // boiled potatoes, by "potato"
  'potato wedges': _roastPotato,
  'potato wedges, baked': _roastPotato,
  'baked potato wedges': _roastPotato,
  // a bratwurst with mustard, by the title
  'rostbratwurst': 'Rostbratwurst sausage, grilled',
  'rostbratwurst, grilled': 'Rostbratwurst sausage, grilled',
  // a gyros burger, or nothing; no row adds the bacon
  'bacon burger': _cheeseburger,
  'bacon cheeseburger': _cheeseburger,
  // The BLS singular rows have no portion, where the plural ones do.
  'strawberry': _strawberries,
  'strawberry, raw': _strawberries,
  'fresh strawberry': _strawberries,
  'blueberry': _blueberries,
  'blueberry, raw': _blueberries,
  'fresh blueberry': _blueberries,
  'blackberry': _blackberries,
  'blackberry, raw': _blackberries,
  'fresh blackberry': _blackberries,
  // nothing
  'salty licorice': _licorice,
  'salty liquorice': _licorice,
  'salmiak': _licorice,
  // nothing: Turkish delight is a starch jelly
  'turkish delight': _starchJelly,
  'lokum': _starchJelly,
  // nothing: dried, not fried like banana chips
  'dried banana': _driedBanana,
  'dried banana flakes': _driedBanana,
  'banana flakes': _driedBanana,
  'dried banana slices': _driedBanana,
  // the plain table row without a portion, at the same energy
  'multigrain flakes': _multigrainFlakes,
  'multigrain porridge flakes': _multigrainFlakes,
  // canned foods, by "canne"
  'cannele': _canele,
  'cannelé': _canele,
  'canele': _canele,
  'canelé': _canele,
  'caneles': _canele,
  'canelés': _canele,
  // a kebab wrap is the shawarma wrap; no row names the wrap otherwise
  'chicken kebab wrap': _shawarmaWrap,
  'kebab wrap': _shawarmaWrap,
  'döner wrap': _shawarmaWrap,
  'doner wrap': _shawarmaWrap,
  'doner kebab wrap': _shawarmaWrap,
  'kebab in lavash': _shawarmaWrap,
  'chicken kebab in lavash': _shawarmaWrap,
  // a marzipan cake or the raw paste
  'marzipan in dark chocolate': _marzipanChocolate,
  'chocolate marzipan': _marzipanChocolate,
  'marzipan chocolate': _marzipanChocolate,
  'chocolate-covered marzipan': _marzipanChocolate,
  'chocolate covered marzipan': _marzipanChocolate,
  'dark chocolate marzipan': _marzipanChocolate,
  // Nothing: no row is the Thai sauce; the sweet and sour one is the
  // nearest sugar-based dipping sauce.
  'sweet chili sauce': _sweetSourSauce,
  'sweet chilli sauce': _sweetSourSauce,
  'sweet chili': _sweetSourSauce,
};

const _cheesePizza =
    'Pizza, cheese, from restaurant or fast food, NS as to type of crust';
const _fries = 'Potato, french fries, NFS';
const _homeFries = 'Potato, home fries, from fresh';
const _bacon = 'Bacon, NS as to type of meat, cooked';
const _tomatoPaste =
    'Tomato products, canned, paste, without salt added (Includes foods for '
    "USDA's Food Distribution Program)";
const _boiledPotato =
    'Potatoes, boiled, cooked without skin, flesh, without salt';
const _scrambledEgg = 'Egg, whole, cooked, scrambled';
const _blackTea = 'Tea, hot, leaf, black';
const _oatmeal = 'Oatmeal, regular or quick, made with water, no added fat';
const _unsaltedButter = 'Butter, without salt';
const _cola = 'Soft drink, cola';
const _longGrainRice = 'Rice, white, long-grain, regular, enriched, cooked';
const _dietCola = 'Soft drink, cola, diet';
const _chickenStock = 'Soup, chicken broth, ready-to-serve';
const _cannedCoconutMilk =
    'Nuts, coconut milk, canned (liquid expressed from grated meat and water)';
const _beefStock = 'Soup, beef broth or bouillon canned, ready-to-serve';
const _burgerBun = 'Roll, white, hamburger bun';
const _pasta = 'Pasta, cooked';
const _wholeWheatPasta =
    "Pasta, whole-wheat, cooked (Includes foods for USDA's Food Distribution "
    'Program)';
const _friedRice = 'Rice, fried, NFS';
const _roastPotato = 'Potato, roasted, NFS';
// Not "Gravy, beef, canned" (the same energy): its serving is the 233 g
// can, which a plate's gravy logged with no amount stated.
const _gravy = 'Gravy, NFS';
const _vinaigrette = 'Salad dressing, home recipe, vinegar and oil';
const _bechamel = 'Bechamel sauce';
const _cookedLentils = 'Lentils, mature seeds, cooked, boiled, with salt';
const _cookedNoodles = 'Noodles, cooked';
const _mint = 'Spearmint, fresh';
const _dill = 'Dill weed, fresh';
const _parsley = 'Parsley, raw';
const _cilantro = 'Coriander (cilantro) leaves, raw';
const _greenOnion = 'Onions, green, raw';
const _parmesan = 'Cheese, parmesan, grated';
const _stuffedPepper = 'Stuffed pepper, with rice and meat';
const _butterMash =
    'Potatoes, mashed, home-prepared, whole milk and butter added';
const _baguette = 'Bread, French or Vienna';
const _toastedBaguette = 'Bread, French or Vienna, toasted';
const _friedChicken =
    'Chicken, broilers or fryers, meat and skin, cooked, fried, batter';
const _steamedDumpling = 'Wonton, dumpling or pot sticker, steamed';
const _friedDumpling = 'Wonton, dumpling or pot sticker, fried';
const _tzatziki = 'Tzatziki dip';
// Not "Meatballs, frozen, Italian style" (286 kcal, by now 269): its
// serving is 3 oz, so a photo's 8 meatballs read as 8 × 85 g. This row
// takes a 30 g piece (`addedPieces`).
const _meatballs = 'Meatballs, fried';
const _cookedEggplant = 'Eggplant, cooked, fat added';
const _greekYogurt = 'Yogurt, Greek, NS as to type of milk, plain';
const _stewBeef = 'Beef, stew meat';
const _flatbread = 'Wheat flatbread';
const _batteredFish =
    'Restaurant, family style, fish fillet, battered or breaded, fried';
const _sauteedOnions = 'Onions, yellow, sauteed';
const _phyllo = 'Phyllo dough';
const _pieCrust = 'Pie crust, refrigerated, regular, baked';
const _prosciutto = 'Ham, prosciutto';
const _schnitzel = 'Pork schnitzel breaded, fried';
const _cookedRiceNoodles = 'Rice noodles, cooked';
const _cookedSnowPeas = 'Snowpeas, fresh, cooked, no added fat';
const _ham = 'Ham, sliced, regular (approximately 11% fat)';
const _vegetableOil = 'Vegetable oil, NFS';
const _wheatBerries = 'Wheat whole grain, boiled';
const _redPepper = 'Peppers, sweet, red, raw';
const _pizzaSauce = 'Sauce, pizza, canned, ready-to-serve';
const _chickenSausage = 'Turkey or chicken sausage';
const _roastChickenBreast =
    'Chicken breast, baked, broiled, or roasted, skin not eaten, from raw';
const _multigrainRoll = 'Roll, multigrain';
const _whiteRoll = 'Roll, white, soft';
const _hardRoll = 'Roll, white, hard';
const _meatPastry = 'Empanada, beef, with vegetables';
const _thinCrustPizza =
    'Pizza, cheese, from restaurant or fast food, thin crust';
const _falafel = 'Falafel, home-prepared';
const _sausage = 'Sausage, NFS';
const _eggNoodles = 'Noodles, egg, enriched, cooked';
const _cookedGreens = 'Greens, NS as to form, cooked';
const _berries = 'Berries, NFS';
const _butter = 'Butter, NFS';
const _bakedPotato = 'Potato, baked, NFS';
const _brownRice = 'Rice, brown, cooked, no added fat';
const _chocolateCake =
    'Cake or cupcake, chocolate with chocolate icing, bakery';
const _salad =
    'Salad, green, without dressing (garden salad, tossed salad, side salad)';
const _dryBuckwheat = 'Buckwheat groats, roasted, dry';
const _milkChocolate = 'Candies, milk chocolate';
const _truffles = 'Candies, truffles, prepared-from-recipe';
const _brinedOlives = 'Olives blackened, in brine, drained';
const _pickledOnion = 'Silverskin onion, pickled, drained';
const _gummies = 'Candy, gummy';
const _oatmealCookie = 'Cookie, oatmeal';
const _cookie = 'Cookie, NFS';
const _chickenGardenSalad =
    'Chicken or turkey garden salad, chicken and/or turkey, tomato and/or '
    'carrots, other vegetables, no dressing';
const _cookedSalmon = 'Fish, salmon, Atlantic, wild, cooked, dry heat';
const _cheeseburger = 'Cheeseburger, NFS';
const _strawberries = 'Strawberries, raw';
const _blueberries = 'Blueberries, raw';
const _blackberries = 'Blackberries, raw';
const _licorice = 'Candy, licorice';
const _starchJelly = 'Candies, gumdrops, starch jelly pieces';
const _driedBanana = 'Banana, dried';
const _sweetSourSauce = 'Sweet and sour sauce';
const _multigrainFlakes =
    'Multigrain flakes, porridge flakes, dry (multigrain porridge flakes, '
    '4-grain flakes, four grain flakes, 5-grain flakes, five grain flakes, '
    'mixed grain flakes, daudzgraudu pārslas)';
const _canele =
    'Canelé, French custard cake (canele, cannelé, cannele, canelé de '
    'Bordeaux, caneles)';
const _shawarmaWrap =
    'Shawarma, chicken, wrap (chicken shawarma, chicken gyros, gyros, '
    'shawarma wrap)';
const _marzipanChocolate =
    'Bittersweet/semisweet chocolate, filled with marzipan';
