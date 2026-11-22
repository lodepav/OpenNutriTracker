import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/bulk/submit_label.dart';

// Crit r4 g2: the Log button and its snackbar name the rows held for a unit,
// and say food, not item.
void main() {
  test('the button counts foods, and one dish logged as one', () {
    expect(submitLabel(count: 1, held: 0), 'Log 1 food');
    expect(submitLabel(count: 3, held: 0), 'Log 3 foods');
    expect(submitLabel(count: 0, held: 0), 'Log 0 foods');
    expect(submitLabel(count: 1, held: 0, oneDish: true), 'Log as 1 dish');
    expect(submitLabel(count: 2, held: 0, oneDish: true), 'Log 2 foods');
  });

  test('held rows: what to check when nothing logs, a count beside the rest',
      () {
    expect(submitLabel(count: 0, held: 2), 'Check 2 rows to log');
    expect(heldLabel(count: 0, held: 2), isNull);
    expect(heldLabel(count: 1, held: 0), isNull);
    expect(heldLabel(count: 1, held: 1), '1 waits for a unit');
    expect(heldLabel(count: 1, held: 2), '2 wait for a unit');
  });

  test('the snackbar names the foods left out, at most two', () {
    expect(loggedMessage('Dinner', const []), 'Added to Dinner');
    expect(
      loggedMessage('Dinner', const ['Banana']),
      'Added to Dinner. Banana not logged: check its unit.',
    );
    expect(
      loggedMessage('Dinner', const ['Banana', 'Apple']),
      'Added to Dinner. Banana and Apple not logged: check their units.',
    );
    expect(
      loggedMessage('Dinner', const ['Banana', 'Apple', 'Egg']),
      'Added to Dinner. Banana, Apple and 1 more not logged: check their '
      'units.',
    );
  });
}
