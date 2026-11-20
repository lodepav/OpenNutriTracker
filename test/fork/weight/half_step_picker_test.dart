import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/weight/half_step_picker.dart';

void main() {
  List<double> items(({double min, double max, int divisions}) b) => [
    for (var i = 0; i <= b.divisions; i++)
      b.min + (b.max - b.min) / b.divisions * i,
  ];

  double centreItem(({double min, double max, int divisions}) b) =>
      items(b)[(b.divisions + 1) ~/ 2];

  void expectHalfSteps(({double min, double max, int divisions}) b) {
    final values = items(b);
    for (var i = 0; i < values.length; i++) {
      expect(values[i] * 2, closeTo((values[i] * 2).round(), 1e-9));
      if (i > 0) expect(values[i] - values[i - 1], closeTo(0.5, 1e-9));
    }
  }

  test('kg: 87.3 centres on 87.5 with upstream span of 50 each side', () {
    final b = halfStepPickerBounds(87.3, false);
    expect(b, (min: 37.5, max: 137.5, divisions: 200));
    expect(centreItem(b), 87.5);
    expectHalfSteps(b);
  });

  test('kg: 87.75 rounds to 88.0', () {
    final b = halfStepPickerBounds(87.75, false);
    expect(centreItem(b), 88.0);
    expectHalfSteps(b);
  });

  test('lb: 200.2 centres on 200.0 with 100 each side', () {
    final b = halfStepPickerBounds(200.2, true);
    expect(b, (min: 100.0, max: 300.0, divisions: 400));
    expect(centreItem(b), 200.0);
    expectHalfSteps(b);
  });

  test('kg near the floor: the span shrinks to stay centred above 1', () {
    final b = halfStepPickerBounds(48, false);
    expect(b, (min: 1.0, max: 95.0, divisions: 188));
    expect(centreItem(b), 48.0);
    expectHalfSteps(b);
  });

  test('lb near the floor', () {
    final b = halfStepPickerBounds(80.4, true);
    expect(b, (min: 1.0, max: 160.0, divisions: 318));
    expect(centreItem(b), 80.5);
    expectHalfSteps(b);
  });

  test('at the floor the ruler keeps one step each side', () {
    final b = halfStepPickerBounds(1, false);
    expect(b, (min: 0.5, max: 1.5, divisions: 2));
    expect(centreItem(b), 1.0);
  });
}
