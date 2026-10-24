import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:health/health.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/utils/extensions.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/fork/dev/fake_health.dart';

/// One body-fat reading as the health store reports it, in percent.
class HealthBodyFat {
  final String id;
  final DateTime measuredAt;
  final double percent;

  const HealthBodyFat(this.id, this.measuredAt, this.percent);

  /// Later than [other]; one instant is ordered by id, as weight's are.
  bool ranksAfter(HealthBodyFat other) =>
      measuredAt.isAfter(other.measuredAt) ||
      (measuredAt.isAtSameMomentAs(other.measuredAt) &&
          id.compareTo(other.id) > 0);

  Map<String, Object> toJson() => {
    'id': id,
    'at': measuredAt.toIso8601String(),
    'percent': percent,
  };

  static HealthBodyFat fromJson(Map<dynamic, dynamic> json) => HealthBodyFat(
    json['id'] as String,
    DateTime.parse(json['at'] as String),
    (json['percent'] as num).toDouble(),
  );
}

abstract class BodyFatSource {
  Future<bool> requestPermission();

  /// Readings taken within `[from, to]`; throws when the read is refused.
  Future<List<HealthBodyFat>> read(DateTime from, DateTime to);
}

class HealthStoreBodyFat implements BodyFatSource {
  static const _types = [HealthDataType.BODY_FAT_PERCENTAGE];
  static const _read = [HealthDataAccess.READ];

  const HealthStoreBodyFat();

  @override
  Future<bool> requestPermission() async =>
      await Health().requestAuthorization(_types, permissions: _read) &&
      await Health().hasPermissions(_types, permissions: _read) != false;

  @override
  Future<List<HealthBodyFat>> read(DateTime from, DateTime to) async {
    if (await Health().hasPermissions(_types, permissions: _read) == false) {
      throw StateError('No permission to read body fat');
    }
    final points = await Health().getHealthDataFromTypes(
      types: _types,
      startTime: from,
      endTime: to,
    );
    return [
      for (final point in points)
        if (point.value case final NumericHealthValue v)
          if (asPercent(v.numericValue.toDouble()) case final percent?)
            HealthBodyFat(point.uuid, point.dateFrom, percent),
    ];
  }

  /// HealthKit reports a fraction, Health Connect a percentage (as upstream's
  /// reader assumes); null outside what a body can hold (a scale fault).
  static double? asPercent(double raw) {
    final percent = raw <= 1 ? raw * 100 : raw;
    return percent >= 2 && percent <= 75 ? percent : null;
  }
}

/// Files body fat % from the health store (a smart scale) in the body
/// measurements, the latest reading of each day, like the weight import
/// (S27): a day whose value differs from what was filed is the user's and
/// is never replaced, and one deleted stays empty until a newer reading.
/// Measured body fat then feeds the expenditure estimate and lean mass.
class BodyFatImport {
  static const _key = 'bodyFatImport';
  static const backfill = Duration(days: 30);
  static const overlap = Duration(hours: 24);
  static const interval = Duration(minutes: 15);
  static final _log = Logger('BodyFatImport');

  final BodyFatSource _source;
  final Future<Box<dynamic>> Function() _box;
  final DateTime Function() _clock;
  Future<int>? _running;

  BodyFatImport(
    this._source, {
    Future<Box<dynamic>> Function()? box,
    DateTime Function()? clock,
  }) : _box = box ?? AdaptiveStore.openActiveBox,
       _clock = clock ?? DateTime.now;

  static BodyFatImport? _instance;

  /// The import [start] made; null where it was not started (tests).
  static BodyFatImport? get current => _instance;

  /// Run at start-up (seam S6): now and on every resume, at most every
  /// [interval].
  static void start() {
    final import = _instance = BodyFatImport(
      forkFakeHealth ? FakeBodyFat() : const HealthStoreBodyFat(),
    );
    void run() => unawaited(import.runIfDue());
    run();
    WidgetsBinding.instance.addObserver(_Lifecycle(run));
  }

  Future<Map<dynamic, dynamic>> _state(Box<dynamic> box) async =>
      (box.get(_key) as Map?) ?? const {};

  Future<bool> isOn() async => (await _state(await _box()))['enabled'] == true;

  /// Asks for the permission; on a grant turns the import on and runs it.
  /// Returns the days filed, or null when the permission was refused.
  Future<int?> turnOn() async {
    if (!await _source.requestPermission()) return null;
    final box = await _box();
    await box.put(_key, {...await _state(box), 'enabled': true});
    return runNow();
  }

  Future<void> turnOff() async {
    final box = await _box();
    await box.put(_key, {...await _state(box), 'enabled': false});
  }

  /// Logs and swallows failures: nobody is waiting on a background run.
  Future<int> runIfDue() async {
    try {
      final state = await _state(await _box());
      if (state['enabled'] != true) return 0;
      final last = state['lastImportAt'] as DateTime?;
      if (last != null && _clock().difference(last) < interval) return 0;
      return await runNow();
    } catch (error, stack) {
      _log.warning('Body fat import failed', error, stack);
      return 0;
    }
  }

  /// Imports and returns how many days were written; throws what the
  /// health store throws.
  Future<int> runNow() =>
      _running ??= _run().whenComplete(() => _running = null);

  Future<int> _run() async {
    // One profile's box for the run; a profile switch closes it, and the
    // run then fails and is logged, writing nothing to the new profile.
    final box = await _box();
    final measurements = MeasurementStore(() async => box);
    final state = await _state(box);
    if (state['enabled'] != true) return 0;
    final to = _clock();
    final floor = to.subtract(backfill).subtract(overlap);
    final since = (state['lastImportAt'] as DateTime?)?.subtract(overlap);
    final from = since == null || since.isBefore(floor) ? floor : since;
    final readings = await _source.read(from, to);

    final filed = {
      for (final MapEntry(:key, :value)
          in ((state['filed'] as Map?) ?? const {}).entries)
        key as String: HealthBodyFat.fromJson(value as Map),
    };
    final latest = <String, HealthBodyFat>{};
    for (final reading in readings) {
      final day = reading.measuredAt.toLocal().toParsedDay();
      if (latest[day] case final other? when !reading.ranksAfter(other)) {
        continue;
      }
      latest[day] = reading;
    }

    final rows = {
      for (final m in await measurements.all())
        if (m.metric == BodyMetric.bodyFat) m.date.toParsedDay(): m.value,
    };
    var written = 0;
    for (final MapEntry(key: day, value: reading) in latest.entries) {
      final mine = filed[day];
      final row = rows[day];
      if (row != null && row != mine?.percent) continue;
      if (mine != null && !reading.ranksAfter(mine)) continue;
      await measurements.addDay(DateTime.parse(day), {
        BodyMetric.bodyFat: reading.percent,
      });
      filed[day] = reading;
      written++;
    }

    final floorDay = floor.toParsedDay();
    await box.put(_key, {
      ...state,
      'filed': {
        for (final MapEntry(:key, :value) in filed.entries)
          if (key.compareTo(floorDay) >= 0) key: value.toJson(),
      },
      'lastImportAt': to,
    });
    return written;
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
