import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/report/rate_text.dart';

// Seam S93: the Weight card's rate never reads "-0.0".
void main() {
  test('signed at two decimals; nothing is 0.00 either way', () {
    expect(signedRate(0.123), '+0.12');
    expect(signedRate(-0.18), '-0.18');
    expect(signedRate(-0.004), '0.00');
    expect(signedRate(0.004), '0.00');
    expect(signedRate(0), '0.00');
  });
}
