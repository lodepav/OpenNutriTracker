import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/dbo/fasting_session_dbo.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/water_intake_dbo.dart';
import 'package:opennutritracker/core/data/repository/water_intake_repository.dart';
import 'package:opennutritracker/features/fasting/data/data_source/fasting_data_source.dart';
import 'package:opennutritracker/features/settings/domain/export_import_failure.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';

/// What the JSON backup leaves out and the fork adds (phase 2, seam S21):
/// the water log, fasting sessions, saved custom meals and the adaptive
/// target's switches and check-ins.
///
/// Ported from theoleuthardt's `PersonalBackupExtras` (GPL-3.0, their #93,
/// #94, #97), without its profile and app-settings files. Every file is
/// optional on restore, so upstream's zips and older ones still import.
class BackupExtras {
  static const waterFileName = 'water_intake.json';
  static const fastingFileName = 'fasting_sessions.json';
  static const customMealsFileName = 'custom_meals.json';
  static const adaptiveFileName = 'fork_adaptive.json';

  final WaterIntakeRepository _water;
  final FastingDataSource _fasting;
  final CustomMealDataSource _customMeals;
  final AdaptiveStore Function() _adaptive;

  BackupExtras(
    this._water,
    this._fasting,
    this._customMeals, {
    AdaptiveStore Function()? adaptive,
  }) : _adaptive = adaptive ?? AdaptiveStore.new;

  Future<void> addTo(Archive archive) async {
    _addJson(archive, waterFileName, [
      for (final entry in await _water.getAllEntriesDBO()) entry.toJson(),
    ]);
    _addJson(archive, fastingFileName, [
      for (final session in await _fasting.allSessions()) session.toJson(),
    ]);
    _addJson(archive, customMealsFileName, [
      for (final meal in _customMeals.getAllCustomMeals()) meal.toJson(),
    ]);
    final adaptive = _adaptive();
    final settings = await adaptive.read();
    _addJson(archive, adaptiveFileName, {
      'smoothedTrend': settings.smoothedTrend,
      'adaptiveTarget': settings.adaptiveTarget,
      'cycleWindow': settings.cycleWindow,
      'checkIns': [for (final c in await adaptive.history()) c.toJson()],
    });
  }

  /// Decodes everything first and returns the writes, so a malformed file
  /// throws an [ExportImportFailure] before the import has written anything.
  /// Each write replaces by id (custom meals: by barcode, else name;
  /// check-ins: by date), so a second restore adds nothing.
  Future<void> Function() prepareRestore(Archive archive) {
    final water = _decode(
      archive,
      waterFileName,
      (json) => [for (final e in json as List) WaterIntakeDBO.fromJson(e)],
    );
    final fasting = _decode(
      archive,
      fastingFileName,
      (json) => [for (final e in json as List) FastingSessionDBO.fromJson(e)],
    );
    final customMeals = _decode(
      archive,
      customMealsFileName,
      (json) => [for (final e in json as List) MealDBO.fromJson(e)],
    );
    final adaptive = _decode(archive, adaptiveFileName, (json) {
      final map = json as Map<String, dynamic>;
      return (
        settings: AdaptiveSettings(
          smoothedTrend: map['smoothedTrend'] as bool,
          adaptiveTarget: map['adaptiveTarget'] as bool,
          cycleWindow: map['cycleWindow'] as bool,
        ),
        checkIns: [
          for (final c in map['checkIns'] as List) CheckInRecord.fromJson(c),
        ],
      );
    });

    return () async {
      if (water != null) await _water.addAllEntries(water);
      for (final session in fasting ?? const <FastingSessionDBO>[]) {
        await _fasting.updateSession(session);
      }
      for (final meal in customMeals ?? const <MealDBO>[]) {
        await _customMeals.saveCustomMeal(meal);
      }
      if (adaptive != null) {
        final store = _adaptive();
        await store.mergeCheckIns(adaptive.checkIns);
        await store.save(adaptive.settings);
      }
    };
  }

  static void _addJson(Archive archive, String name, Object json) {
    final bytes = utf8.encode(jsonEncode(json));
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  static T? _decode<T>(
    Archive archive,
    String name,
    T Function(Object? json) parse,
  ) {
    final file = archive.findFile(name);
    if (file == null) return null;
    return ExportImportFailure.guardSync(
      ExportImportFailureReason.unreadableOrWrongFormat,
      'Could not parse $name',
      () => parse(jsonDecode(utf8.decode(file.content as List<int>))),
    );
  }
}
