import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:health/health.dart';
import 'package:opennutritracker/fork/health/health_grants.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/data/repository/user_repository.dart';
import 'package:opennutritracker/core/data/repository/weight_log_repository.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/utils/bounds/validator.dart';
import 'package:opennutritracker/core/utils/extensions.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/dev/fake_health.dart';

/// One weigh-in as the health store reports it.
class HealthWeight {
  final String id;
  final DateTime measuredAt;
  final double kg;

  const HealthWeight(this.id, this.measuredAt, this.kg);

  /// Later than [other]; two readings at one instant (a scale's app and an
  /// aggregator copying it) are ordered by id, so every run keeps the same.
  bool ranksAfter(HealthWeight other) =>
      measuredAt.isAfter(other.measuredAt) ||
      (measuredAt.isAtSameMomentAs(other.measuredAt) &&
          id.compareTo(other.id) > 0);

  Map<String, Object> toJson() => {
    'id': id,
    'at': measuredAt.toIso8601String(),
    'kg': kg,
  };

  static HealthWeight fromJson(Map<dynamic, dynamic> json) => HealthWeight(
    json['id'] as String,
    DateTime.parse(json['at'] as String),
    (json['kg'] as num).toDouble(),
  );
}

/// Where the readings come from: Health Connect / Apple Health, or a fake
/// on the emulator.
abstract class WeightSource {
  Future<bool> requestPermission();

  /// Readings taken within `[from, to]`; throws when the read is refused.
  Future<List<HealthWeight>> read(DateTime from, DateTime to);
}

class HealthStoreWeights implements WeightSource {
  static const _types = [HealthDataType.WEIGHT];
  static const _read = [HealthDataAccess.READ];

  const HealthStoreWeights();

  @override
  Future<bool> requestPermission() async =>
      await Health().requestAuthorization(_types, permissions: _read) &&
      await hasHealthGrantsOrFalse(['READ_WEIGHT'], _types, _read);

  @override
  Future<List<HealthWeight>> read(DateTime from, DateTime to) async {
    // A revoked grant would read as "no readings" and move the watermark on.
    if (await hasHealthGrants(['READ_WEIGHT'], _types, _read) == false) {
      throw StateError('No permission to read weight');
    }
    final points = await Health().getHealthDataFromTypes(
      types: _types,
      startTime: from,
      endTime: to,
    );
    return [
      for (final point in points)
        if (_kg(point) case final kg?)
          HealthWeight(point.uuid, point.dateFrom, kg),
    ];
  }

  /// The weight in kg, or null for one in an unknown unit or outside the
  /// bounds a typed weight has to pass (a scale or sync fault).
  static double? _kg(HealthDataPoint point) {
    final value = point.value;
    if (value is! NumericHealthValue) return null;
    final n = value.numericValue.toDouble();
    final kg = switch (point.unit) {
      HealthDataUnit.KILOGRAM => n,
      HealthDataUnit.GRAM => n / 1000,
      HealthDataUnit.POUND => n * 0.45359237,
      _ => null,
    };
    return kg == null ? null : ValueValidator.parseWeightInKg(kg);
  }
}

/// Files body weight from the health store in the weight log, which holds
/// one entry per day: each day gets its latest reading (backlog item 3).
///
/// Follows the rules of upstream PR #1296 (markprovan), without its new Hive
/// fields: a per-profile fork box records what was filed for each day, and
/// the log row tells the rest. A row whose weight differs from the record is
/// the user's (typed, or edited) and is never replaced; a recorded day with
/// no row was deleted, and stays empty until a newer reading arrives. When
/// the newest row in the log is an imported one, it becomes the current
/// weight that BMI and the calorie goal use. Swap for upstream's import when
/// it is released.
class WeightImport {
  static const boxName = 'ForkHealthWeightBox';
  static const backfill = Duration(days: 30);

  /// Read back past the last run, for readings a scale's app syncs late.
  static const overlap = Duration(hours: 24);
  static const interval = Duration(minutes: 15);
  static final _log = Logger('WeightImport');

  final WeightSource _source;
  final WeightLogRepository _weights;
  final UserRepository _user;
  final Future<Box<dynamic>> Function() _box;
  final String Function() _profile;
  final DateTime? Function() _profileCreatedAt;
  final DateTime Function() _clock;
  Future<int>? _running;

  WeightImport(
    this._source,
    this._weights,
    this._user, {
    Future<Box<dynamic>> Function()? box,
    String Function()? profile,
    DateTime? Function()? profileCreatedAt,
    DateTime Function()? clock,
  }) : _box = box ?? _activeBox,
       _profile = profile ?? (() => locator<HiveDBProvider>().activeProfileId),
       _profileCreatedAt = profileCreatedAt ?? _activeProfileCreatedAt,
       _clock = clock ?? DateTime.now;

  static WeightImport? _instance;

  /// The import [start] made; null where it was not started (tests).
  static WeightImport? get current => _instance;

