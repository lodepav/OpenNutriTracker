// lib/fork/food/portion_words.dart: the shape a food was served in.
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/food/portion_words.dart';

void main() {
  test('a shape word comes off, and the food stays', () {
    expect(withoutShapeWords('lemon slice'), 'lemon');
    expect(withoutShapeWords('slices of bread'), 'bread');
    expect(withoutShapeWords('apple wedges'), 'apple');
    expect(withoutShapeWords('orange segments'), 'orange');
  });

  test('a name in brackets comes off too', () {
    expect(withoutShapeWords('fresh coriander (cilantro)'), 'fresh coriander');
    expect(withoutShapeWords('lemon slices (thin)'), 'lemon');
    expect(withoutShapeWords('(cilantro)'), isNull);
  });

  test('a name with no shape word, or only one, is left alone', () {
    expect(withoutShapeWords('lemon'), isNull);
    expect(withoutShapeWords('slices'), isNull);
    expect(withoutShapeWords('sliced cheese'), isNull);
  });
}
