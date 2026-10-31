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
String? everydayRowName(String query) => _everyday[query.trim().toLowerCase()];

/// Whether [name] is the row [query] means (see [everydayRowName]).
bool isEverydayRow(String? name, String query) =>
    name != null && everydayRowName(query) == name;

const _everyday = {
  'egg': 'Egg, whole, raw, fresh',
  'eggs': 'Eggs, Grade A, Large, egg whole',
  'pizza': _cheesePizza,
  'cheese pizza': _cheesePizza,
  'fries': _fries,
  'french fries': _fries,
  'chips': _fries,
  'tomato sauce': 'Tomato products, canned, sauce',
  'tomato paste': _tomatoPaste,
  'potato': _boiledPotato,
  'potatoes': _boiledPotato,
  'boiled potato': _boiledPotato,
  'boiled potatoes': _boiledPotato,
  'porridge': _oatmeal,
  'oatmeal': _oatmeal,
  'oat porridge': _oatmeal,
  // Latvian maizes zupa: rye bread soup with raisins and apple, served with
  // cream.
  'bread soup': 'Bread soup (brown bread), with raisins, apple and sour cream',
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
  // fried rice, by the shorter name
  'rice': _longGrainRice,
  'rice, cooked': _longGrainRice,
  'basmati rice': _longGrainRice,
  'jasmine rice': _longGrainRice,
  // A soup's broth, which found canned chicken "with broth" and a dry
  // bouillon cube at 170 kcal per 100 g, tripling a bowl of soup.
  'chicken broth': _chickenStock,
  'chicken stock': _chickenStock,
  'beef broth': _beefStock,
  'beef stock': _beefStock,
  'vegetable broth': 'Soup, vegetable broth, ready to serve',
  'vegetable stock': 'Soup, vegetable broth, ready to serve',
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
};

const _cheesePizza =
    'Pizza, cheese, from restaurant or fast food, NS as to type of crust';
const _fries = 'Potato, french fries, NFS';
const _tomatoPaste =
    'Tomato products, canned, paste, without salt added (Includes foods for '
    "USDA's Food Distribution Program)";
const _boiledPotato =
    'Potatoes, boiled, cooked without skin, flesh, without salt';
const _oatmeal = 'Oatmeal, regular or quick, made with water, no added fat';
const _unsaltedButter = 'Butter, without salt';
const _cola = 'Soft drink, cola';
const _longGrainRice = 'Rice, white, long-grain, regular, enriched, cooked';
const _dietCola = 'Soft drink, cola, diet';
const _chickenStock = 'Soup, stock, chicken, home-prepared';
const _beefStock = 'Soup, stock, beef, home-prepared';
const _burgerBun = 'Roll, white, hamburger bun';
const _pasta = 'Pasta, cooked';
const _wholeWheatPasta =
    "Pasta, whole-wheat, cooked (Includes foods for USDA's Food Distribution "
    'Program)';
const _friedRice = 'Rice, fried, NFS';
const _roastPotato = 'Potato, roasted, NFS';
const _gravy = 'Gravy, beef, canned, ready-to-serve';
const _vinaigrette = 'Salad dressing, home recipe, vinegar and oil';
const _bechamel = 'Bechamel sauce';
const _cookedLentils = 'Lentils, mature seeds, cooked, boiled, with salt';
const _cookedNoodles = 'Noodles, cooked';
const _mint = 'Spearmint, fresh';
const _friedChicken =
    'Chicken, broilers or fryers, meat and skin, cooked, fried, batter';
const _steamedDumpling = 'Wonton, dumpling or pot sticker, steamed';
const _friedDumpling = 'Wonton, dumpling or pot sticker, fried';
const _tzatziki = 'Tzatziki dip';
const _meatballs = 'Meatballs, frozen, Italian style';
const _cookedEggplant = 'Eggplant, cooked, fat added';
const _greekYogurt = 'Yogurt, Greek, NS as to type of milk, plain';
