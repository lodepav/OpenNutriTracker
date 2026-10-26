import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';

void main() {
  test('a little under the lowest to a little over the highest', () {
    final r = fittedRange([2100, 2400, 2250]);
    expect(r.min, closeTo(2055, 1e-9));
    expect(r.max, closeTo(2445, 1e-9));
  });

  test('positive values never go under zero; crossing it keeps it', () {
    expect(fittedRange([1, 50]).min, 0);
    final r = fittedRange([-300, 200]);
    expect(r.min, closeTo(-375, 1e-9));
    expect(r.max, closeTo(275, 1e-9));
  });

  test('a flat period pads by its minimum span; none is a unit span', () {
    final r = fittedRange([80, 80], minSpan: 2);
    expect(r.min, closeTo(79.7, 1e-9));
    expect(r.max, closeTo(80.3, 1e-9));
    expect(fittedRange(const [], minSpan: 5), (min: 0, max: 5));
  });
}
