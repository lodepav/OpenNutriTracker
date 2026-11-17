// lib/fork/food/everyday_row.dart: the row a bare name means.
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/food/everyday_row.dart';

void main() {
  test('a key stands for its boiled and state-first spellings', () {
    // "spaghetti, boiled" found spaghetti squash, which holds both words.
    for (final query in [
      'spaghetti',
      'Spaghetti, cooked',
      'spaghetti, boiled',
      'boiled spaghetti',
      'cooked spaghetti',
      'macaroni, boiled',
    ]) {
      expect(everydayRowName(query), 'Pasta, cooked', reason: query);
    }
    expect(everydayRowName('boiled potatoes'), isNotNull);
    expect(everydayRowName('spaghetti squash, boiled'), isNull);
    expect(everydayRowName('boiled egg whites'), isNull);
  });

  // "beef, cooked" logged beef bacon at 449 kcal per 100 g in a stuffed
  // pepper and a solyanka; "pork chop" a stuffed chop.
  test('a meat named only by how it was cooked is the generic row', () {
    for (final (query, row) in [
      ('beef, cooked', 'Beef, NFS'),
      ('cooked sliced beef', 'Beef, NFS'),
      ('beef, cooked, sliced', 'Beef, NFS'),
      ('pork, cooked, roasted', 'Pork, NFS'),
      ('pork meat', 'Pork, NFS'),
      ('turkey, roasted', 'Turkey, NFS'),
      ('pork chops', 'Pork, chop, NS as to fat eaten'),
      (
        'beef, ground, cooked, pan-browned',
        'Beef, ground, unspecified fat content, cooked',
      ),
    ]) {
      expect(everydayRowName(query), row, reason: query);
    }
    // a key of its own still wins, and a cut or a fried coat is its row
    expect(everydayRowName('beef, stewed'), isNot('Beef, NFS'));
    expect(everydayRowName('pork belly'), isNull);
    expect(everydayRowName('pork chop, breaded, fried'), isNull);
    expect(everydayRowName('beef broth'), isNot('Beef, NFS'));
  });

  // A karbonāde's "pork cutlet, breaded, fried" missed the schnitzel mapped
  // to "pork, cutlet, breaded, fried" and found minced pork patties.
  test('a key matches by its words, whatever the commas', () {
    expect(
      everydayRowName('pork cutlet, breaded, fried'),
      everydayRowName('pork, cutlet, breaded, fried'),
    );
    expect(everydayRowName('pork cutlet breaded fried'), isNotNull);
  });

  // "boiled broccoli" went boiled → cooked → state first and found the
  // "broccoli, cooked" row, which has fat added.
  test('boiled broccoli is the boiled row in either order', () {
    for (final query in ['boiled broccoli', 'broccoli, boiled']) {
      expect(
        everydayRowName(query),
        'Broccoli, cooked, boiled, drained, without salt',
        reason: query,
      );
    }
    expect(everydayRowName('broccoli, cooked'), isNot(contains('boiled')));
  });

  // Battered vegetables the table has no row of are the tempura row; the
  // ones it has (broccoli, carrots) and a plain fried vegetable keep theirs.
  test('a battered vegetable without its own row is tempura', () {
    for (final query in [
      'zucchini, battered and fried',
      'bell peppers, fried in batter',
      'battered fried vegetables',
      'vegetables, mixed, battered, fried',
    ]) {
      expect(everydayRowName(query), 'Vegetable tempura', reason: query);
    }
    for (final query in [
      'broccoli, battered and fried',
      'carrots, battered, fried',
      'zucchini, fried',
      'bell pepper, battered',
      'chicken, fried, battered',
    ]) {
      expect(everydayRowName(query), isNull, reason: query);
    }
  });
}
