import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/calc/calendar_day_calc.dart';
import 'package:opennutritracker/features/add_meal/data/meal_items_api_factory.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/util/meal_photo_encoder.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/adaptive/trend_points.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/fork/leftovers/ai_leftovers.dart'
    show sideBySide;

/// Marks the request, for the fake AI.
const bodyComparePromptStart = 'You compare two progress photos of one person';

/// What was eaten on a day, as its log totals.
typedef DayIntake = ({
  double kcal,
  double? carbs,
  double? fat,
  double? protein,
});

/// What was logged around one photo's day.
class BodyDay {
  final DateTime date;

  /// That day's weigh-in, and the trend weight on it.
  final double? weightKg;
  final double? trendKg;

  /// The latest of each measurement within a week up to the day.
  final Map<BodyMetric, double> measurements;

  /// What was eaten that day and the day before.
  final DayIntake? eaten;
  final DayIntake? eatenBefore;

  const BodyDay({
    required this.date,
    this.weightKg,
    this.trendKg,
    this.measurements = const {},
    this.eaten,
    this.eatenBefore,
  });

  /// From the whole weight log and measurements, and the day's and the day
  /// before's totals.
  factory BodyDay.of(
    DateTime date, {
    required List<WeightLogEntity> weights,
    required List<Measurement> measurements,
    TrackedDayEntity? day,
    TrackedDayEntity? dayBefore,
  }) {
    final on = DateTime(date.year, date.month, date.day);
    bool sameDay(DateTime d) => CalendarDayCalc.daysBetween(on, d) == 0;
    final trend = trendPoints(weights, until: on);
    final latest = <BodyMetric, double>{};
    // Oldest first, so a later one replaces an earlier.
    for (final m in measurements) {
      final age = CalendarDayCalc.daysBetween(m.date, on);
      if (age >= 0 && age < 7) latest[m.metric] = m.value;
    }
    DayIntake? intake(TrackedDayEntity? d) =>
        d == null || d.caloriesTracked <= 0
        ? null
        : (
            kcal: d.caloriesTracked,
            carbs: d.carbsTracked,
            fat: d.fatTracked,
            protein: d.proteinTracked,
          );
    return BodyDay(
      date: on,
      weightKg: weights.where((w) => sameDay(w.date)).lastOrNull?.weightKg,
      trendKg: trend.where((p) => sameDay(p.date)).firstOrNull?.weightKg,
      measurements: latest,
      eaten: intake(day),
      eatenBefore: intake(dayBefore),
    );
  }

  /// The figures, a line each, as the model and the user read them.
  List<String> get lines {
    String n(double v) => v.toStringAsFixed(1);
    String eat(DayIntake d) => [
      '${d.kcal.round()} kcal',
      if (d.carbs case final c?) 'carbs ${c.round()} g',
      if (d.fat case final f?) 'fat ${f.round()} g',
      if (d.protein case final p?) 'protein ${p.round()} g',
    ].join(', ');
    return [
      if (weightKg != null || trendKg != null)
        [
          if (weightKg case final w?) 'weigh-in ${n(w)} kg',
          if (trendKg case final t?) 'trend weight ${n(t)} kg',
        ].join(', '),
      if (measurements.isNotEmpty)
        'measurements: ${[for (final MapEntry(key: m, value: v) in measurements.entries) '${m.label.toLowerCase()} ${n(v)} ${m.unit}'].join(', ')}',
      if (eaten case final e?) 'eaten that day: ${eat(e)}',
      if (eatenBefore case final e?) 'eaten the day before: ${eat(e)}',
    ];
  }
}

