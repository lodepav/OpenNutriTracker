import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/fork/display/day_ring.dart';
import 'package:opennutritracker/fork/display/day_totals_card.dart';
import 'package:provider/provider.dart';

import '../../helpers/ux_checks.dart';

// The Diary's week strip and day card at a large font on a small phone.

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double scale = 2,
}) async {
  await pumpOnPhone(
    tester,
    ChangeNotifierProvider<EnergyUnitProvider>(
      create: (_) => EnergyUnitProvider(usesKilojoules: false),
      child: SingleChildScrollView(child: child),
    ),
    textScale: scale,
  );
  // 360 x 800 dp at pumpOnPhone's 2.625.
  tester.view.physicalSize = const Size(945, 2100);
  await tester.pump();
}

final _day = TrackedDayEntity(
  day: DateTime(2026, 11, 17),
  calorieGoal: 3098,
  caloriesTracked: 2898,
  carbsGoal: 465,
  fatGoal: 86,
  proteinGoal: 150,
);

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('at ${scale}x a two-digit day stays inside its ring', (
      tester,
    ) async {
      await _pump(
        tester,
        Row(
          children: [
            for (final selected in [false, true])
              Expanded(
                child: DayRing(
                  day: DateTime(2026, 11, 17),
                  trackedDay: _day,
                  selected: selected,
                ),
              ),
          ],
        ),
        scale: scale,
      );
      expect(tester.takeException(), isNull);
      for (final ring in find.byType(DayRing).evaluate()) {
        final square = tester.getRect(
          find
              .descendant(
                of: find.byWidget(ring.widget),
                matching: find.byType(CustomPaint),
              )
              .first,
        );
        // The stroke's inner edge: the 38 dp ring less its 3 dp stroke.
        final inner = square.width / 2 - 3;
        final text = tester.getRect(
          find.descendant(
            of: find.byWidget(ring.widget),
            matching: find.text('17'),
          ),
        );
        for (final corner in [
          text.topLeft,
          text.topRight,
          text.bottomLeft,
          text.bottomRight,
        ]) {
          final d = corner - square.center;
          expect(
            math.sqrt(d.dx * d.dx + d.dy * d.dy),
            lessThan(inner),
            reason: '$corner of $text',
          );
        }
      }
    });
  }

  testWidgets('at 2x on a 360 phone each total leads with its name, '
      'on its figure\'s line, the bar under', (tester) async {
    await _pump(tester, DayTotalsCard(trackedDay: _day, intakes: const []));
    expect(tester.takeException(), isNull);
    final bars = find.byType(LinearProgressIndicator);
    for (final (i, name) in ['Energy', 'Carbs', 'Fat', 'Protein'].indexed) {
      final label = tester.getRect(find.text(name));
      final bar = tester.getRect(bars.at(i));
      expect(label.bottom, lessThanOrEqualTo(bar.top), reason: name);
      final figure = tester.getRect(find.textContaining(' / ').at(i));
      expect(figure.left, greaterThan(label.right), reason: name);
      expect(label.center.dy, inInclusiveRange(figure.top, figure.bottom));
      // The next total's figure is below this one's bar.
      if (i < 3) {
        final next = tester.getRect(find.textContaining(' / ').at(i + 1));
        expect(next.top, greaterThan(bar.bottom), reason: name);
      }
    }
  });

  testWidgets('at 1x the totals stay side by side, each name under its bar', (
    tester,
  ) async {
    await _pump(
      tester,
      DayTotalsCard(trackedDay: _day, intakes: const []),
      scale: 1,
    );
    final bars = find.byType(LinearProgressIndicator);
    for (final (i, name) in ['Energy', 'Carbs', 'Fat', 'Protein'].indexed) {
      expect(
        tester.getRect(find.text(name)).top,
        greaterThanOrEqualTo(tester.getRect(bars.at(i)).bottom),
        reason: name,
      );
    }
    expect(
      tester.getRect(find.text('Protein')).left,
      greaterThan(tester.getRect(find.text('Energy')).right),
    );
  });
}
