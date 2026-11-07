import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/food/unasked_variant.dart';

void main() {
  test('a variant the query did not name trails', () {
    expect(unaskedVariant('Bacon, meatless', 'bacon'), unaskedVariantPenalty);
    expect(
      unaskedVariant('Vegan schnitzel', 'schnitzel'),
      unaskedVariantPenalty,
    );
    expect(
      unaskedVariant('Baby Toddler sweet potatoes', 'baby potatoes'),
      unaskedVariantPenalty,
    );
    for (final (name, query) in [
      ('Carrots, glazed, cooked', 'carrots, cooked'),
      ('Salmon, in puff pastry baked', 'salmon, baked'),
      ('Spaghetti, spinach, cooked', 'spaghetti, cooked'),
      ('Rice, white, cooked, glutinous', 'rice, white, cooked'),
      (
        'Babyfood, dinner, vegetables and dumplings and beef, junior',
        'dumplings, vegetable, cooked',
      ),
      (
        'Spaghetti, protein-fortified, cooked, enriched (n x 6.25)',
        'spaghetti, cooked',
      ),
    ]) {
      expect(unaskedVariant(name, query), unaskedVariantPenalty, reason: name);
    }
    expect(unaskedVariant('Spinach, raw', 'spinach'), 0);
    expect(
      unaskedVariant('Rice, white, cooked, glutinous', 'rice, glutinous'),
      0,
    );
  });

  test('the variant the query names, and plain rows, keep their score', () {
    expect(unaskedVariant('Vegan schnitzel', 'vegan schnitzel'), 0);
    expect(unaskedVariant('Pork schnitzel, fried', 'schnitzel'), 0);
    // USDA's "unprepared" is the raw row a recipe wants, not a variant.
    expect(unaskedVariant('Pork, cured, bacon, unprepared', 'pork bacon'), 0);
    expect(unaskedVariant(null, 'bacon'), 0);
  });

  test('a row that is only the skin trails, unless the query says skin', () {
    for (final name in [
      'Potatoes, raw, skin',
      'Potatoes, boiled, cooked in skin, skin, with salt',
      'Chicken, skin (drumsticks and thighs), raw',
    ]) {
      expect(unaskedVariant(name, 'potatoes'), unaskedVariantPenalty);
    }
    expect(unaskedVariant('Potatoes, raw, skin', 'potato skin'), 0);
    expect(
      unaskedVariant(
        'Potatoes, boiled, cooked in skin, skin, without salt',
        'potatoes, boiled, cooked without skin',
      ),
      unaskedVariantPenalty,
    );
    for (final name in [
      'Potatoes, boiled, cooked in skin, flesh, with salt',
      'Chicken thigh, grilled, skin eaten',
      'Chicken thigh, skin removed before cooking',
      'Potatoes, flesh and skin, raw',
    ]) {
      expect(unaskedVariant(name, 'potatoes'), 0, reason: name);
    }
  });

  test('a pickled or turkey row trails, unless the query says so', () {
    expect(
      unaskedVariant('Tomato, green, pickled', 'tomato'),
      unaskedVariantPenalty,
    );
    expect(
      unaskedVariant('Bacon, turkey, unprepared', 'bacon'),
      unaskedVariantPenalty,
    );
    expect(unaskedVariant('Tomato, green, pickled', 'pickled tomato'), 0);
    expect(unaskedVariant('Cucumber, pickled', 'pickles'), 0);
    expect(unaskedVariant('Bacon, turkey, unprepared', 'turkey bacon'), 0);
    // A row titled turkey is the food asked for.
    expect(unaskedVariant('Turkey, ground, cooked', 'turkey'), 0);
  });

  test('a row named for lacking what the query names trails', () {
    expect(
      unaskedVariant(
        'Pizza, with meat other than pepperoni, stuffed crust',
        'pepperoni pizza',
      ),
      unaskedVariantPenalty,
    );
    expect(
      unaskedVariant('Coffee, without milk', 'coffee with milk'),
      unaskedVariantPenalty,
    );
    expect(
      unaskedVariant('Pizza, no cheese, thin crust', 'cheese pizza'),
      unaskedVariantPenalty,
    );
    expect(
      unaskedVariant('Pizza, with pepperoni, thin crust', 'pepperoni pizza'),
      0,
    );
    expect(unaskedVariant('Pizza, no cheese, thin crust', 'pizza'), 0);
  });

  test('a lighter make trails, unless the query asks for lighter', () {
    for (final (name, query) in [
      ('Salad dressing, caesar, fat-free', 'salad dressing, caesar'),
      ('Salad dressing, caesar, low calorie', 'caesar dressing'),
      (
        'Salad dressing, thousand island dressing, reduced fat',
        'thousand island',
      ),
      (
        'Beef, ground, 97% lean meat /3% fat, patty, cooked, pan-broiled',
        'beef patty, cooked',
      ),
      ('Canadian bacon, cooked, pan-fried', 'bacon, cooked, pan-fried'),
      ('Wheat flour, white, tortilla mix, enriched', 'tortilla, wheat flour'),
      ('Mayonnaise, light', 'mayonnaise'),
      ('Ice creams, vanilla, light', 'ice cream, vanilla'),
    ]) {
      expect(unaskedVariant(name, query), unaskedVariantPenalty, reason: name);
    }
    for (final (name, query) in [
      ('Salad dressing, caesar, fat-free', 'fat free caesar dressing'),
      ('Salad dressing, caesar, low calorie', 'light caesar dressing'),
      ('Beef, ground, 95% lean meat / 5% fat, raw', 'lean ground beef'),
      ('Milk, nonfat, fluid', 'skim milk'),
      ('Salad dressing, caesar dressing, regular', 'caesar dressing'),
      ('Beef, ground, 80% lean meat / 20% fat, raw', 'ground beef'),
      ('Potato, scalloped, from dry mix', 'potato'),
      (
        'Puddings, chocolate, dry mix, instant, prepared with 2% milk',
        'chocolate pudding',
      ),
      ('Mayonnaise, light', 'light mayonnaise'),
      // light meat is a cut, not a make
      ('Turkey, whole, light meat, meat and skin, cooked, roasted', 'turkey'),
    ]) {
      expect(unaskedVariant(name, query), 0, reason: name);
    }
  });

  test('fries from the freezer are a variant unless asked for', () {
    const row = 'Potatoes, french fried, steak fries, frozen, oven-heated';
    expect(
      unaskedVariant(row, 'potatoes, french fried, fast food style'),
      unaskedVariantPenalty,
    );
    expect(unaskedVariant(row, 'french fries, oven baked'), 0);
    expect(unaskedVariant(row, 'french fries, frozen'), 0);
    expect(
      unaskedVariant(
        'Fast foods, potato, french fried in vegetable oil',
        'fries',
      ),
      0,
    );
  });

  test('a sauce named after the food trails the food: a canteen photo\'s '
      '"roast pork" logged "Roast pork gravy"', () {
    const p = unaskedVariantPenalty;
    expect(unaskedVariant('Roast pork gravy', 'roast pork'), p);
    expect(unaskedVariant('Chicken soup', 'chicken'), p);
    expect(unaskedVariant('Pork chop seasoning', 'pork chop'), p);
    expect(unaskedVariant('Salad dressing, ranch', 'salad'), p);
    expect(unaskedVariant('Meatball and sausage marinara', 'meatballs'), p);
    expect(unaskedVariant('Meatball and sausage marinara', 'marinara'), 0);
    // Asked for, or a food that comes with one.
    expect(unaskedVariant('Roast pork gravy', 'gravy'), 0);
    expect(unaskedVariant('Gravy, beef, canned', 'gravies'), 0);
    expect(unaskedVariant('Ham or pork with gravy', 'pork'), 0);
    expect(
      unaskedVariant('Chicken breast, grilled without sauce', 'chicken'),
      0,
    );
    expect(unaskedVariant('Tomato products, canned, sauce', 'tomato sauce'), 0);
  });

  test('a dry or powdered form trails the food as eaten: a photo\'s '
      '"gravy, brown" logged the granules', () {
    const p = unaskedVariantPenalty;
    expect(unaskedVariant('Gravy, brown, dry', 'gravy, brown'), p);
    expect(unaskedVariant('Milk, dry, whole', 'milk'), p);
    expect(unaskedVariant('Curry powder', 'curry'), p);
    expect(unaskedVariant('Gravy, brown, dry', 'gravy mix'), 0);
    expect(unaskedVariant('Pasta, dry, unenriched', 'dry pasta'), 0);
    expect(unaskedVariant('Milk, dry, whole', 'powdered milk'), 0);
    // Not a dish made from one, nor nuts roasted dry.
    expect(
      unaskedVariant('Nuts, almonds, dry roasted, with salt added', 'almonds'),
      0,
    );
    expect(
      unaskedVariant(
        'Potatoes, mashed, dehydrated, prepared from flakes without milk',
        'mashed potatoes',
      ),
      0,
    );
  });
}
