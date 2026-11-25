import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/dev/fake_health.dart';

void main() {
  test('the fake scale has a weigh-in today before 7:00', () async {
    final now = DateTime(2026, 11, 26, 0, 34);
    final weights = await FakeWeights().read(DateTime(2026, 11, 25), now);
    expect(weights.map((w) => w.measuredAt), [DateTime(2026, 11, 25, 7), now]);
  });

  test('after 7:00 today\'s weigh-in is at 7:00', () async {
    final now = DateTime(2026, 11, 26, 9);
    final weights = await FakeWeights().read(DateTime(2026, 11, 26), now);
    expect(weights.map((w) => w.measuredAt), [DateTime(2026, 11, 26, 7)]);
  });
}
