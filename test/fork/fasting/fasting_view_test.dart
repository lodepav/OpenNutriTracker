import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/fasting/domain/entity/fasting_session_entity.dart';
import 'package:opennutritracker/features/fasting/presentation/bloc/fasting_bloc.dart';
import 'package:opennutritracker/fork/fasting/fasting_view.dart';
import 'package:opennutritracker/generated/l10n.dart';

// Seam S123: the fasting timer, its plans and its history.

final _now = DateTime(2026, 10, 25, 10, 1);

FastingSessionEntity _fast(
  String id,
  DateTime start, {
  int hours = 16,
  Duration? ran,
  bool cancelled = false,
}) => FastingSessionEntity(
  id: id,
  startedAt: start,
  targetDurationMinutes: hours * 60,
  completedAt: ran == null || cancelled ? null : start.add(ran),
  cancelledAt: ran != null && cancelled ? start.add(ran) : null,
);

class _Calls {
  final started = <int>[];
  final changed = <FastingSessionEntity>[];
  var ended = 0;
}

Future<_Calls> _pump(
  WidgetTester tester,
  FastingState state, {
  List<FastingSessionEntity> history = const [],
  int? custom,
}) async {
  final calls = _Calls();
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.supportedLocales,
      home: Scaffold(
        body: FastingView(
          state: state,
          history: Future.value(history),
          onStart: calls.started.add,
          onEnd: () => calls.ended++,
          onChange: calls.changed.add,
          pickHours: (_) async => custom,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return calls;
}

void main() {
  final active = _fast('now', DateTime(2026, 10, 25, 5, 0));

  testWidgets('a fast under way: what is left, what is done, when it ends', (
    tester,
  ) async {
    final calls = await _pump(
      tester,
      FastingActive(session: active, now: _now),
    );
    expect(find.text('10h 59m'), findsOneWidget);
    expect(find.text('5h 01m'), findsOneWidget);
    expect(find.text('of a 16-hour fast · 31%'), findsOneWidget);
    expect(find.text('5:00 AM'), findsOneWidget);
    expect(find.text('Today · edit'), findsOneWidget);
    expect(find.text('9:00 PM'), findsOneWidget);
    await tester.tap(find.text('End fast'));
    expect(calls.ended, 1);
  });

  testWidgets('a plan picked during a fast is its new target', (tester) async {
    final calls = await _pump(
      tester,
      FastingActive(session: active, now: _now),
    );
    await tester.tap(find.text('18:6'));
    await tester.pump();
    expect(calls.changed.single.targetDurationMinutes, 18 * 60);
    expect(calls.changed.single.startedAt, active.startedAt);
    expect(calls.changed.single.id, 'now');
    // The plan it has already is no change.
    await tester.tap(find.text('16:8'));
    await tester.pump();
    expect(calls.changed, hasLength(1));
  });

  testWidgets('before a fast, the plan picked is the one started', (
    tester,
  ) async {
    final calls = await _pump(tester, const FastingIdle());
    await tester.tap(find.text('20:4'));
    await tester.pump();
    await tester.tap(find.text('Start timer'));
    expect(calls.started, [20 * 60]);
  });

  testWidgets('a custom plan', (tester) async {
    final calls = await _pump(tester, const FastingIdle(), custom: 36);
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    expect(find.text('36 h'), findsOneWidget);
    await tester.tap(find.text('Start timer'));
    expect(calls.started, [36 * 60]);
  });

  testWidgets('the last fasts against their targets', (tester) async {
    DateTime day(int d) => DateTime(2026, 10, 25 - d, 20);
    await _pump(
      tester,
      FastingActive(session: active, now: _now),
      history: [
        _fast('a', day(3), ran: const Duration(hours: 16)),
        _fast('b', day(2), ran: const Duration(hours: 12), cancelled: true),
        _fast('c', day(1), ran: const Duration(hours: 16)),
        active,
      ],
    );
    expect(find.text('Last 4 fasts'), findsOneWidget);
    expect(find.text('2 of 3 reached 16 h'), findsOneWidget);
    final labels = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .map((w) => w.properties.label)
        .whereType<String>();
    expect(labels, contains('Friday: 12h 00m of 16h 00m'));
    expect(labels, contains('Sunday: 5h 01m of 16h 00m, under way'));
  });

  test('recentFasts: the last seven, oldest first, by how long they ran', () {
    final sessions = [
      for (var i = 0; i < 9; i++)
        _fast(
          '$i',
          DateTime(2026, 10, 10 + i, 20),
          ran: Duration(hours: 10 + i),
        ),
      // Never ended, not under way: an old crash. Left out.
      FastingSessionEntity(
        id: 'x',
        startedAt: DateTime(2026, 10, 1),
        targetDurationMinutes: 960,
        cancelledAt: null,
      ),
    ]..shuffle();
    final fasts = recentFasts(sessions, _now);
    expect(fasts, hasLength(7));
    expect(fasts.first.length, const Duration(hours: 12));
    expect(fasts.last.length, const Duration(hours: 18));
  });

  test('a start time still to come today was yesterday', () {
    expect(
      fastStartAt(const TimeOfDay(hour: 20, minute: 30), _now),
      DateTime(2026, 10, 24, 20, 30),
    );
    expect(
      fastStartAt(const TimeOfDay(hour: 6, minute: 15), _now),
      DateTime(2026, 10, 25, 6, 15),
    );
  });

  test('hoursMinutes', () {
    expect(hoursMinutes(const Duration(hours: 10, minutes: 59)), '10h 59m');
    expect(hoursMinutes(const Duration(minutes: -5)), '0h 00m');
  });
}
