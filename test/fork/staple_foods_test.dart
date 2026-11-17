// Phase 1b.4: the foods the user eats most resolve from the bundled table
// alone, without D9's estimate. Runs upstream's resolver and repository,
// with the fork's seams, over the table; Open Food Facts is left out, so a
// pass here does not lean on a branded product.
//
// Upstream's tie-break picks the shorter sibling, the same on its backend
// (resolver_relevance.dart, upstream #1231): `egg` landed on "Egg,
// creamed", `eggs` on a Foundation yolk row and `pizza` on "Pizza, no
// cheese, thin crust". The fork's tie-breaks (S73, S74), its list of the
// row a name means (S75) and variant rule (S70) fixed those, `pepperoni
// pizza` and the bare names below.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/meal_detail/util/meal_quantity_converter.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/off_data_source.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/search_products_usecase.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';

class _TableOnlySearch implements SearchProductsUseCase {
  final ProductsRepository repository;

  _TableOnlySearch(this.repository);

  @override
  Future<SearchProductsResult> searchOFFProductsByString(
    String searchString, {
    bool skipRemote = false,
  }) async => SearchProductsResult(meals: const [], remoteSourceEmpty: true);

  @override
  Future<SearchProductsResult> searchFDCFoodByString(
    String searchString, {
    bool skipRemote = false,
    bool forResolution = false,
  }) async => SearchProductsResult(
    meals: await repository.getSupabaseFoodsByString(
      searchString,
      forResolution: forResolution,
    ),
    remoteSourceEmpty: false,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late ResolveParsedMealsUseCase resolver;

  setUpAll(() async {
    final table = LocalFoodTable.fromGzip(
      await File(LocalFoodDataSource.assetPath).readAsBytes(),
    );
    final foods = LocalFoodDataSource(
      loadTable: () async => table,
      readToggles: () async => null,
    );
    resolver = ResolveParsedMealsUseCase(
      _TableOnlySearch(ProductsRepository(OFFDataSource(), foods)),
    );
  });

  Future<ResolvedMealItem> resolve(String query) async =>
      (await resolver.resolve([ParsedMealItem(query: query)])).single;

  for (final (query, expected) in [
    ('rye bread', 'Bread, rye'),
    ('kefir', 'Kefir'),
    ('buckwheat', 'Buckwheat, boiled'),
    // biezpiens: the model's usual English for it.
    ('quark', 'Quark, < 10 % fat in dry matter'),
    ('cottage cheese', 'Cheese, cottage, NFS'),
  ]) {
    test('$query resolves to "$expected"', () async {
      final item = await resolve(query);
      expect(item.candidates[item.selectedIndex].name, expected);
      expect(item.confidence, greaterThanOrEqualTo(kResolutionConfidenceFloor));
    });
  }

  // No open table has them; the fork's own dish row does (S72), beside
  // phase 1c's starter recipe "grey peas with bacon" (D12).
  test('grey peas resolve to the fork\'s dish', () async {
    final item = await resolve('grey peas');
    expect(item.candidates.map((c) => c.backendSource).toSet(), {
      'fork_dishes',
    });
  });

  // A fork dish's bracketed names count whole, or beside a word of its
  // name: a single Latvian word found the dish it is one word of, "lasis"
  // a salmon soup made "ar lasi", "pankūkas" liver patties ("aknu
  // pankūkas"), "speķis" grey peas with bacon.
  for (final query in ['lasis', 'pankūkas', 'speķis', 'biezpiens']) {
    test('"$query" is not a dish it is one word of', () async {
      final item = await resolve(query);
      expect(
        item.candidates.map((c) => c.backendSource),
        isNot(contains('fork_dishes')),
        reason: item.candidates.map((c) => c.name).join('; '),
      );
    });
  }

  for (final (query, dish) in [
    ('pelēkie zirņi', 'Grey peas with bacon'),
    ('laša zupa', 'Salmon soup'),
    ('aknu pankūkas', 'Liver patties'),
    ('fried pork patties', 'Pork cutlets'),
  ]) {
    test('"$query" is still the fork\'s "$dish"', () async {
      final item = await resolve(query);
      expect(item.candidates[item.selectedIndex].name, startsWith(dish));
    });
  }

  // A photo's chłodnik came back under these names, found no row and was
  // broken down by a second call at 263-345 kcal, a bowl being about 110.
  for (final query in [
    'cold beetroot soup (chlodnik)',
    'cold beetroot soup (chilled borscht)',
    'cold beetroot soup (chilled borscht with kefir)',
    'cold beet soup with kefir',
    'cold beet soup (chilled borscht with kefir or yogurt)',
    'chłodnik',
    'cold borscht',
    'chilled borscht',
    'cold beet soup',
    'cold beet borscht',
    'chilled beet borscht',
  ]) {
    test('$query resolves to the fork\'s chłodnik', () async {
      final item = await resolve(query);
      expect(item.candidates[item.selectedIndex].name, startsWith('Chłodnik'));
    });
  }

  // FNDDS's crème brûlée, at 113 kcal per 100 g, is left out of the table
  // (WRONG_ROWS, build_food_db.py): it shared BLS's name.
  test('creme brulee resolves to a custard of cream and yolks', () async {
    final item = await resolve('creme brulee');
    final row = item.candidates[item.selectedIndex];
    expect(row.name, 'Creme brulee');
    expect(row.nutriments.energyKcal100, greaterThan(300));
  });

  // A bare family name lands on the everyday row, not the shortest sibling:
  // the user's log typed these, and "chicken" logged "Chicken, back",
  // "tomato" "Tomato, green, pickled", "salad" "Salmon salad". A fork dish
  // wins a tie with the table's odd forms (S74): "lasagna" logged "Lasagna,
  // Vegetable, frozen, baked"; a form the query names keeps its row.
  for (final (query, expected) in [
    ('chicken', 'Chicken, NS as to part'),
    ('bacon', 'Bacon, NS as to type of meat, cooked'),
    ('tomato', 'Tomatoes, '),
    ('salad', 'Salad, green, without dressing'),
    ('pepperoni pizza', 'Pizza, with pepperoni'),
    ('coffee', 'Coffee, NS as to type'),
    ('kvass, bread-based', 'Kvass, bread drink'),
    ('lasagna', 'Lasagna, beef, homemade'),
    ('egg', 'Egg, whole, raw, fresh'),
    ('eggs', 'Eggs, Grade A, Large, egg whole'),
    ('pizza', 'Pizza, cheese, from restaurant or fast food, NS as to'),
    ('cheese pizza', 'Pizza, cheese, from restaurant or fast food, NS as to'),
    ('fries', 'Potato, french fries, NFS'),
    ('tomato sauce', 'Tomato products, canned, sauce'),
    ('tomato paste', 'Tomato products, canned, paste'),
    ('potato', 'Potatoes, boiled, cooked without skin'),
    ('potatoes', 'Potatoes, boiled, cooked without skin'),
    ('porridge', 'Oatmeal, regular or quick, made with water'),
    ('bread soup', 'Bread soup (brown bread), with raisins'),
    ('butter, unsalted', 'Butter, without salt'),
    ('unsalted butter', 'Butter, without salt'),
    ('cola', 'Soft drink, cola'),
    ('coke', 'Soft drink, cola'),
    ('diet coke', 'Soft drink, cola, diet'),
    ('greek yogurt', 'Yogurt, Greek, NS as to type of milk, plain'),
    ('granola', 'Cereal, granola'),
    ('basmati rice', 'Rice, white, long-grain, regular, enriched, cooked'),
    ('jasmine rice', 'Rice, white, long-grain, regular, enriched, cooked'),
    ('cooked basmati rice', 'Rice, white, long-grain'),
    ('chicken broth', 'Soup, chicken broth, ready-to-serve'),
    ('beef broth', 'Soup, beef broth or bouillon canned, ready-to-serve'),
    (
      'coconut milk',
      'Nuts, coconut milk, canned (liquid expressed from grated meat and water)',
    ),
    ('vegetable stock', 'Soup, vegetable broth, ready to serve'),
    ('sour cream', 'Cream, sour, cultured'),
    ('vegetable lasagna', 'Lasagna, Vegetable'),
    ('hamburger bun, plain', 'Roll, white, hamburger bun'),
    ('salad dressing, caesar', 'Salad dressing, caesar dressing, regular'),
    ('beef patty, cooked, pan-broiled', 'Beef, ground, 70%'),
    ('bacon, cooked, pan-fried', 'Pork, cured, bacon'),
    ('tortilla, wheat flour', 'Wheat flour tortilla'),
    ('potatoes, boiled, cooked without skin', 'Potatoes, boiled, cooked'),
    ('mayonnaise', 'Mayonnaise, regular'),
    ('bread, hamburger bun', 'Roll, white, hamburger bun'),
    ('spaghetti, cooked', 'Pasta, cooked'),
    ('rice, white, cooked, fried', 'Rice, fried, NFS'),
    ('potatoes, roasted', 'Potato, roasted, NFS'),
    ('gravy, onion', 'Gravy, NFS'),
    ('gravy, brown', 'Gravy, NFS'),
    ('salad dressing, vinaigrette', 'Salad dressing, home recipe, vinegar'),
    ('carrots, cooked', 'Carrots, NS as to form, cooked'),
    ('salmon, baked', 'Fish, salmon, baked or broiled'),
    ('rice, white, cooked', 'Rice, white, cooked, NS as to fat'),
    ('rice', 'Rice, white, long-grain, regular, enriched, cooked'),
    ('lentils, red, cooked', 'Lentils, mature seeds, cooked'),
    ('noodles, chinese, cooked', 'Noodles, cooked'),
    ('tomato sauce, cooked', 'Tomato products, canned, sauce'),
    ('white sauce, prepared with milk', 'Bechamel sauce'),
    ('mint, fresh', 'Spearmint, fresh'),
    ('chicken, fried', 'Chicken, broilers or fryers, meat and skin'),
    ('dumplings, vegetable, cooked', 'Wonton, dumpling or pot sticker'),
    ('gyoza', 'Wonton, dumpling or pot sticker, fried'),
    ('tzatziki sauce', 'Tzatziki dip'),
    ('flan', 'Flan'),
    ('spaghetti, cooked, enriched', 'Pasta, cooked'),
    ('beef, stewed', 'Beef, stew meat'),
    ('bread, flatbread', 'Wheat flatbread'),
    ('bread, italian or french', 'Bread, Italian'),
    ('cabbage, cooked', 'Cabbage, green, cooked'),
    ('fish, battered, fried', 'Restaurant, family style, fish fillet'),
    ('ice cream, vanilla, regular', 'Ice cream, vanilla'),
    ('onions, cooked, fried', 'Onions, yellow, sauteed'),
    ('pastry, phyllo, baked', 'Phyllo dough'),
    ('pork, cured, prosciutto', 'Ham, prosciutto'),
    ('pork, cutlet, breaded, fried', 'Pork schnitzel breaded, fried'),
    ('potatoes, french fried', 'Potato, french fries, NFS'),
    ('rice noodles, stir-fried', 'Rice noodles, cooked'),
    ('snow peas, cooked', 'Snowpeas, fresh, cooked'),
    ('wontons, pork, cooked', 'Wonton, dumpling or pot sticker, steamed'),
    ('dill', 'Dill weed, fresh'),
    ('parsley', 'Parsley, raw'),
    ('cilantro', 'Coriander (cilantro) leaves, raw'),
    ('green onion', 'Onions, green, raw'),
    ('grated parmesan cheese', 'Cheese, parmesan, grated'),
    ('stuffed bell pepper', 'Stuffed pepper, with rice and meat'),
    ('mashed potatoes with butter', 'Potatoes, mashed, home-prepared'),
    ('toasted baguette', 'Bread, French or Vienna, toasted'),
    ('borsch, beet soup', 'Borscht, with beef'),
    ('borscht, beet soup', 'Borscht, with beef'),
    ('beet soup', 'Borscht, with beef'),
    ('beet borscht', 'Borscht, with beef'),
    ('wheat flour noodles, dry, egg-free, cooked', 'Noodles, cooked'),
    ('broccoli sprouts, raw', 'Radish seeds, sprouted, raw'),
    ('elk, steak, cooked, grilled', _elkSteak),
    ('elk, cooked, steak', _elkSteak),
    ('elk, cooked', _elkSteak),
    ('elk steak', _elkSteak),
    ('elk steak, grilled', _elkSteak),
    ('elk, raw', 'Game meat, elk, raw'),
    ('elk, steak, raw', 'Game meat, elk, raw'),
    ('elk, cooked, roasted', 'Game meat, elk, cooked, roasted'),
    ('burger', 'Hamburger, NFS'),
    ('beef burger', 'Hamburger, NFS'),
    ('veggie burger', 'Veggie burger'),
    ('hamburger bun, white', 'Roll, white, hamburger bun'),
    ('breaded chicken', 'Chicken fillet, breaded'),
    ('breaded chicken pieces', 'Chicken fillet, breaded'),
    ('cod, battered or breaded, fried', 'Cod fillet, in frying batter'),
    ('seaweed salad', 'Seaweed salad, wakame'),
    ('wakame salad', 'Seaweed salad, wakame'),
    ('seaweed salad, wakame', 'Seaweed salad, wakame'),
    // the row audit of photo reads (2026-11-17)
    ('farro, cooked', 'Spelt, cooked'),
    ('potatoes, hash browns, frozen, cooked', 'Potatoes, hash brown, frozen'),
    ('shredded potato, fried', 'Potato, hash brown, from fresh'),
    ('gravy, brown, prepared from mix', 'Gravy, NFS'),
    ('broccoli, cooked', 'Broccoli, NS as to form, cooked'),
    ('broccoli, steamed', 'Broccoli, cooked, boiled'),
    ('broccoli, boiled', 'Broccoli, cooked, boiled'),
    ('vinaigrette dressing', 'Salad dressing, home recipe, vinegar'),
    ('creamy herb dressing', 'Ranch dressing'),
    ('butter, for cooking', 'Butter, NFS'),
    ('fat, olive oil', 'Olive oil'),
    ('oil, vegetable, salad or cooking', 'Vegetable oil, NFS'),
    ('bread, white, roll', 'Roll, white, soft'),
    ('bread, ciabatta roll', 'Roll, white, hard'),
    ('bread, multigrain with seeds, roll', 'Roll, multigrain'),
    ('bread, flatbread, pizza crust', 'Wheat flatbread'),
    ('fish, white, breaded, cooked', 'Restaurant, family style, fish fillet'),
    ('fish, white, battered, fried', 'Restaurant, family style, fish fillet'),
    ('fish, cod, battered and fried', 'Cod fillet, in frying batter'),
    ('squid, battered, fried', 'Mollusks, squid, mixed species, cooked, fried'),
    ('chicken, cooked', 'Chicken, NS as to part and cooking method'),
    ('chicken, shredded, cooked', 'Chicken, NS as to part and cooking method'),
    ('chicken, roasted, meat only', 'Chicken, broilers or fryers, meat only'),
    ('chicken pieces, stir-fried', 'Chicken, NS as to part, sauteed'),
    ('chicken breast, cooked', 'Chicken breast, baked, broiled, or roasted'),
    ('chicken breast, stir-fried', 'Chicken breast, sauteed, skin not eaten'),
    ('chicken cutlet, breaded, fried', 'Chicken schnitzel, breaded, fried'),
    ('lamb kebab, grilled', 'Lamb, cubed for stew or kabob'),
    ('lamb kofta, grilled', 'Lamb, ground, cooked, broiled'),
    ('lamb, cooked, meat only', 'Lamb, NS as to cut'),
    ('bacon, grilled', 'Bacon, NS as to type of meat, cooked'),
    ('frankfurter, pork and beef', 'Frankfurter, meat'),
    ('falafel', 'Falafel, home-prepared'),
    ('meatballs, grilled', 'Meatballs, fried'),
    ('corn on the cob, boiled', 'Corn, sweet, yellow, cooked, boiled'),
    ('corn on the cob', 'Corn, sweet, yellow, cooked, boiled'),
    ('cherry tomatoes, raw', 'Tomatoes, raw'),
    ('baked beans in tomato sauce', 'Beans, baked, canned, plain'),
    ('orzo, cooked', 'Pasta, cooked'),
    ('celery root, cooked', 'Celeriac, cooked'),
    ('beef, steak, sliced, grilled', 'Steak, NS as to type of meat'),
    ('beef, roasted, sirloin steak', 'Beef, loin, top sirloin cap steak'),
    ('breakfast sausage, link, cooked', 'Pork sausage, link/patty, cooked'),
    ('eggs, scrambled, with milk', 'Egg, whole, cooked, scrambled'),
    ('herbs, mixed, fresh', 'Parsley, raw'),
    ('bread, cornbread', 'Cornbread, made from home recipe'),
    ('tomato sauce, spicy', 'Tomato products, canned, sauce'),
    ('rice vermicelli', 'Rice noodles, cooked'),
    ('lasagna, meat-free, baked', 'Lasagna, Vegetable'),
    ('bologna sausage', 'Bologna'),
    ('breadcrumbs', 'Bread, crumbs, dry, grated, plain'),
    ('granola with nuts', 'Cereal, granola'),
    ('fruit jam', 'Jam'),
    ('potatoes, fried, home fries', 'Potato, home fries, from fresh'),
    ('baby greens, raw', 'Mixed salad greens, raw'),
    ('salmon, cooked', 'Fish, salmon, Atlantic, wild, cooked'),
    ('walnuts', 'Nuts, walnuts, english'),
    ('zucchini, battered and fried', 'Vegetable tempura'),
    ('bell pepper, fried in batter', 'Vegetable tempura'),
    ('vegetables, mixed, battered, fried', 'Vegetable tempura'),
  ]) {
    test('bare "$query" resolves to "$expected..."', () async {
      final item = await resolve(query);
      expect(item.candidates[item.selectedIndex].name, startsWith(expected));
      expect(item.confidence, greaterThanOrEqualTo(kResolutionConfidenceFloor));
    });
  }

  // Names beside the audit's fixes keep their own rows: a battered
  // vegetable the table has, a raw or bought food, a dish's other parts.
  for (final (query, expected) in [
    ('broccoli, battered and fried', 'Broccoli, in frying batter'),
    ('carrots, battered, fried', 'Carrots, in frying batter'),
    ('broccoli, raw', 'Broccoli, raw'),
    ('bell pepper, red, raw', 'Peppers, bell, red, raw'),
    ('farro', 'Farro, pearled, dry, raw'),
    ('walnuts, raw', 'Nuts, walnuts, English, halves, raw'),
    ('hash brown, fried', 'Potatoes, hash brown, refrigerated, prepared'),
    ('chicken breast, grilled', 'Chicken breast, grilled without sauce'),
    ('chicken breast, breaded, fried', 'Chicken schnitzel, breaded, fried'),
    ('salmon, grilled', 'Salmon, grilled'),
    ('beef kofta, grilled', 'Kofta, beef, grilled'),
  ]) {
    test('"$query" keeps "$expected..."', () async {
      final item = await resolve(query);
      expect(item.candidates[item.selectedIndex].name, startsWith(expected));
    });
  }

  // A dressed carrot salad, not the one with apples, which holds the words.
  for (final query in [
    'carrot salad with mayonnaise',
    'carrot salad with mayo',
    'carrot salad, with mayonnaise',
  ]) {
    test('$query resolves to "Carrots, raw, salad"', () async {
      final item = await resolve(query);
      expect(item.candidates[item.selectedIndex].name, 'Carrots, raw, salad');
    });
  }

  // Elk named as ground keeps the ground rows; a steak or a plain cooked
  // elk is the lean loin.
  for (final query in [
    'elk, ground, cooked',
    'ground elk',
    'elk, ground, raw',
  ]) {
    test('$query stays a ground elk row', () async {
      final item = await resolve(query);
      final name = item.candidates[item.selectedIndex].name;
      expect(name, contains('lk'));
      expect(name, contains('ground'));
    });
  }

  // A photo's 8 meatballs: an Open Food Facts "meatball and sausage
  // marinara" won over a row with no piece, or a 3 oz serving made 680 g.
  for (final query in ['meatballs', 'meatball', 'fried meatballs']) {
    test('$query, counted, are that many 30 g meatballs', () async {
      final item = (await resolver.resolve([
        ParsedMealItem(query: query, quantity: 8),
      ])).single;
      final meal = item.candidates[item.selectedIndex];
      expect(meal.name, 'Meatballs, fried');
      expect(meal.servingQuantity, 30);
      expect(convertQuantityToBaseUnit(8, 'serving', meal), 240);
    });
  }
  test(
    'a kind of meatball takes a piece too; a small one is smaller',
    () async {
      for (final (query, name, grams) in [
        ('pork meatballs', 'Pork meatballs, fried', 30.0),
        ('small meatballs', 'Small meatballs', 12.0),
      ]) {
        final item = await resolve(query);
        final meal = item.candidates[item.selectedIndex];
        expect(meal.name, name);
        expect(meal.servingQuantity, grams);
      }
    },
  );

  test(
    "a photo's fried bacon counts in 8 g slices, not a 3 oz serving",
    () async {
      for (final query in ['fried bacon', 'bacon', 'crispy bacon']) {
        final item = (await resolver.resolve([
          ParsedMealItem(query: query, quantity: 4),
        ])).single;
        final meal = item.candidates[item.selectedIndex];
        expect(
          meal.name,
          'Bacon, NS as to type of meat, cooked',
          reason: query,
        );
        expect(convertQuantityToBaseUnit(4, 'serving', meal), 32);
      }
    },
  );

  test("a photo's fried potatoes are home fries; the table's name stays "
      'fries', () async {
    for (final query in [
      'fried potato',
      'fried potatoes',
      'sauteed potatoes',
    ]) {
      final item = await resolve(query);
      expect(
        item.candidates[item.selectedIndex].name,
        'Potato, home fries, from fresh',
        reason: query,
      );
    }
    final fries = await resolve('potatoes, fried');
    expect(
      fries.candidates[fries.selectedIndex].name,
      startsWith('Potato, french fries'),
    );
  });

  // Phase 1c: the ingredient names the breakdown prompt asks for
  // (BreakDownDishUseCase.systemPrompt) land on the plain raw row.
  for (final (query, expected) in [
    ('egg, whole, raw', 'Egg, whole, raw'),
    ('carrot, raw', 'Carrots, raw'),
    (
      'wheat flour, white, all-purpose',
      'Wheat flour, white, all-purpose, unenriched',
    ),
    ('sour cream, regular', 'Sour cream, regular'),
    ('beef, ground, raw', 'Beef, ground, raw'),
    ('split peas, raw', 'Peas, green, split, mature seeds, raw'),
    ('cheese, mozzarella, whole milk', 'Cheese, mozzarella, whole milk'),
    ('pork bacon', 'Pork, cured, bacon, unprepared'),
  ]) {
    test('ingredient "$query" resolves to "$expected"', () async {
      final item = await resolve(query);
      expect(item.candidates[item.selectedIndex].name, expected);
      expect(item.confidence, greaterThanOrEqualTo(kResolutionConfidenceFloor));
    });
  }
}

const _elkSteak = 'Game meat, elk, loin, separable lean only, cooked, broiled';
