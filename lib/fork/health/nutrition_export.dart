import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:health/health.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/dev/fake_health.dart';
import 'package:opennutritracker/fork/history/history_file.dart';

/// One diary entry as a Health Connect nutrition record, in grams.
class NutritionRecord {
  /// The record's client id: the entry's own, so an edit replaces it.
  final String clientId;
  final IntakeTypeEntity meal;
  final DateTime at;
  final String name;
  final double kcal;
  final double carbs;
  final double protein;
  final double fat;
  final double? fiber;
  final double? sugar;
  final double? saturatedFat;
  final double? sodium;

  const NutritionRecord({
    required this.clientId,
    required this.meal,
    required this.at,
    required this.name,
    required this.kcal,
    required this.carbs,
    required this.protein,
    required this.fat,
    this.fiber,
    this.sugar,
    this.saturatedFat,
    this.sodium,
  });

  static String clientIdOf(String intakeId) => 'openbite-$intakeId';

  factory NutritionRecord.of(IntakeEntity intake) {
    final n = intake.meal.nutriments;
    double? total(double? per100) =>
        per100 == null ? null : intake.amount * per100 / 100;
    return NutritionRecord(
      clientId: clientIdOf(intake.id),
      meal: intake.type,
      // A date-only entry (a UTC midnight from the Diary, or an import's)
      // at noon of its date, so other apps file it on that day in any zone.
      at: DayBoundaryCalc.isDayLabel(intake.dateTime)
          ? DateTime(
              intake.dateTime.year,
              intake.dateTime.month,
              intake.dateTime.day,
              12,
            )
          : intake.dateTime,
      name: intake.meal.name ?? '',
      kcal: intake.totalKcal,
      carbs: intake.totalCarbsGram,
      protein: intake.totalProteinsGram,
      fat: intake.totalFatsGram,
      fiber: total(n.fiber100),
      sugar: total(n.sugars100),
      saturatedFat: total(n.saturatedFat100),
      // mg in the diary, grams in Health Connect.
      sodium: total(n.sodium100) == null ? null : total(n.sodium100)! / 1000,
    );
  }

  /// Changes whenever what is written would: an edit to the amount, the
  /// time (a timeline move) or the food.
  String get signature => [
    meal.name,
    at.toIso8601String(),
    name,
    for (final v in [kcal, carbs, protein, fat, fiber, sugar])
      v?.toStringAsFixed(2),
    saturatedFat?.toStringAsFixed(2),
    sodium?.toStringAsFixed(4),
  ].join('|');
}

/// Where the records go: Health Connect, or a fake on the emulator.
abstract class NutritionSink {
  Future<bool> requestPermission();

  /// Writes [record], replacing one of its client id written at a lower
  /// [version]; throws when refused.
  Future<void> write(NutritionRecord record, int version);
  Future<void> delete(String clientId);
}

class HealthStoreNutrition implements NutritionSink {
  static const _types = [HealthDataType.NUTRITION];
  static const _write = [HealthDataAccess.WRITE];

  const HealthStoreNutrition();

  @override
  Future<bool> requestPermission() async =>
      await Health().requestAuthorization(_types, permissions: _write) &&
      await Health().hasPermissions(_types, permissions: _write) != false;

  @override
  Future<void> write(NutritionRecord record, int version) async {
    final ok = await Health().writeMeal(
      mealType: switch (record.meal) {
        IntakeTypeEntity.breakfast => MealType.BREAKFAST,
        IntakeTypeEntity.lunch => MealType.LUNCH,
        IntakeTypeEntity.dinner => MealType.DINNER,
        IntakeTypeEntity.snack => MealType.SNACK,
      },
      // Health Connect wants an interval; a minute stands for the moment.
      startTime: record.at,
      endTime: record.at.add(const Duration(minutes: 1)),
      clientRecordId: record.clientId,
      clientRecordVersion: version.toDouble(),
      name: record.name,
      caloriesConsumed: record.kcal,
      carbohydrates: record.carbs,
      protein: record.protein,
      fatTotal: record.fat,
      fiber: record.fiber,
      sugar: record.sugar,
      fatSaturated: record.saturatedFat,
      sodium: record.sodium,
      recordingMethod: RecordingMethod.manual,
    );
    if (!ok) throw StateError('Health Connect refused ${record.clientId}');
  }

  @override
  Future<void> delete(String clientId) async {
    final ok = await Health().deleteByClientRecordId(
      dataTypeKey: HealthDataType.NUTRITION,
      clientRecordId: clientId,
    );
    if (!ok) throw StateError('Health Connect kept $clientId');
  }
}

