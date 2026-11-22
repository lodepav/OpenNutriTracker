import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/fasting/domain/entity/fasting_session_entity.dart';
import 'package:opennutritracker/features/fasting/presentation/bloc/fasting_bloc.dart';
import 'package:opennutritracker/fork/fasting/fasting_view.dart';

import '../../helpers/ux_checks.dart';

// The history's "Last N fasts" and "x of y reached" share a line only while
// both fit; at 200% text the count goes under the title (A6).

FastingSessionEntity _fast(String id, DateTime start, {required int target}) =>
    FastingSessionEntity(
      id: id,
      startedAt: start,
      targetDurationMinutes: target * 60,
      completedAt: start.add(Duration(hours: target)),
    );

void main() {
  testWidgets('the history header fits at 200% text', (tester) async {
    final now = DateTime(2026, 10, 25, 10);
    DateTime day(int d) => DateTime(2026, 10, 25 - d, 20);
    await pumpOnPhone(
      tester,
      FastingView(
        state: FastingActive(
          session: FastingSessionEntity(
            id: 'now',
            startedAt: DateTime(2026, 10, 25, 5),
            targetDurationMinutes: 16 * 60,
          ),
          now: now,
        ),
        history: Future.value([
          // targets that differ make the longest count, "reached their target"
          for (var d = 6; d >= 1; d--) _fast('$d', day(d), target: 14 + d % 3),
        ]),
        onStart: (_) {},
        onEnd: () {},
        onChange: (_) {},
        pickHours: (_) async => null,
      ),
    );
    tester.view.physicalSize = const Size(1080, 7020);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Last 6 fasts'), findsOneWidget);
    expect(find.text('6 of 6 reached their target'), findsOneWidget);
    expect(cutText(tester), isEmpty);
  });
}
