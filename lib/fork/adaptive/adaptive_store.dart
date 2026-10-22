import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

/// The two D13 switches, plus the 28-day window for users with a
/// menstrual cycle (fork/research/phase3-simulation.md).
class AdaptiveSettings {
  /// Smoothed trend on the weight chart instead of the 7-day average.
  final bool smoothedTrend;

  /// The weekly check-in's target instead of upstream's formula.
  final bool adaptiveTarget;
  final bool cycleWindow;

  const AdaptiveSettings({
    this.smoothedTrend = false,
    this.adaptiveTarget = false,
    this.cycleWindow = false,
  });

  AdaptiveSettings copyWith({
    bool? smoothedTrend,
    bool? adaptiveTarget,
    bool? cycleWindow,
  }) => AdaptiveSettings(
    smoothedTrend: smoothedTrend ?? this.smoothedTrend,
    adaptiveTarget: adaptiveTarget ?? this.adaptiveTarget,
    cycleWindow: cycleWindow ?? this.cycleWindow,
  );
}

/// One check-in as accepted: kept so the next one knows where the target
/// stands, and as the history phase 2's backup must carry.
class CheckInRecord {
  final DateTime date;
  final double expenditureKcal;
  final double proposedKcal;
  final double acceptedKcal;

  const CheckInRecord({
    required this.date,
    required this.expenditureKcal,
    required this.proposedKcal,
    required this.acceptedKcal,
  });

  Map<String, Object> toJson() => {
    'date': date.toIso8601String(),
    'expenditureKcal': expenditureKcal,
    'proposedKcal': proposedKcal,
    'acceptedKcal': acceptedKcal,
  };

  static CheckInRecord fromJson(Map<dynamic, dynamic> json) => CheckInRecord(
    date: DateTime.parse(json['date'] as String),
    expenditureKcal: (json['expenditureKcal'] as num).toDouble(),
    proposedKcal: (json['proposedKcal'] as num).toDouble(),
    acceptedKcal: (json['acceptedKcal'] as num).toDouble(),
  );
}

/// The fork's adaptive state, in a box of its own. [settings] is also held
/// in memory so the weight chart, which builds synchronously, can read it.
class AdaptiveStore {
  static const boxName = 'fork_adaptive';

  static final settings = ValueNotifier(const AdaptiveSettings());

  final Future<Box<dynamic>> Function() _box;

  AdaptiveStore([Future<Box<dynamic>> Function()? box])
    : _box = box ?? (() => Hive.openBox<dynamic>(boxName));

  /// Run at start-up (seam S6), before anything reads [settings].
  Future<void> load() async {
    final box = await _box();
    settings.value = AdaptiveSettings(
      smoothedTrend: box.get('smoothedTrend', defaultValue: false) as bool,
      adaptiveTarget: box.get('adaptiveTarget', defaultValue: false) as bool,
      cycleWindow: box.get('cycleWindow', defaultValue: false) as bool,
    );
  }

  Future<void> save(AdaptiveSettings value) async {
    final box = await _box();
    await box.putAll({
      'smoothedTrend': value.smoothedTrend,
      'adaptiveTarget': value.adaptiveTarget,
      'cycleWindow': value.cycleWindow,
    });
    settings.value = value;
  }

  Future<List<CheckInRecord>> history() async => [
    for (final json in (await _box()).get('checkIns', defaultValue: []) as List)
      CheckInRecord.fromJson(json as Map),
  ];

  Future<CheckInRecord?> lastCheckIn() async {
    final all = await history();
    return all.isEmpty ? null : all.last;
  }

  Future<void> addCheckIn(CheckInRecord record) async {
    final box = await _box();
    await box.put('checkIns', [
      ...(box.get('checkIns', defaultValue: []) as List),
      record.toJson(),
    ]);
  }
}