/// Writes the diary's calories and macros to Health Connect (WRITE_NUTRITION,
/// seam S49), one record per entry under the entry's id: an edited entry
/// (amount, time, food) is written again over its record, and a deleted one
/// has its record removed. Run when the app opens and when it is left, over
/// the entries of the past [window]; what was written is kept per profile
/// in the fork's box, so only changes go out.
class NutritionExport {
  static const _key = 'nutritionExport';
  static const window = Duration(days: 14);
  static final _log = Logger('NutritionExport');

  final NutritionSink _sink;
  final Future<List<IntakeEntity>> Function(DateTime since) _intakes;
  final Future<Box<dynamic>> Function() _box;
  final DateTime Function() _clock;
  Future<int>? _running;

  NutritionExport(
    this._sink, {
    Future<List<IntakeEntity>> Function(DateTime since)? intakes,
    Future<Box<dynamic>> Function()? box,
    DateTime Function()? clock,
  }) : _intakes = intakes ?? _fromRepository,
       _box = box ?? AdaptiveStore.openActiveBox,
       _clock = clock ?? DateTime.now;

  static Future<List<IntakeEntity>> _fromRepository(DateTime since) async => [
    for (final dbo in await locator<IntakeRepository>().getAllIntakesDBO())
      if (!dbo.dateTime.isBefore(since)) IntakeEntity.fromIntakeDBO(dbo),
  ];

  static NutritionExport? _instance;

  /// The export [start] made; null where it was not started (tests).
  static NutritionExport? get current => _instance;

  /// Run at start-up (seam S6): now, and whenever the app is opened or
  /// left.
  static void start() {
    final export = _instance = NutritionExport(
      forkFakeHealth ? FakeNutrition() : const HealthStoreNutrition(),
    );
    void run() => unawaited(export.runIfOn());
    run();
    WidgetsBinding.instance.addObserver(_Lifecycle(run));
  }

  Future<Map<dynamic, dynamic>> _state(Box<dynamic> box) async =>
      (box.get(_key) as Map?) ?? const {};

  Future<bool> isOn() async => (await _state(await _box()))['enabled'] == true;

  /// Asks for the permission; on a grant turns the export on and runs it.
  /// Returns the entries written, or null when the permission was refused.
  Future<int?> turnOn() async {
    if (!await _sink.requestPermission()) return null;
    final box = await _box();
    await box.put(_key, {...await _state(box), 'enabled': true});
    return runNow();
  }

  /// Records already written stay in Health Connect; turned on again, the
  /// export writes the window afresh over them.
  Future<void> turnOff() async => (await _box()).put(_key, {'enabled': false});

  /// Logs and swallows failures: nobody is waiting on a background run.
  Future<int> runIfOn() async {
    try {
      if (!await isOn()) return 0;
      return await runNow();
    } catch (error, stack) {
      _log.warning('Nutrition export failed', error, stack);
      return 0;
    }
  }

  /// Writes what changed and returns how many records were written or
  /// removed; throws what Health Connect throws, keeping what went out.
  Future<int> runNow() =>
      _running ??= _run().whenComplete(() => _running = null);

  Future<int> _run() async {
    final box = await _box();
    final state = await _state(box);
    if (state['enabled'] != true) return 0;
    final now = _clock();
    final since = DateTime(now.year, now.month, now.day).subtract(window);
    final written = {
      for (final MapEntry(:key, :value)
          in ((state['written'] as Map?) ?? const {}).entries)
        key as String: Map<String, Object?>.from(value as Map),
    };
    Future<void> save() => box.put(_key, {...state, 'written': written});

    var changed = 0;
    try {
      final records = {
        for (final intake in await _intakes(since))
          // An imported day's totals: the app they came from has likely
          // written that day to Health Connect already.
          if (!isImportedHistory(intake)) intake.id: NutritionRecord.of(intake),
      };
      for (final MapEntry(key: id, value: record) in records.entries) {
        if (written[id]?['sig'] == record.signature) continue;
        await _sink.write(record, now.millisecondsSinceEpoch);
        written[id] = {'sig': record.signature, 'at': record.at};
        changed++;
      }
      for (final id in [...written.keys]) {
        if (records.containsKey(id)) continue;
        final at = written[id]!['at'] as DateTime;
        // Out of the window it is only forgotten; within, it was deleted.
        if (!at.isBefore(since)) {
          await _sink.delete(NutritionRecord.clientIdOf(id));
          changed++;
        }
        written.remove(id);
      }
    } finally {
      await save();
    }
    return changed;
  }
}

class _Lifecycle extends WidgetsBindingObserver {
  final void Function() _run;

  _Lifecycle(this._run);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.paused) {
      _run();
    }
  }
}
