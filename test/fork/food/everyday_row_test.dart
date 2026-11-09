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
}
