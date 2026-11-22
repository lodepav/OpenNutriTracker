import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/water_intake_entity.dart';
import 'package:opennutritracker/fork/water/last_logged_water.dart';

// Undo last takes back the drink logged last, not the one timed latest.

WaterIntakeEntity _drink(String id, int hour) => WaterIntakeEntity(
  id: id,
  dateTime: DateTime(2026, 11, 22, hour),
  amountMl: 250,
);

void main() {
  test('the drink logged last, over a seeded drink timed later', () {
    final logged = _drink('water-1795000000000000', 10);
    final earlier = _drink('water-1794990000000000', 9);
    final seeded = _drink('4f9a-uuid', 21);
    expect(lastLoggedWater([seeded, logged, earlier]), logged);
  });

  test('with no stamped drink, the latest by time', () {
    expect(
      lastLoggedWater([_drink('a', 15), _drink('b', 9), _drink('c', 12)])?.id,
      'a',
    );
  });

  test('nothing today', () => expect(lastLoggedWater(const []), isNull));
}