  /// Run at start-up (seam S6): imports now and on every resume, at most
  /// every [interval]; [onChanged] refreshes the screens.
  static Future<void> start(void Function() onChanged) async {
    final import = _instance = WeightImport(
      forkFakeHealth ? FakeWeights() : const HealthStoreWeights(),
      locator(),
      locator(),
    );
    Future<void> run() async {
      if (await import.runIfDue() > 0) onChanged();
    }

    unawaited(run());
    WidgetsBinding.instance.addObserver(_Lifecycle(() => unawaited(run())));
  }

  static Future<Box<dynamic>> _activeBox() {
    final db = locator<HiveDBProvider>();
    final suffix = db.profileBox.get(db.activeProfileId)?.boxSuffix ?? '';
    return db.openScopedBox<dynamic>(boxName, suffix);
  }

  static DateTime? _activeProfileCreatedAt() {
    final db = locator<HiveDBProvider>();
    return db.profileBox.get(db.activeProfileId)?.createdAt;
  }

  Future<bool> isOn() async =>
      (await _box()).get('enabled', defaultValue: false) as bool;

  Future<DateTime?> lastImportAt() async =>
      (await _box()).get('lastImportAt') as DateTime?;

  /// Asks for the permission; on a grant turns the import on and runs it.
  /// Returns the days filed, or null when the permission was refused.
  Future<int?> turnOn() async {
    if (!await _source.requestPermission()) return null;
    await (await _box()).put('enabled', true);
    return runNow();
  }

  Future<void> turnOff() async => (await _box()).put('enabled', false);

  /// Logs and swallows failures: nobody is waiting on a background run.
  Future<int> runIfDue() async {
    try {
      final box = await _box();
      if (box.get('enabled', defaultValue: false) != true) return 0;
      final last = box.get('lastImportAt') as DateTime?;
      if (last != null && _clock().difference(last) < interval) return 0;
      return await runNow();
    } catch (error, stack) {
      _log.warning('Weight import failed', error, stack);
      return 0;
    }
  }

  /// Imports and returns how many days were written; throws what the
  /// health store throws.
  Future<int> runNow() =>
      _running ??= _run().whenComplete(() => _running = null);

  Future<int> _run() async {
    final profile = _profile();
    final box = await _box();
    if (box.get('enabled', defaultValue: false) != true) return 0;
    final to = _clock();
    final floor = to.subtract(backfill).subtract(overlap);
    final last = box.get('lastImportAt') as DateTime?;
    final since = last?.subtract(overlap);
    final from = since == null || since.isBefore(floor) ? floor : since;
    final readings = await _source.read(from, to);
    if (_profile() != profile) return 0;

    final filed = {
      for (final MapEntry(:key, :value)
          in (box.get('filed', defaultValue: {}) as Map).entries)
        key as String: HealthWeight.fromJson(value as Map),
    };
    final latest = <String, HealthWeight>{};
    for (final reading in readings) {
      final day = reading.measuredAt.toLocal().toParsedDay();
      if (latest[day] case final other? when !reading.ranksAfter(other)) {
        continue;
      }
      latest[day] = reading;
    }

    var written = 0;
    for (final MapEntry(key: day, value: reading) in latest.entries) {
      final date = DateTime.parse(day);
      final mine = filed[day];
      final row = await _weights.getEntry(date);
      if (row != null && row.weightKg != mine?.kg) continue;
      if (mine != null && !reading.ranksAfter(mine)) continue;
      if (_profile() != profile) return written;
      await _weights.addEntry(
        WeightLogEntity(date: date, weightKg: reading.kg),
      );
      filed[day] = reading;
      written++;
    }

    if (_profile() != profile) return written;
    final floorDay = floor.toParsedDay();
    await box.putAll({
      'filed': {
        for (final MapEntry(:key, :value) in filed.entries)
          if (key.compareTo(floorDay) >= 0) key: value.toJson(),
      },
      'lastImportAt': to,
    });
    await _updateCurrentWeight(filed);
    return written;
  }

  /// The newest row becomes the current weight when the import filed it.
  /// With no row of the user's own, the weight they gave at onboarding is
  /// only replaced by a reading taken after the profile was made.
  Future<void> _updateCurrentWeight(Map<String, HealthWeight> filed) async {
    final rows = await _weights.getAllEntries();
    if (rows.isEmpty || !await _user.hasUserData()) return;
    bool isMine(WeightLogEntity row) =>
        filed[row.date.toParsedDay()]?.kg == row.weightKg;
    final newest = rows.reduce((a, b) => b.date.isAfter(a.date) ? b : a);
    if (!isMine(newest)) return;
    final createdAt = _profileCreatedAt();
    final reading = filed[newest.date.toParsedDay()]!;
    if (!rows.any((row) => !isMine(row)) &&
        createdAt != null &&
        !reading.measuredAt.isAfter(createdAt)) {
      return;
    }
    final user = await _user.getUserData();
    if (user.weightKG == newest.weightKg) return;
    user.weightKG = newest.weightKg;
    await _user.updateUserData(user);
  }
}

class _Lifecycle extends WidgetsBindingObserver {
  final void Function() _onResume;

  _Lifecycle(this._onResume);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onResume();
  }
}
