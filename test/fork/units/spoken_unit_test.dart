import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/units/amount_text.dart';

void main() {
  test('a unit is spoken in words, an unknown one as written', () {
    expect(spokenUnit('g'), 'grams');
    expect(spokenUnit('mg'), 'milligrams');
    expect(spokenUnit('µg'), 'micrograms');
    expect(spokenUnit('kJ'), 'kilojoules');
    expect(spokenUnit('cup'), 'cup');
  });
}
