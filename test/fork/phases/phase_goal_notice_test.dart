import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/phases/phase_goal_notice.dart';
import 'package:opennutritracker/fork/phases/phases.dart';

import '../../helpers/ux_checks.dart';

/// In memory, as real Hive hangs under `testWidgets`.
class _Memory extends PhaseStore {
  @override
  Future<void> dismissGoalNotice() async => PhaseStore.goalNotice.value = null;
}

const _notice = (title: 'New phase: Cut', fromKcal: 2500.0, toKcal: 2000.0);

void main() {
  tearDown(() => PhaseStore.goalNotice.value = null);

  Future<void> pump(
    WidgetTester tester, {
    VoidCallback? onShown,
    PhaseStore? store,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PhaseGoalNoticeCard(onShown: onShown ?? () {}, store: store),
      ),
    ),
  );

  testWidgets('says from what to what, and has Home reload as it appears', (
    tester,
  ) async {
    var shown = 0;
    await pump(tester, onShown: () => shown++);
    expect(find.byType(IconButton), findsNothing);

    PhaseStore.goalNotice.value = _notice;
    await tester.pump();

    expect(find.text('New phase: Cut'), findsOneWidget);
    expect(
      find.text('Your daily goal went from 2500 kcal to 2000 kcal.'),
      findsOneWidget,
    );
    expect(shown, 1);
  });

  testWidgets('Dismiss takes it off', (tester) async {
    PhaseStore.goalNotice.value = _notice;
    await pump(tester, store: _Memory());

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();

    expect(find.text('New phase: Cut'), findsNothing);
  });

  testWidgets('at 200% text: nothing cut, the targets and contrast', (
    tester,
  ) async {
    PhaseStore.goalNotice.value = _notice;
    await checkScreen(tester, const PhaseGoalNoticeCard(onShown: _nothing));
  });
}

void _nothing() {}
