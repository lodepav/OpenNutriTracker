import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/presentation/widgets/demo_mode_banner.dart';

import '../../../helpers/ux_checks.dart';

// Seam S222: at 2x the banner's text wraps; the eye stays by its first line.
void main() {
  testWidgets('the eye sits at the first line when the text wraps', (
    tester,
  ) async {
    await pumpOnPhone(tester, const DemoModeBanner());
    final label = find.text("You're viewing sample data");
    final action = find.text('Set up your profile');
    // Wrapped: the action on a line of its own.
    expect(
      tester.getTopLeft(action).dy,
      greaterThan(tester.getTopLeft(label).dy),
    );
    final eye = tester.getRect(find.byIcon(Icons.visibility_outlined));
    final top = tester.getTopLeft(label).dy;
    // One line of the same style: the action's.
    final line = tester.getSize(action).height;
    expect(eye.top, greaterThanOrEqualTo(top));
    expect(eye.bottom, lessThanOrEqualTo(top + line));
  });
}
