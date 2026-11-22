import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/body/body_card.dart';

void main() {
  test('older entries with fewer than two in range say why', () {
    expect(
      measurementRangeHint(series: 2, inRange: 1, rangeDays: 7),
      '1 measurement in the last 7 days. '
      'Pick a longer range above to see the change.',
    );
    expect(
      measurementRangeHint(series: 3, inRange: 0, rangeDays: 30),
      'No measurements in the last 30 days. '
      'Pick a longer range above to see the change.',
    );
  });

  test('nothing to say with one entry or two in range', () {
    expect(measurementRangeHint(series: 1, inRange: 1, rangeDays: 7), isNull);
    expect(measurementRangeHint(series: 0, inRange: 0, rangeDays: 7), isNull);
    expect(measurementRangeHint(series: 5, inRange: 2, rangeDays: 7), isNull);
  });
}
