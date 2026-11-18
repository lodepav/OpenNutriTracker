import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/presentation/widgets/demo_mode_banner.dart';

import '../../../helpers/ux_checks.dart';

// Seam S222: at 2x the banner's text wraps; the eye stays by its first line.
// Seam S232: on a wide window it is as wide as the tabs' content under it.
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

  testWidgets('on a 1280 dp window it keeps to the 600 dp column', (
    tester,
  ) async {
    await pumpOnPhone(
      tester,
      const Column(children: [DemoModeBanner()]),
      textScale: 1,
    );
    tester.view.physicalSize = const Size(1280 * 2.625, 2340);
    await tester.pumpAndSettle();
    final banner = tester.getRect(
      find.bySemanticsIdentifier('main-demo-banner'),
    );
    expect(banner.width, lessThanOrEqualTo(600));
    expect(banner.center.dx, closeTo(640, 1));
  });
}
