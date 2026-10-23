import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:opennutritracker/core/data/data_source/config_data_source.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/data_source/user_data_source.dart';
import 'package:opennutritracker/core/data/dbo/calories_profile_dbo.dart';
import 'package:opennutritracker/core/data/dbo/config_dbo.dart';
import 'package:opennutritracker/core/data/dbo/fasting_session_dbo.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/user_dbo.dart';
import 'package:opennutritracker/core/data/dbo/user_gender_dbo.dart';
import 'package:opennutritracker/core/data/dbo/user_pal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/user_weight_goal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/water_intake_dbo.dart';
import 'package:opennutritracker/core/data/repository/water_intake_repository.dart';
import 'package:opennutritracker/features/fasting/data/data_source/fasting_data_source.dart';
import 'package:opennutritracker/features/settings/domain/export_import_failure.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/backup/profiles_backup.dart';

/// What the JSON backup leaves out and the fork adds (phase 2, seam S21):
/// the water log, fasting sessions, saved custom meals, the adaptive
/// target's switches and check-ins, the profile, the app settings, and
/// every other profile ([ProfilesBackup]).
///
/// Ported from theoleuthardt's `PersonalBackupExtras` (GPL-3.0, their #93,
/// #94, #95, #97). Every file is optional on restore, so upstream's zips and
/// older ones still import.
class BackupExtras {
  static const waterFileName = 'water_intake.json';
  static const fastingFileName = 'fasting_sessions.json';
  static const customMealsFileName = 'custom_meals.json';
  static const adaptiveFileName = 'fork_adaptive.json';
  static const profileFileName = 'user_profile.json';
  static const appSettingsFileName = 'app_settings.json';

  /// The `ConfigDBO` keys `app_settings.json` carries: the device-wide
  /// preferences. Left out on purpose: the legal and consent flags (a restore
  /// must not accept a policy for the user), the demo flag, the goals (in
  /// `goal_settings.json`), the health import's per-device state, the day
  /// boundary (it keys the tracked days), and the reminder switch, which on
  /// a new phone would read on without the reminder being scheduled.
  static const appSettingKeys = [
    'selectedAppTheme',
    'usesImperialUnits',
    'usesImperialFoodUnits',
    'usesImperialHeightUnits',
    'bodyWeightUnitIndex',
    'usesKilojoules',
    'selectedLocale',
    'showActivityTracking',
    'showMealMacros',
    'showMicronutrients',
    'notificationHour',
    'notificationMinute',
    'customMealFormMode',
    'nutrientPanelVisibility',
    'diarySortPreferences',
    'fastingWarningAcknowledged',
    'useMaterialYou',
    'accentColor',
    'scannerPortraitLock',
    'foodSourceToggles',
    'defaultToRawFoodUnits',
  ];

  final WaterIntakeRepository _water;
  final FastingDataSource _fasting;
  final CustomMealDataSource _customMeals;
  final AdaptiveStore Function() _adaptive;

  /// Null leaves the profile, and the app settings, out of the backup.
  final UserDataSource? _user;
  final ConfigDataSource? _config;

  /// The other profiles' folders; null in a folder's own extras.
  final ProfilesBackup? _profiles;

  BackupExtras(
    this._water,
    this._fasting,
    this._customMeals, {
    AdaptiveStore Function()? adaptive,
    UserDataSource? user,
    ConfigDataSource? config,
    ProfilesBackup? profiles,
  }) : _adaptive = adaptive ?? AdaptiveStore.new,
       _user = user,
       _config = config,
       _profiles = profiles;

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
      ...settings.toJson(),
      'checkIns': [for (final c in await adaptive.history()) c.toJson()],
    });
    if (_user case final user? when await user.hasUserData()) {
      _addJson(archive, profileFileName, _userToJson(await user.getUserData()));
    }
    if (_config case final config?) {
      final settings = (await config.getConfig()).toJson();
      _addJson(archive, appSettingsFileName, {
        for (final key in appSettingKeys)
          if (settings[key] != null) key: settings[key],
      });
    }
    await _profiles?.addTo(archive);
  }

  /// Whether [archive] holds a profile, so a restore can stand in for
  /// onboarding.
  static bool hasProfile(Archive archive) =>
      archive.findFile(profileFileName) != null;

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
        settings: AdaptiveSettings.fromJson(map),
        checkIns: [
          for (final c in map['checkIns'] as List) CheckInRecord.fromJson(c),
        ],
      );
    });
    final profile = _decode(
      archive,
      profileFileName,
      (json) => _userFromJson(json as Map<String, dynamic>),
    );
    final settings = _decode(archive, appSettingsFileName, (json) {
      final map = json as Map<String, dynamic>;
      final picked = {
        for (final key in appSettingKeys)
          if (map.containsKey(key)) key: map[key],
      };
      // Throws here, before any write, on a value of the wrong type.
      ConfigDBO.fromJson({...ConfigDBO.empty().toJson(), ...picked});
      return picked;
    });
    final otherProfiles = _profiles?.prepareRestore(archive);

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
      if (profile != null) await _user?.saveUserData(profile);
      if ((_config, settings) case (final config?, final settings?)) {
        final current = (await config.getConfig()).toJson();
        await config.addConfig(ConfigDBO.fromJson({...current, ...settings}));
      }
      await otherProfiles?.call();
    };
  }

  static Map<String, Object?> _userToJson(UserDBO user) => {
    'birthday': user.birthday.toIso8601String(),
    'heightCM': user.heightCM,
    'weightKG': user.weightKG,
    'gender': user.gender.name,
    'goal': user.goal.name,
    'pal': user.pal.name,
    'weeklyWeightGoalKg': user.weeklyWeightGoalKg,
    'caloriesProfile': user.caloriesProfile?.name,
    'targetWeightKg': user.targetWeightKg,
    'caloriesTaperEnabled': user.caloriesTaperEnabled,
  };

  static UserDBO _userFromJson(Map<String, dynamic> json) {
    final caloriesProfile = json['caloriesProfile'] as String?;
    return UserDBO(
      birthday: DateTime.parse(json['birthday'] as String),
      heightCM: (json['heightCM'] as num).toDouble(),
      weightKG: (json['weightKG'] as num).toDouble(),
      gender: UserGenderDBO.values.byName(json['gender'] as String),
      goal: UserWeightGoalDBO.values.byName(json['goal'] as String),
      pal: UserPALDBO.values.byName(json['pal'] as String),
      weeklyWeightGoalKg: (json['weeklyWeightGoalKg'] as num?)?.toDouble(),
      caloriesProfile: caloriesProfile == null
          ? null
          : CaloriesProfileDBO.values.byName(caloriesProfile),
      targetWeightKg: (json['targetWeightKg'] as num?)?.toDouble(),
      caloriesTaperEnabled: json['caloriesTaperEnabled'] as bool? ?? false,
    );
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
      () => parse(
        // A number too large for a double (1e400) is refused, as upstream's
        // import does: stored, it would make the next export throw.
        jsonDecode(
          utf8.decode(file.content as List<int>),
          reviver: (key, value) => value is double && !value.isFinite
              ? throw FormatException('Not a finite number', '$key')
              : value,
        ),
      ),
    );
  }
}
