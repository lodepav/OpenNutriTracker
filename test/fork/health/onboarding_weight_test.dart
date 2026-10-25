import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/onboarding_body_measurements_page_body.dart';
import 'package:opennutritracker/fork/health/onboarding_weight.dart';
import 'package:opennutritracker/fork/health/weight_import.dart';
import 'package:opennutritracker/generated/l10n.dart';

// Seam S99: onboarding offers the latest Health Connect weigh-in beside the
// typed weight.

class _Source implements WeightSource {
  final bool granted;
  final List<HealthWeight> readings;
  final bool throws;
  (DateTime, DateTime)? asked;

  _Source({this.granted = true, this.readings = const [], this.throws = false});

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<List<HealthWeight>> read(DateTime from, DateTime to) async {
    asked = (from, to);
    if (throws) throw StateError('refused');
    return readings;
  }
}

final _now = DateTime(2026, 10, 25, 9);

void main() {
  group('readLatestHealthWeight', () {
    test('the latest of the past 30 days', () async {
      final source = _Source(
        readings: [
          HealthWeight('a', DateTime(2026, 10, 20), 81),
          HealthWeight('b', DateTime(2026, 10, 24), 80.2),
          HealthWeight('c', DateTime(2026, 10, 1), 83),
        ],
      );
      final read = await readLatestHealthWeight(source, clock: () => _now);

      expect(read, isA<HealthWeightFound>());
      read as HealthWeightFound;
      expect(read.kg, 80.2);
      expect(read.measuredAt, DateTime(2026, 10, 24));
      expect(source.asked, (_now.subtract(const Duration(days: 30)), _now));
    });

    test('no readings', () async {
      expect(
        await readLatestHealthWeight(_Source(), clock: () => _now),
        isA<HealthWeightNone>(),
      );
    });

    test('permission refused: nothing is read', () async {
      final source = _Source(granted: false);
      expect(
        await readLatestHealthWeight(source, clock: () => _now),
        isA<HealthWeightRefused>(),
      );
      expect(source.asked, isNull);
    });

    test('a read that throws counts as refused', () async {
      expect(
        await readLatestHealthWeight(_Source(throws: true), clock: () => _now),
        isA<HealthWeightRefused>(),
      );
    });
  });

  group('onboarding page', () {
    Future<void> pump(
      WidgetTester tester,
      WeightSource source,
      void Function(bool active, double? weight) onWeight,
    ) => tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: OnboardingBodyMeasurementsPageBody(
            healthWeightSource: source,
            setButtonContent: (active, _, weight, _, _, _, _) =>
                onWeight(active, weight),
          ),
        ),
      ),
    );

    final button = find.byKey(const ValueKey('onboarding-health-weight'));

    testWidgets('a weigh-in fills the weight field', (tester) async {
      (bool, double?)? next;
      await pump(
        tester,
        _Source(readings: [HealthWeight('a', DateTime(2026, 10, 24), 80.4)]),
        (active, w) => next = (active, w),
      );
      await tester.enterText(find.byType(TextFormField).first, '180');
      await tester.pump();
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(1))
            .controller!
            .text,
        '80.4',
      );
      expect(
        find.text('From Health Connect, weighed 2026-10-24.'),
        findsOneWidget,
      );
      // With the height typed, Next is on with the read weight.
      expect(next, (true, 80.4));
    });

    testWidgets('refused: says so and leaves the field empty', (tester) async {
      await pump(tester, _Source(granted: false), (_, _) {});
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(
        find.text("Health Connect didn't share your weight. Type it instead."),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(1))
            .controller!
            .text,
        isEmpty,
      );
    });

    testWidgets('no weigh-ins: says so', (tester) async {
      await pump(tester, _Source(), (_, _) {});
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No weigh-ins in Health Connect'),
        findsOneWidget,
      );
    });
  });
}
