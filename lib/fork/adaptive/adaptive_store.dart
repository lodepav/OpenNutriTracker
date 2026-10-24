import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/adaptive/macro_program.dart';

/// Fixed daily macros in grams; their energy is the fixed target.
class FixedMacros {
  final double proteinG;
  final double carbsG;
  final double fatG;

  const FixedMacros({
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });

  /// Atwater's 4, 4 and 9 kcal per gram.
  double get kcal => 4 * proteinG + 4 * carbsG + 9 * fatG;

  Map<String, double> toJson() => {
    'proteinG': proteinG,
    'carbsG': carbsG,
    'fatG': fatG,
  };

  static FixedMacros fromJson(Map<dynamic, dynamic> json) => FixedMacros(
    proteinG: (json['proteinG'] as num).toDouble(),
    carbsG: (json['carbsG'] as num).toDouble(),
    fatG: (json['fatG'] as num).toDouble(),
  );
}

/// The two D13 switches, the 28-day window for users with a menstrual
/// cycle (fork/research/phase3-simulation.md), the fixed target (upstream
/// #671) and the per-weekday shift of the target.
class AdaptiveSettings {
  /// Smoothed trend on the weight chart instead of the 7-day average.
  final bool smoothedTrend;

  /// The weekly check-in's target instead of upstream's formula.
  final bool adaptiveTarget;
  final bool cycleWindow;

  /// A target typed by the user instead of either; it wins over
  /// [adaptiveTarget] (the settings dialog keeps one of them on).
  final bool fixedTarget;
  final double fixedKcal;

  /// When set, the fixed target is their energy and the macro goals are
  /// these grams rather than upstream's percentages.
  final FixedMacros? fixedMacros;

  /// kcal added to the target on each weekday, Monday first.
  final List<double> weekdayOffsets;

  /// Macro goals from protein per kg and a diet style, in place of
  /// upstream's percentages; the fixed target's own grams win over it.
  final MacroProgram? macroProgram;

  static const noOffsets = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];

  const AdaptiveSettings({
    this.smoothedTrend = false,
    this.adaptiveTarget = false,
    this.cycleWindow = false,
    this.fixedTarget = false,
    this.fixedKcal = 2000,
    this.fixedMacros,
    this.weekdayOffsets = noOffsets,
    this.macroProgram,
  });

  /// The fixed target's daily energy before the weekday shift.
  double get fixedTargetKcal => switch (fixedMacros) {
    final macros? when macros.kcal > 0 => macros.kcal,
    _ => fixedKcal,
  };

  AdaptiveSettings copyWith({
    bool? smoothedTrend,
    bool? adaptiveTarget,
    bool? cycleWindow,
    bool? fixedTarget,
    double? fixedKcal,
    FixedMacros? Function()? fixedMacros,
    List<double>? weekdayOffsets,
    MacroProgram? Function()? macroProgram,
  }) => AdaptiveSettings(
    smoothedTrend: smoothedTrend ?? this.smoothedTrend,
    adaptiveTarget: adaptiveTarget ?? this.adaptiveTarget,
    cycleWindow: cycleWindow ?? this.cycleWindow,
    fixedTarget: fixedTarget ?? this.fixedTarget,
    fixedKcal: fixedKcal ?? this.fixedKcal,
    fixedMacros: fixedMacros == null ? this.fixedMacros : fixedMacros(),
    weekdayOffsets: weekdayOffsets ?? this.weekdayOffsets,
    macroProgram: macroProgram == null ? this.macroProgram : macroProgram(),
  );

  /// As kept in the box and in `fork_adaptive.json`.
  Map<String, Object?> toJson() => {
    'smoothedTrend': smoothedTrend,
    'adaptiveTarget': adaptiveTarget,
    'cycleWindow': cycleWindow,
    'fixedTarget': fixedTarget,
    'fixedKcal': fixedKcal,
    'fixedMacros': fixedMacros?.toJson(),
    'weekdayOffsets': weekdayOffsets,
    'macroProgram': macroProgram?.toJson(),
  };

  /// Throws on a value of the wrong type; a missing key (an older box or
  /// backup) takes the default.
  static AdaptiveSettings fromJson(Map<dynamic, dynamic> json) {
    final offsets = json['weekdayOffsets'] as List?;
    if (offsets != null && offsets.length != 7) {
      throw const FormatException('weekdayOffsets needs 7 days');
    }
    final macros = json['fixedMacros'] as Map?;
    final program = json['macroProgram'] as Map?;
    return AdaptiveSettings(
      smoothedTrend: json['smoothedTrend'] as bool? ?? false,
      adaptiveTarget: json['adaptiveTarget'] as bool? ?? false,
      cycleWindow: json['cycleWindow'] as bool? ?? false,
      fixedTarget: json['fixedTarget'] as bool? ?? false,
      fixedKcal: (json['fixedKcal'] as num?)?.toDouble() ?? 2000,
      fixedMacros: macros == null ? null : FixedMacros.fromJson(macros),
      weekdayOffsets: offsets == null
          ? noOffsets
          : [for (final o in offsets) (o as num).toDouble()],
      macroProgram: program == null ? null : MacroProgram.fromJson(program),
    );
  }
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

  /// False for another profile's store, whose [save] leaves [settings].
  final bool _active;

  /// The active profile's store, or one over [box] in tests.
  AdaptiveStore([Future<Box<dynamic>> Function()? box])
    : _box = box ?? (() => _open(_activeSuffix())),
      _otherProfileSuffix = null,
      _active = true;

  /// Another profile's store, for a meal copied into it.
  AdaptiveStore.forProfile(HiveDBProvider db, String boxSuffix)
    : _box = (() => db.openScopedBox<dynamic>(boxName, boxSuffix)),
      _otherProfileSuffix = boxSuffix,
      _active = false;

  /// Another profile's store over [box], opened and closed by the caller
  /// (a backup of every profile).
  AdaptiveStore.otherProfile(this._box)
    : _otherProfileSuffix = null,
      _active = false;

  /// The active profile's box, which also holds the meal plan
  /// (`PlanStore`).
  static Future<Box<dynamic>> openActiveBox() => _open(_activeSuffix());

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

  Future<AdaptiveSettings> read() async =>
      AdaptiveSettings.fromJson((await _box()).toMap());

  Future<void> save(AdaptiveSettings value) async {
    final box = await _box();
    await box.putAll(value.toJson());
    if (_active) settings.value = value;
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
