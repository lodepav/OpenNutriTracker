import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/screens/home/dashboard_widget.dart';

void main() {
  double left(double left) =>
      homeRingFill(goal: 3000, left: left, showsEaten: false);
  double eaten(double left) =>
      homeRingFill(goal: 3000, left: left, showsEaten: true);

  test('Left mode shows what is left: 200 of 3000 left is 7% full', () {
    expect(left(200), closeTo(0.0667, 1e-3));
    expect(left(3000), 1);
  });

  test('Left mode is empty at and past the goal', () {
    expect(left(0), 0);
    expect(left(-300), 0);
  });

  test('Left mode is full while activity has lifted left past the goal', () {
    expect(left(3400), 1);
  });

  test('Eaten mode fills with what was eaten, full past the goal', () {
    expect(eaten(200), closeTo(0.9333, 1e-3));
    expect(eaten(3000), 0);
    expect(eaten(3400), 0);
    expect(eaten(-300), 1);
  });

  test('no goal: empty, but full in Eaten mode once over', () {
    expect(homeRingFill(goal: 0, left: 0, showsEaten: false), 0);
    expect(homeRingFill(goal: 0, left: 0, showsEaten: true), 0);
    expect(homeRingFill(goal: 0, left: -10, showsEaten: true), 1);
  });
}
