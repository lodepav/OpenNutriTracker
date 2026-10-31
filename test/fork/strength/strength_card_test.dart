import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/strength/strength_card.dart';
import 'package:opennutritracker/fork/strength/strength_signal.dart';

class _Store extends AdaptiveStore {
  final keys = <String, Object?>{};

  @override
  Future<Object?> readKey(String key) async => keys[key];

  @override
  Future<void> writeKey(String key, Object? value) async => keys[key] = value;

  @override
  Future<void> save(AdaptiveSettings settings) async =>
      AdaptiveStore.settings.value = settings;
}

void main() {
  late _Store store;
  late List<double> paces;
  late int applied;
  late int refreshed;
  late int reads;

  setUp(() {
    store = _Store();
    paces = [];
    applied = 0;
    refreshed = 0;
    reads = 0;
    AdaptiveStore.settings.value = const AdaptiveSettings();
  });

  tearDown(() => AdaptiveStore.settings.value = const AdaptiveSettings());

  Future<void> pump(
    WidgetTester tester, {
    StrengthSignal? signal,
    bool noSignal = false,
    bool saved = true,
    double scale = 1,
    Key? key,
  }) => tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: StrengthCard(
              key: key,
              unit: BodyWeightUnit.kg,
              onApplied: () => applied++,
              read: () async {
                reads++;
                return noSignal
                    ? null
                    : signal ??
                          StrengthSignal(
                            trend: 'falling',
                            level: 'warning',
                            muscles: const ['Chest'],
                            phase: 'cutting',
                            lastWorkoutAt: DateTime.now(),
                          );
              },
              rate: () async => -0.4,
              store: store,
              setPace: (kgPerWeek, ProfileStamp startedOn) async {
                paces.add(kgPerWeek);
                return saved;
              },
              refresh: () async => refreshed++,
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('says nothing without a suggestion', (tester) async {
    await pump(tester, noSignal: true);
    await tester.pumpAndSettle();
    expect(find.text('Apply'), findsNothing);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('changes nothing until applied', (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('Chest strength is falling'), findsOneWidget);
    expect(
      find.textContaining('-0.40 kg/week to -0.35 kg/week'),
      findsOneWidget,
    );
    expect(paces, isEmpty);
    expect(applied, 0);
  });

  testWidgets('Not now only hides it, and holds it back', (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Apply'), findsNothing);
    expect(paces, isEmpty);
    expect(applied, 0);
    final answered = StrengthAnswered.decode(store.keys['strengthAnswered']);
    expect(answered?.key, 'falling|Chest');
    // Back after Home rebuilds or the app restarts: still quiet.
    await pump(tester, key: UniqueKey());
    await tester.pumpAndSettle();
    expect(find.text('Apply'), findsNothing);
  });

  testWidgets('Apply moves the pace, and Undo takes it back', (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(paces, [-0.35]);
    expect(applied, 1);
    expect(find.text('Pace is now -0.35 kg/week.'), findsOneWidget);
    expect(find.text('Not now'), findsNothing);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(paces, [-0.35, -0.4]);
    expect(applied, 2);
    // Undoing doesn't ask again straight away.
    expect(find.text('Not now'), findsNothing);
  });

  testWidgets('a pace the profile switch dropped says so, and stays open', (
    tester,
  ) async {
    await pump(tester, saved: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Not changed: the profile changed.'), findsOneWidget);
    expect(applied, 0);
    expect(store.keys, isEmpty);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets('a fixed target moves by the calories, and back', (tester) async {
    AdaptiveStore.settings.value = const AdaptiveSettings(
      fixedTarget: true,
      fixedKcal: 2000,
    );
    await pump(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('raises your fixed target'), findsOneWidget);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(AdaptiveStore.settings.value.fixedKcal, 2055);
    expect(find.text('Target is now 2055 kcal.'), findsOneWidget);
    expect(refreshed, 1);
    expect(paces, isEmpty);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(AdaptiveStore.settings.value.fixedKcal, 2000);
    expect(refreshed, 2);
  });

  testWidgets('a target set by macros gets advice but no Apply', (
    tester,
  ) async {
    AdaptiveStore.settings.value = const AdaptiveSettings(
      fixedTarget: true,
      fixedKcal: 2000,
      fixedMacros: FixedMacros(carbsG: 200, fatG: 60, proteinG: 150),
    );
    await pump(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('macros you set'), findsOneWidget);
    expect(find.text('Apply'), findsNothing);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets('an adaptive target says a check-in follows', (tester) async {
    AdaptiveStore.settings.value = const AdaptiveSettings(adaptiveTarget: true);
    await pump(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('A check-in then updates'), findsOneWidget);
  });

  testWidgets('Home rebuilding asks Go Hevier at most once a minute', (
    tester,
  ) async {
    await pump(tester);
    await tester.pumpAndSettle();
    await pump(tester);
    await tester.pumpAndSettle();
    expect(reads, 1);
  });

  testWidgets('fits at 200% on a phone', (tester) async {
    tester.view.physicalSize = const Size(320, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, scale: 2);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Apply'), findsOneWidget);
  });
}
