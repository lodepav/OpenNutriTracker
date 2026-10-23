import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';

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

/// The fork's adaptive state, in an encrypted box per profile like
/// upstream's own per-profile boxes. [settings] holds the active profile's
/// in memory so the weight chart, which builds synchronously, can read it.
class AdaptiveStore {
  static const boxName = 'ForkAdaptiveBox';

  static final settings = ValueNotifier(const AdaptiveSettings());

  final Future<Box<dynamic>> Function() _box;
  final String? _otherProfileSuffix;

  /// The active profile's store, or one over [box] in tests.
  AdaptiveStore([Future<Box<dynamic>> Function()? box])
    : _box = box ?? (() => _open(_activeSuffix())),
      _otherProfileSuffix = null;

  /// Another profile's store, for a meal copied into it.
  AdaptiveStore.forProfile(HiveDBProvider db, String boxSuffix)
    : _box = (() => db.openScopedBox<dynamic>(boxName, boxSuffix)),
      _otherProfileSuffix = boxSuffix;

  static Future<Box<dynamic>> _open(String suffix) =>
      locator<HiveDBProvider>().openScopedBox<dynamic>(boxName, suffix);

  static String _activeSuffix() {
    final db = locator<HiveDBProvider>();
    return db.profileBox.get(db.activeProfileId)?.boxSuffix ?? '';
  }

  /// Run at start-up (seam S6): loads [settings] and reloads them when the
  /// profile switches.
  /// The box of the profile switched away from is closed, as upstream
  /// closes that profile's own.
  static Future<void> start() async {
    var suffix = _activeSuffix();
    await AdaptiveStore().load();
    locator<HiveDBProvider>().addListener(() async {
      final previous = HiveDBProvider.boxNameFor(boxName, suffix);
      suffix = _activeSuffix();
      if (Hive.isBoxOpen(previous)) await Hive.box<dynamic>(previous).close();
      await AdaptiveStore().load();
    });
  }

  /// Closes another profile's box once read, as upstream closes the rest
  /// of that profile's boxes after a copy; the active profile's stays open.
  Future<void> release() async {
    final suffix = _otherProfileSuffix;
    if (suffix == null) return;
    final name = HiveDBProvider.boxNameFor(boxName, suffix);
    if (Hive.isBoxOpen(name)) await Hive.box<dynamic>(name).close();
  }

  Future<void> load() async => settings.value = await read();

  Future<AdaptiveSettings> read() async {
    final box = await _box();
    return AdaptiveSettings(
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

  /// Adds [records] from a backup; one on a date already here replaces it.
  Future<void> mergeCheckIns(List<CheckInRecord> records) async {
    final byDate = {
      for (final r in [...await history(), ...records])
        r.date.toIso8601String(): r,
    };
    final merged = byDate.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    await (await _box()).put('checkIns', [for (final r in merged) r.toJson()]);
  }

  Future<void> addCheckIn(CheckInRecord record) async {
    final box = await _box();
    await box.put('checkIns', [
      ...(box.get('checkIns', defaultValue: []) as List),
      record.toJson(),
    ]);
  }
}
