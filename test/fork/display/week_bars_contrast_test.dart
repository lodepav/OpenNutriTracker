import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/fork/display/contrast.dart';
import 'package:opennutritracker/fork/display/week_bars.dart';

int _eightBit(double c) => (c * 255).round();

void main() {
  test('past days stay over 3:1 on the dark card once drawn in 8-bit colour '
      '(the demo blue measured 2.97:1)', () {
    const surface = Color(0xFF252320);
    expect(AppPalette.dark.surface, surface);
    for (final accent in [
      const Color(0xFFB0C6FF),
      AppPalette.dark.accent,
      const Color(0xFF3F5F90),
    ]) {
      final (:today, :past) = weekBarColors(accent, surface);
      final drawn = Color.fromARGB(
        255,
        _eightBit(past.r),
        _eightBit(past.g),
        _eightBit(past.b),
      );
      expect(contrastRatio(drawn, surface), greaterThan(3.05), reason: '$accent');
      expect(contrastRatio(today, past), greaterThanOrEqualTo(1.5));
    }
  });
}
