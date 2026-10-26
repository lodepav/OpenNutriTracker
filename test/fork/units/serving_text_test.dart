import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/units/amount_text.dart';

/// S142: a serving's text is shown only when it names the weight added.
void main() {
  test('a text naming the weight added agrees', () {
    expect(servingTextAgrees('1 serving (80 g)', 80), isTrue);
    expect(servingTextAgrees('1 cup (240 ml)', 240), isTrue);
    expect(servingTextAgrees('2 slices (56g)', 56.2), isTrue);
  });

  test('a text naming another weight does not', () {
    expect(servingTextAgrees('1 serving (10 g)', 80), isFalse);
    expect(servingTextAgrees('1,5 g', 80), isFalse);
  });

  test('a text naming no weight, or no quantity, agrees', () {
    expect(servingTextAgrees('1 medium', 118), isTrue);
    expect(servingTextAgrees('1 serving (10 g)', null), isTrue);
  });
}
