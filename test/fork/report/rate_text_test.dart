import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
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

  group('a weekly rate, one form on the You tab', () {
    const kg = BodyWeightUnit.kg;
    test('up to two decimals, trailing zeros trimmed, a true minus', () {
      expect(weeklyRateText(-0.16, kg), '\u22120.16 kg a week');
      expect(weeklyRateText(-0.25, kg), '\u22120.25 kg a week');
      expect(weeklyRateText(0.4, kg), '+0.4 kg a week');
      expect(weeklyRateText(-0.5, kg), '\u22120.5 kg a week');
      expect(weeklyRateText(-1, kg), '\u22121 kg a week');
      expect(weeklyRateSpoken(-0.16, kg), 'down 0.16 kg a week');
      expect(weeklyRateSpoken(0.4, kg), 'up 0.4 kg a week');
      expect(unsignedRateText(-0.4, kg), '0.4 kg a week');
      expect(weeklyRateShown(-0.161, kg), -0.16);
    });

    test('near zero: two decimals, then 0', () {
      expect(weeklyRateText(-0.04, kg), '\u22120.04 kg a week');
      expect(weeklyRateSpoken(0.04, kg), 'up 0.04 kg a week');
      expect(weeklyRateText(-0.004, kg), '0 kg a week');
      expect(weeklyRateText(0, kg), '0 kg a week');
      expect(weeklyRateSpoken(-0.004, kg), 'steady');
      expect(weeklyRateShown(-0.004, kg), 0);
    });

    test('pounds for lb and st', () {
      expect(weeklyRateText(-0.4, BodyWeightUnit.lb), '\u22120.88 lb a week');
      expect(weeklyRateSpoken(-0.4, BodyWeightUnit.st), 'down 0.88 lb a week');
    });
  });
}
