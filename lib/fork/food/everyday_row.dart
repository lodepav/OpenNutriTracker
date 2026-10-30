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
  // a salad's or a soup's, not the light one the shortest name found
  'sour cream': 'Cream, sour, cultured',
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
const _greekYogurt ='Yogurt, Greek, NS as to type of milk, plain';
