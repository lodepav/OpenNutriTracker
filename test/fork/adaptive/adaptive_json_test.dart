import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/expenditure.dart';
import 'package:opennutritracker/fork/adaptive/macro_program.dart';

/// Through the text a backup holds.
Map<String, dynamic> _viaText(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

void main() {
  test('every setting off its default survives a backup', () {
    const settings = AdaptiveSettings(
      smoothedTrend: true,
      adaptiveTarget: true,
      cycleWindow: true,
      fixedTarget: true,
      fixedKcal: 1850,
      fixedMacros: FixedMacros(proteinG: 150, carbsG: 200, fatG: 60),
      weekdayOffsets: [0, 0, 0, 0, 100, 200, -50],
      macroProgram: MacroProgram(proteinGPerKg: 2),
      responsiveness: Responsiveness.responsive,
      activityMode: ActivityMode.daily,
      countSteps: false,
      countWorkouts: false,
      workoutSharePct: 65,
      checkInWeekday: 3,
      maxCheckInChangeKcal: null,
      autoAcceptCheckIn: true,
      flatEnergy: true,
    );
    final json = settings.toJson();
    // A field added to the settings but not to the JSON shows here.
    expect(json.values.where((v) => v != null).length, json.length - 1);
    final back = AdaptiveSettings.fromJson(_viaText(json));
    expect(back.toJson(), _viaText(json));
    expect(back.targetBasis, settings.targetBasis);
  });

  test('an older backup takes the defaults', () {
    final back = AdaptiveSettings.fromJson(const {});
    expect(back.toJson(), const AdaptiveSettings().toJson());
  });

  test('a check-in survives a backup with all it keeps', () {
    final record = CheckInRecord(
      date: DateTime(2026, 10, 19, 8, 30),
      expenditureKcal: 2950.5,
      proposedKcal: 2480,
      acceptedKcal: 2500,
      activityKcal: 180,
      baseKcal: 2770.5,
      goalRateKgPerWeek: -0.45,
      targetWeightKg: 84,
      basis: const AdaptiveSettings(
        activityMode: ActivityMode.weekly,
      ).targetBasis,
    );
    final back = CheckInRecord.fromJson(_viaText(record.toJson()));
    expect(back.toJson(), record.toJson());
  });

  test('a value of the wrong type throws rather than reading as default', () {
    expect(
      () => AdaptiveSettings.fromJson(const {'flatEnergy': 'yes'}),
      throwsA(isA<TypeError>()),
    );
    expect(
      () => AdaptiveSettings.fromJson(const {'activityMode': 'hourly'}),
      throwsArgumentError,
    );
    expect(
      () => CheckInRecord.fromJson(const {
        'date': '2026-10-19T08:30:00.000',
        'expenditureKcal': 2900,
        'proposedKcal': 2500,
        'acceptedKcal': 2500,
        'basis': 3,
      }),
      throwsA(isA<TypeError>()),
    );
  });
}