String _day(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// The rules for comparing two progress photos, with what was logged
/// around each. The answer rides on upstream's meal-items tool as the
/// label's does: one item per value, its query `key=value`.
String bodyCompareSystemPrompt(BodyDay earlier, BodyDay later) {
  String day(String name, BodyDay d) => [
    '$name, ${_day(d.date)}:',
    ...d.lines.map((l) => '- $l'),
    if (d.lines.isEmpty) '- nothing logged',
  ].join('\n');
  final days = CalendarDayCalc.daysBetween(earlier.date, later.date);
  return '$bodyComparePromptStart, taken $days days apart, to judge how '
      'their body composition changed.\n'
      'The photo has two halves: on the left the earlier day, on the right '
      'the later one.\n'
      'What was logged:\n'
      '${day('Earlier', earlier)}\n'
      '${day('Later', later)}\n'
      'Judge from the photos; the figures only help explain them. First '
      'compare the conditions: lighting (direction, brightness, colour), '
      'pose and posture, camera angle and distance, clothing, flexing or a '
      'pump. Any of these can make a body look leaner or softer with no '
      'real change: name the differences and lower your certainty for '
      'them. A big meal, or much carbohydrate or salt the day before, holds '
      'water and blurs definition; little food the day before can make one '
      'look leaner. A weight change over a few days is mostly water.\n'
      'Record one item per value, and nothing else. Its query is '
      '`key=value`; leave quantity and unit out.\n'
      'Keys:\n'
      '- fat: body fat on the later day against the earlier: less, more, '
      'same or unclear\n'
      '- muscle: muscle on the later day against the earlier: more, less, '
      'same or unclear\n'
      '- certainty: how sure you are of fat and muscle, 0 to 100, a number '
      'only\n'
      '- lighting: how the lighting differs, or same\n'
      '- pose: how pose, angle, distance or clothing differ, or same\n'
      '- sign: one visible change you base the answer on; one item each, '
      'at most five\n'
      '- summary: one or two plain sentences for the person\n'
      'Rules:\n'
      '- No visible difference is same, not a guess either way.\n'
      '- Above 80 only when the conditions match and the change is plain; '
      'under 50 when they differ a lot.\n'
      '- The person chose these as their own photos: take both halves as '
      'the same person. A big change in weight changes the face, build, '
      'hair and skin a lot; that is the change to judge, not a sign of '
      'someone else. Only when the halves plainly cannot be one person (a '
      'man and a woman, a child and an adult) or are not bodies, fat and '
      'muscle are unclear and certainty is 0; say why in summary.\n'
      '- Describe only visible change: never health, attractiveness or '
      'advice.';
}

/// Which way one part of body composition went.
enum BodyChange {
  less,
  more,
  same,
  unclear;

  static BodyChange? parse(String raw) =>
      values.where((v) => v.name == raw.trim().toLowerCase()).firstOrNull;
}

/// The model's comparison.
class BodyComparison {
  final BodyChange fat;
  final BodyChange muscle;

  /// 0 to 100.
  final int certainty;
  final String? lighting;
  final String? pose;
  final List<String> signs;
  final String? summary;

  const BodyComparison({
    required this.fat,
    required this.muscle,
    required this.certainty,
    this.lighting,
    this.pose,
    this.signs = const [],
    this.summary,
  });

  /// From the model's items; null without a certainty or either verdict.
  /// Unknown keys and values are dropped.
  static BodyComparison? fromItems(List<ParsedMealItem> items) {
    BodyChange? fat, muscle;
    int? certainty;
    String? lighting, pose, summary;
    final signs = <String>[];
    for (final item in items) {
      final at = item.query.indexOf('=');
      if (at < 0) continue;
      final key = item.query.substring(0, at).trim().toLowerCase();
      final raw = item.query.substring(at + 1).trim();
      if (raw.isEmpty) continue;
      switch (key) {
        case 'fat':
          fat = BodyChange.parse(raw);
        case 'muscle':
          muscle = BodyChange.parse(raw);
        case 'certainty':
          final n = double.tryParse(
            RegExp(r'\d+(?:\.\d+)?').firstMatch(raw)?[0] ?? '',
          );
          if (n != null) certainty = n.round().clamp(0, 100);
        case 'lighting':
          lighting = raw;
        case 'pose':
          pose = raw;
        case 'sign':
          if (signs.length < 5) signs.add(raw);
        case 'summary':
          summary = raw;
      }
    }
    if (certainty == null || (fat == null && muscle == null)) return null;
    return BodyComparison(
      fat: fat ?? BodyChange.unclear,
      muscle: muscle ?? BodyChange.unclear,
      certainty: certainty,
      lighting: lighting,
      pose: pose,
      signs: signs,
      summary: summary,
    );
  }
}

/// Asks [api] to compare [earlier] and [later], side by side in one image
/// as the leftovers photo is, since upstream's clients carry one photo.
/// Raises [MealInterpreterException] when the call fails or its answer
/// cannot be read.
Future<BodyComparison> compareBodies(
  MealItemsApi api, {
  required MealPhoto earlier,
  required MealPhoto later,
  required BodyDay earlierDay,
  required BodyDay laterDay,
  required MealPhotoFormat format,
}) async => compareJoinedBodies(
  api,
  photo: await sideBySide(earlier, later, format),
  earlierDay: earlierDay,
  laterDay: laterDay,
);

/// [compareBodies] on a [photo] already holding the earlier day on its
/// left and the later on its right.
Future<BodyComparison> compareJoinedBodies(
  MealItemsApi api, {
  required MealPhoto photo,
  required BodyDay earlierDay,
  required BodyDay laterDay,
}) async {
  final result = await api.requestItems(
    content: MealPhotoContent(
      mediaType: photo.mediaType,
      base64Data: base64Encode(photo.bytes),
    ),
    system: bodyCompareSystemPrompt(earlierDay, laterDay),
  );
  final comparison = BodyComparison.fromItems(result.items);
  if (comparison == null) {
    throw const MealInterpreterException('No comparison in the answer');
  }
  return comparison;
}

/// Compares two progress photos with the chosen model.
class CompareBodiesUseCase {
  final AiCredentialStorage _credentials;
  final http.Client _client;

  CompareBodiesUseCase(this._credentials, this._client);

  Future<AiSelection?> get selection => _credentials.readSelection();

  /// Null when no model is set up.
  Future<BodyComparison?> compare({
    required MealPhoto earlier,
    required MealPhoto later,
    required BodyDay earlierDay,
    required BodyDay laterDay,
  }) async {
    final selection = await _credentials.readSelection();
    if (selection == null) return null;
    return compareBodies(
      mealItemsApiFor(_client, selection),
      earlier: earlier,
      later: later,
      earlierDay: earlierDay,
      laterDay: laterDay,
      format: MealPhotoFormat.forProvider(selection.provider),
    );
  }
}
