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
}
