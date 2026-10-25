import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/utils/id_generator.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';

/// What can be measured besides weight (MacroFactor's body metrics).
/// Lengths are stored in cm, body fat in percent.
enum BodyMetric {
  bodyFat('Body fat', '%'),
  waist('Waist', 'cm'),
  hips('Hips', 'cm'),
  chest('Chest', 'cm'),
  neck('Neck', 'cm'),
  leftArm('Left arm', 'cm'),
  rightArm('Right arm', 'cm'),
  leftThigh('Left thigh', 'cm'),
  rightThigh('Right thigh', 'cm');

  final String label;
  final String unit;

  const BodyMetric(this.label, this.unit);

  bool get isLength => unit == 'cm';

  /// [name] as stored, also from before arms and thighs had sides: one
  /// arm or thigh then was the right one, as the MacroFactor import took
  /// it where both were measured.
  static BodyMetric byName(String name) => switch (name) {
    'arm' => rightArm,
    'thigh' => rightThigh,
    _ => values.byName(name),
  };
}

class Measurement {
  final String id;
  final DateTime date;
  final BodyMetric metric;
  final double value;

  const Measurement({
    required this.id,
    required this.date,
    required this.metric,
    required this.value,
  });

  Map<String, Object> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'metric': metric.name,
    'value': value,
  };

  static Measurement fromJson(Map<dynamic, dynamic> json) => Measurement(
    id: json['id'] as String,
    date: DateTime.parse(json['date'] as String),
    metric: BodyMetric.byName(json['metric'] as String),
    value: (json['value'] as num).toDouble(),
  );
}

/// Body measurements, in the fork's per-profile box beside the adaptive
/// state; oldest first.
class MeasurementStore {
  static const _key = 'measurements';

  /// Bumped on every write, so the Trends card reloads.
  static final changes = ValueNotifier(0);

  final Future<Box<dynamic>> Function() _box;

  MeasurementStore([Future<Box<dynamic>> Function()? box])
    : _box = box ?? AdaptiveStore.openActiveBox;

  Future<List<Measurement>> all() async => [
    for (final json in (await _box()).get(_key, defaultValue: []) as List)
      Measurement.fromJson(json as Map),
  ]..sort((a, b) => a.date.compareTo(b.date));

  /// Records [values] on [date]; one already there for a metric that day
  /// is replaced.
  Future<void> addDay(DateTime date, Map<BodyMetric, double> values) async {
    final day = DateTime(date.year, date.month, date.day);
    await _write([
      for (final m in await all())
        if (!(values.containsKey(m.metric) && _sameDay(m.date, day))) m,
      for (final e in values.entries)
        Measurement(
          id: IdGenerator.getUniqueID(),
          date: day,
          metric: e.key,
          value: e.value,
        ),
    ]);
  }

  Future<void> remove(String id) async => _write([
    for (final m in await all())
      if (m.id != id) m,
  ]);

  /// Adds [measurements] from a backup; one with an id already here
  /// replaces it.
  Future<void> merge(List<Measurement> measurements) async {
    final byId = {
      for (final m in [...await all(), ...measurements]) m.id: m,
    };
    await _write(byId.values.toList());
  }

  /// The latest body fat % within [maxAge] of [now], for the energy
  /// density of a weight change; null when there is none.
  Future<double?> recentBodyFat(
    DateTime now, {
    Duration maxAge = const Duration(days: 90),
  }) async {
    final fat = [
      for (final m in await all())
        if (m.metric == BodyMetric.bodyFat && now.difference(m.date) <= maxAge)
          m,
    ];
    return fat.isEmpty ? null : fat.last.value;
  }

  Future<void> _write(List<Measurement> measurements) async {
    await (await _box()).put(_key, [for (final m in measurements) m.toJson()]);
    changes.value++;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
