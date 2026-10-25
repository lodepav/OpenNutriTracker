import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/custom_text_input_formatter.dart';

/// S141: a number field takes digits and one separator, nothing else.
void main() {
  String type(String old, String typed) {
    var value = TextEditingValue(text: typed);
    for (final f in CustomTextInputFormatter.doubleOnly()) {
      value = f.formatEditUpdate(TextEditingValue(text: old), value);
    }
    return value.text;
  }

  test('a minus, a letter or a second separator is dropped', () {
    expect(type('120', '120-'), '120');
    expect(type('120', '-120'), '120');
    expect(type('12', '12a'), '12');
    expect(type('1.5', '1.5.'), '1.5');
    expect(type('1.5', '1.5,'), '1.5');
  });

  test('digits, a comma or a period still go in', () {
    expect(type('12', '120'), '120');
    expect(type('1', '1,'), '1.');
    expect(type('', '.5'), '.5');
    expect(type('1.25', ''), '');
  });
}
