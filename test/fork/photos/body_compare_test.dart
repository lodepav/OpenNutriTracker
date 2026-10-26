import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/fork/photos/body_compare.dart';
import 'package:opennutritracker/fork/photos/photo_card.dart';
import 'package:opennutritracker/fork/photos/photo_store.dart';

List<ParsedMealItem> _items(List<String> queries) => [
  for (final q in queries) ParsedMealItem(query: q),
];

/// Answers with [queries], keeping what it was asked.
class _Api implements MealItemsApi {
  final List<String> queries;
  String? system;
  MealContent? content;

  _Api(this.queries);

  @override
  Future<MealTextParseResult> requestItems({
    required MealContent content,
    required String system,
  }) async {
    this.content = content;
    this.system = system;
    return MealTextParseResult(items: _items(queries), errors: const []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Answers without a model or a photo join, counting its calls.
class _UseCase implements CompareBodiesUseCase {
  final BodyComparison? answer;
  final Object? error;
  var calls = 0;

  _UseCase({this.answer, this.error});

  @override
  Future<AiSelection?> get selection async =>
      const AiSelection(provider: AiProvider.openrouter, apiKey: 'k');

  @override
  Future<BodyComparison?> compare({
    required MealPhoto earlier,
    required MealPhoto later,
    required BodyDay earlierDay,
    required BodyDay laterDay,
  }) async {
    calls++;
    if (error case final e?) throw e;
    return answer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final day = DateTime(2026, 10, 20);

  group('the day', () {
    test('its weigh-in, trend, week of measurements and two days eaten', () {
      final d = BodyDay.of(
        day.add(const Duration(hours: 9)),
        weights: [
          WeightLogEntity(date: DateTime(2026, 10, 18, 7), weightKg: 82),
          WeightLogEntity(date: DateTime(2026, 10, 20, 7), weightKg: 81),
        ],
        measurements: [
          Measurement(
            id: 'old',
            date: DateTime(2026, 10, 10),
            metric: BodyMetric.waist,
            value: 90,
          ),
          Measurement(
            id: 'w',
            date: DateTime(2026, 10, 17),
            metric: BodyMetric.waist,
            value: 88.5,
          ),
          Measurement(
            id: 'after',
            date: DateTime(2026, 10, 21),
            metric: BodyMetric.hips,
            value: 99,
          ),
        ],
        day: TrackedDayEntity(
          day: day,
          calorieGoal: 2500,
          caloriesTracked: 2210,
          carbsTracked: 240,
          fatTracked: 70,
          proteinTracked: 150,
        ),
        dayBefore: TrackedDayEntity(
          day: DateTime(2026, 10, 19),
          calorieGoal: 2500,
          caloriesTracked: 3100,
        ),
      );
      expect(d.date, day);
      expect(d.weightKg, 81);
      expect(d.trendKg, isNotNull);
      expect(d.measurements, {BodyMetric.waist: 88.5});
      expect(d.lines, [
        'weigh-in 81.0 kg, trend weight ${d.trendKg!.toStringAsFixed(1)} kg',
        'measurements: waist 88.5 cm',
        'eaten that day: 2210 kcal, carbs 240 g, fat 70 g, protein 150 g',
        'eaten the day before: 3100 kcal',
      ]);
    });

    test('nothing logged: no lines, and the prompt says so', () {
      final none = BodyDay(date: day);
      expect(none.lines, isEmpty);
      final prompt = bodyCompareSystemPrompt(
        BodyDay(date: DateTime(2026, 8, 1)),
        none,
      );
      expect(prompt, startsWith(bodyComparePromptStart));
      expect(prompt, contains('taken 80 days apart'));
      expect(prompt, contains('Earlier, 2026-08-01:\n- nothing logged'));
      expect(prompt, contains('lighting'));
      expect(prompt, contains('certainty'));
    });
  });

  group('the answer', () {
    test('read from its items; unknown values and keys dropped', () {
      final c = BodyComparison.fromItems(
        _items([
          'fat=Less',
          'muscle=bigger',
          'certainty=about 72.6%',
          'lighting=warmer light on the right',
          'pose=same',
          for (var i = 0; i < 7; i++) 'sign=s$i',
          'summary=Leaner.',
          'mood=happy',
          'no equals sign',
        ]),
      )!;
      expect(c.fat, BodyChange.less);
      expect(c.muscle, BodyChange.unclear);
      expect(c.certainty, 73);
      expect(c.lighting, 'warmer light on the right');
      expect(c.pose, 'same');
      expect(c.signs, ['s0', 's1', 's2', 's3', 's4']);
      expect(c.summary, 'Leaner.');
    });

    test('a certainty past 100 is 100; none, or no verdict, is no answer', () {
      expect(
        BodyComparison.fromItems(
          _items(['fat=same', 'certainty=140']),
        )!.certainty,
        100,
      );
      expect(BodyComparison.fromItems(_items(['fat=same'])), isNull);
      expect(BodyComparison.fromItems(_items(['certainty=50'])), isNull);
    });

    test('the request: the joined photo and both days\' figures', () async {
      final api = _Api(['fat=more', 'muscle=more', 'certainty=40']);
      final c = await compareJoinedBodies(
        api,
        photo: MealPhoto(bytes: Uint8List(3), mediaType: 'image/jpeg'),
        earlierDay: BodyDay(date: DateTime(2026, 9, 1), weightKg: 80),
        laterDay: BodyDay(date: day, weightKg: 84),
      );
      expect(c.fat, BodyChange.more);
      expect(c.certainty, 40);
      expect(api.system, contains('Earlier, 2026-09-01:\n- weigh-in 80.0 kg'));
      expect(api.system, contains('Later, 2026-10-20:\n- weigh-in 84.0 kg'));
      expect((api.content! as MealPhotoContent).mediaType, 'image/jpeg');
    });

    test('an answer with nothing to read fails as retryable', () async {
      await expectLater(
        compareJoinedBodies(
          _Api(['banana']),
          photo: MealPhoto(bytes: Uint8List(3), mediaType: 'image/jpeg'),
          earlierDay: BodyDay(date: DateTime(2026, 9, 1)),
          laterDay: BodyDay(date: day),
        ),
        throwsA(
          isA<MealInterpreterException>().having(
            (e) => e.failure,
            'failure',
            MealInterpreterFailure.transient,
          ),
        ),
      );
    });
  });

  group('the screen', () {
    late Directory dir;
    late List<ShownPhoto> photos;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('bodies');
      photos = [
        for (final (id, date) in [
          ('a', DateTime(2026, 8, 1)),
          ('b', DateTime(2026, 10, 1)),
        ])
          (
            photo: ProgressPhoto(id: id, date: date),
            file: File('${dir.path}/$id.jpg')..writeAsBytesSync([1, 2, 3]),
          ),
      ];
    });

    tearDown(() => dir.deleteSync(recursive: true));

    Future<void> pump(
      WidgetTester tester,
      CompareBodiesUseCase? useCase,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ComparePhotosScreen(
            photos: photos,
            useCase: useCase,
            loadDay: (d) async =>
                BodyDay(date: d, weightKg: d.month == 8 ? 84 : 81.5),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    const answer = BodyComparison(
      fat: BodyChange.less,
      muscle: BodyChange.same,
      certainty: 62,
      lighting: 'brighter on the right',
      pose: 'same',
      signs: ['narrower waist'],
      summary: 'A little leaner.',
    );

    testWidgets('no model set up: no Ask AI', (tester) async {
      await pump(tester, null);
      expect(find.byKey(const ValueKey('compare-ai')), findsNothing);
    });

    testWidgets('asks first, naming where it goes and what; then answers', (
      tester,
    ) async {
      final useCase = _UseCase(answer: answer);
      await pump(tester, useCase);
      await tester.tap(find.byKey(const ValueKey('compare-ai')));
      await tester.pumpAndSettle();
      expect(find.textContaining('to OpenRouter'), findsOne);
      expect(find.text('Earlier, 2026-08-01'), findsOne);
      expect(find.text('weigh-in 84.0 kg'), findsOne);
      expect(find.text('weigh-in 81.5 kg'), findsOne);

      // Cancelled: nothing sent.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(useCase.calls, 0);

      await tester.tap(find.byKey(const ValueKey('compare-ai')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('body-compare-send')));
      await tester.pumpAndSettle();
      expect(useCase.calls, 1);
      expect(find.text('Less body fat'), findsOne);
      expect(find.text('Muscle looks the same'), findsOne);
      expect(find.text('Certainty 62%'), findsOne);
      expect(find.text('A little leaner.'), findsOne);
      expect(find.text('• narrower waist'), findsOne);
      expect(find.textContaining('brighter on the right'), findsOne);

      // Kept for the pair: shown again without asking.
      Navigator.of(tester.element(find.text('Less body fat'))).pop();
      await tester.pumpAndSettle();
      expect(find.text('AI result'), findsOne);
      await tester.tap(find.byKey(const ValueKey('compare-ai')));
      await tester.pumpAndSettle();
      expect(find.text('Less body fat'), findsOne);
      expect(useCase.calls, 1);
    });

    testWidgets('a failed call says so', (tester) async {
      await pump(
        tester,
        _UseCase(error: const MealInterpreterException('down')),
      );
      await tester.tap(find.byKey(const ValueKey('compare-ai')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('body-compare-send')));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't compare the photos. Try again."), findsOne);
    });
  });
}
