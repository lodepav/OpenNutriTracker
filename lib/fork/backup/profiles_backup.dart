import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/data_source/config_data_source.dart';
import 'package:opennutritracker/core/data/data_source/custom_activity_template_data_source.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/data_source/favourite_meal_data_source.dart';
import 'package:opennutritracker/core/data/data_source/intake_data_source.dart';
import 'package:opennutritracker/core/data/data_source/profile_data_source.dart';
import 'package:opennutritracker/core/data/data_source/recipe_data_source.dart';
import 'package:opennutritracker/core/data/data_source/tracked_day_data_source.dart';
import 'package:opennutritracker/core/data/data_source/user_activity_data_source.dart';
import 'package:opennutritracker/core/data/data_source/user_activity_dbo.dart';
import 'package:opennutritracker/core/data/data_source/user_data_source.dart';
import 'package:opennutritracker/core/data/data_source/water_intake_data_source.dart';
import 'package:opennutritracker/core/data/data_source/weight_log_data_source.dart';
import 'package:opennutritracker/core/data/dbo/config_dbo.dart';
import 'package:opennutritracker/core/data/dbo/fasting_session_dbo.dart';
import 'package:opennutritracker/core/data/dbo/favourite_meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/intake_dbo.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/recipe_dbo.dart';
import 'package:opennutritracker/core/data/data_source/custom_activity_template_dbo.dart';
import 'package:opennutritracker/core/data/dbo/profile_dbo.dart';
import 'package:opennutritracker/core/data/dbo/tracked_day_dbo.dart';
import 'package:opennutritracker/core/data/dbo/user_dbo.dart';
import 'package:opennutritracker/core/data/dbo/water_intake_dbo.dart';
import 'package:opennutritracker/core/data/dbo/weight_log_dbo.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/data/repository/custom_activity_template_repository.dart';
import 'package:opennutritracker/core/data/repository/favourite_meal_repository.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/data/repository/recipe_repository.dart';
import 'package:opennutritracker/core/data/repository/tracked_day_repository.dart';
import 'package:opennutritracker/core/data/repository/user_activity_repository.dart';
import 'package:opennutritracker/core/data/repository/water_intake_repository.dart';
import 'package:opennutritracker/core/data/repository/weight_log_repository.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/tracked_day_reconciler.dart';
import 'package:opennutritracker/core/utils/user_image_storage.dart';
import 'package:opennutritracker/features/fasting/data/data_source/fasting_data_source.dart';
import 'package:opennutritracker/features/settings/domain/export_import_failure.dart';
import 'package:opennutritracker/features/settings/domain/tracked_day_boundary_record.dart';
import 'package:opennutritracker/features/settings/domain/usecase/export_data_usecase.dart';
import 'package:opennutritracker/features/settings/domain/usecase/import_data_usecase.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/backup/backup_extras.dart';

typedef OpenProfileBox =
    Future<Box<E>> Function<E>(String baseName, String boxSuffix);

/// Every profile in the JSON backup, not only the active one (seam S21,
/// theoleuthardt #96).
///
/// Ported after review from theoleuthardt `personal` (GPL-3.0): their
/// layout, so upstream and older builds still import the zip. The top level
/// stays the active profile's, as upstream writes it; `profiles.json` lists
/// every profile and names that one; each other profile has a folder
/// `profiles/<id>/` with its own files, written and read by upstream's
/// export and import running on that profile's boxes. Shared data (custom
/// meals, recipes, activity templates, app settings, photos) lives at the
/// top level only. Review: sound, and every folder is decoded before the
/// first write. Simpler here: no "replace everything" restore (a separate
/// feature), and a restore never renames the active profile.
class ProfilesBackup {
  static const profilesFileName = 'profiles.json';
  static const folderPrefix = 'profiles/';

  static const _activity = 'user_activity.json';
  static const _intake = 'user_intake.json';
  static const _trackedDay = 'user_tracked_day.json';
  static const _recipe = 'user_recipes.json';
  static const _weightLog = 'weight_log.json';
  static const _template = 'custom_activity_templates.json';
  static const _goalSettings = 'goal_settings.json';
  static const _favourites = 'user_favourites.json';

  /// The files of a profile's folder: what the backup holds per profile.
  static const profileFileNames = {
    _activity,
    _intake,
    _trackedDay,
    _weightLog,
    _goalSettings,
    _favourites,
    TrackedDayBoundaryRecord.jsonFileName,
    BackupExtras.waterFileName,
    BackupExtras.fastingFileName,
    BackupExtras.adaptiveFileName,
    BackupExtras.profileFileName,
  };

  final HiveDBProvider _db;
  final ProfileDataSource _profiles;

  /// Opens a profile's box: the app's encrypted one, or a plain one in
  /// tests.
  final OpenProfileBox _open;

  ProfilesBackup(this._db, {OpenProfileBox? openBox})
    : _profiles = ProfileDataSource(_db),
      _open = openBox ?? _db.openScopedBox;

  /// Writes `profiles.json` and a folder for every profile but the active
  /// one into [archive]. Runs inside the export's tracked-day lock.
  Future<void> addTo(Archive archive) async {
    final mainId = _db.activeProfileId;
    final profiles = _profiles.getAllProfiles();
    _addJson(archive, profilesFileName, {
      'mainProfileId': mainId,
      'profiles': [
        for (final p in profiles)
          {
            'id': p.id,
            'name': p.name,
            'createdAt': p.createdAt.toIso8601String(),
            'boxSuffix': p.boxSuffix,
          },
      ],
    });
    for (final profile in profiles) {
      if (profile.id == mainId) continue;
      await _inScope(profile, (scope, open) async {
        final folder = await _exporter(scope, profile, open).assembleArchive(
          format: ExportFormat.json,
          userActivityJsonFileName: _activity,
          userIntakeJsonFileName: _intake,
          trackedDayJsonFileName: _trackedDay,
          recipeJsonFileName: _recipe,
          weightLogJsonFileName: _weightLog,
          customActivityTemplateJsonFileName: _template,
          goalSettingsJsonFileName: _goalSettings,
          favouriteJsonFileName: _favourites,
        );
        for (final file in folder.files) {
          final bytes = file.content as List<int>;
          if (profileFileNames.contains(file.name)) {
            archive.addFile(
              ArchiveFile.bytes(
                '$folderPrefix${profile.id}/${file.name}',
                bytes,
              ),
            );
          } else if (_isPhoto(file.name) &&
              archive.findFile(file.name) == null) {
            archive.addFile(ArchiveFile.bytes(file.name, bytes));
          }
        }
      });
    }
  }

  /// Decodes `profiles.json` and checks every folder before anything is
  /// written, and returns the writes: each folder into the profile with its
  /// id, created when the device lacks it. Null for a zip without
  /// `profiles.json`. A backup whose other profiles include the active one
  /// is refused, since its top level would land in the wrong diary.
  Future<void> Function()? prepareRestore(Archive archive) {
    final file = archive.findFile(profilesFileName);
    if (file == null) return null;
    final (:mainId, :profiles) = _guard(
      'Could not parse $profilesFileName',
      () => _decodeProfiles(file),
    );
    final others = [
      for (final p in profiles)
        if (p.id != mainId) p,
    ];
    if (others.any((p) => p.id == _db.activeProfileId)) {
      throw ExportImportFailure(
        ExportImportFailureReason.unreadableOrWrongFormat,
        'The active profile is not the main profile of this backup; switch '
        'to the profile it was made from first',
      );
    }
    final folders = {for (final p in others) p.id: _folder(archive, p.id)};
    folders.forEach(_validate);

    return () async {
      for (final backup in others) {
        final local = await _ensureProfile(backup);
        await _inScope(local, (scope, open) async {
          await _importer(scope, local, open).importArchive(
            folders[backup.id]!,
            _activity,
            _intake,
            _trackedDay,
            _recipe,
            _weightLog,
            _template,
            goalSettingsJsonFileName: _goalSettings,
            favouriteJsonFileName: _favourites,
          );
        });
      }
    };
  }

  /// The device's profile for [backup]: the one with its id, or a new one
  /// under that id, keeping its box suffix unless it is empty (the device's
  /// first profile owns that) or taken.
  Future<ProfileDBO> _ensureProfile(ProfileDBO backup) async {
    final existing = _profiles.getProfile(backup.id);
    if (existing != null) return existing;
    final taken = {for (final p in _profiles.getAllProfiles()) p.boxSuffix};
    final created = ProfileDBO(
      id: backup.id,
      name: backup.name,
      createdAt: backup.createdAt,
      boxSuffix: backup.boxSuffix.isEmpty || taken.contains(backup.boxSuffix)
          ? backup.id.replaceAll('-', '')
          : backup.boxSuffix,
    );
    await _profiles.saveProfile(created);
    return created;
  }

  /// Runs [action] on [profile]'s boxes, opened for it and closed after.
  Future<void> _inScope(
    ProfileDBO profile,
    Future<void> Function(HiveDBProvider scope, OpenProfileBox open) action,
  ) async {
    final opened = <Box<dynamic>>{};
    Future<Box<E>> open<E>(String name, String suffix) async {
      final box = await _open<E>(name, suffix);
      opened.add(box);
      return box;
    }

    try {
      final suffix = profile.boxSuffix;
      final scope = ProfileBoxScope(
        shared: _db,
        profileId: profile.id,
        config: await open<ConfigDBO>(HiveDBProvider.configBoxName, suffix),
        intake: await open<IntakeDBO>(HiveDBProvider.intakeBoxName, suffix),
        userActivity: await open<UserActivityDBO>(
          HiveDBProvider.userActivityBoxName,
          suffix,
        ),
        user: await open<UserDBO>(HiveDBProvider.userBoxName, suffix),
        trackedDay: await open<TrackedDayDBO>(
          HiveDBProvider.trackedDayBoxName,
          suffix,
        ),
        weightLog: await open<WeightLogDBO>(
          HiveDBProvider.weightLogBoxName,
          suffix,
        ),
        waterIntake: await open<WaterIntakeDBO>(
          HiveDBProvider.waterIntakeBoxName,
          suffix,
        ),
        fasting: await open<FastingSessionDBO>(
          HiveDBProvider.fastingBoxName,
          suffix,
        ),
        favouriteMeal: await open<FavouriteMealDBO>(
          HiveDBProvider.favouriteMealBoxName,
          suffix,
        ),
      );
      await action(scope, open);
    } finally {
      for (final box in opened) {
        if (box.isOpen) await box.close();
      }
    }
  }

  BackupExtras _extras(
    HiveDBProvider scope,
    ProfileDBO profile,
    OpenProfileBox open,
  ) => BackupExtras(
    WaterIntakeRepository(WaterIntakeDataSource(scope)),
    FastingDataSource(scope),
    CustomMealDataSource(scope),
    adaptive: () => AdaptiveStore.otherProfile(
      () => open<dynamic>(AdaptiveStore.boxName, profile.boxSuffix),
    ),
    user: UserDataSource(scope),
  );

  ExportDataUsecase _exporter(
    HiveDBProvider scope,
    ProfileDBO profile,
    OpenProfileBox open,
  ) => ExportDataUsecase(
    UserActivityRepository(UserActivityDataSource(scope)),
    IntakeRepository(IntakeDataSource(scope)),
    TrackedDayRepository(TrackedDayDataSource(scope)),
    RecipeRepository(RecipeDataSource(scope)),
    CustomMealDataSource(scope),
    WeightLogRepository(WeightLogDataSource(scope)),
    CustomActivityTemplateRepository(CustomActivityTemplateDataSource(scope)),
    ConfigRepository(ConfigDataSource(scope)),
    _favouriteRepository(scope),
    forkExtras: _extras(scope, profile, open),
  );

  ImportDataUsecase _importer(
    HiveDBProvider scope,
    ProfileDBO profile,
    OpenProfileBox open,
  ) {
    final config = ConfigDataSource(scope);
    return ImportDataUsecase(
      UserActivityRepository(UserActivityDataSource(scope)),
      IntakeRepository(IntakeDataSource(scope)),
      TrackedDayRepository(TrackedDayDataSource(scope)),
      RecipeRepository(RecipeDataSource(scope)),
      WeightLogRepository(WeightLogDataSource(scope)),
      CustomActivityTemplateRepository(CustomActivityTemplateDataSource(scope)),
      ConfigRepository(config),
      _favouriteRepository(scope),
      restoreTrackedDays:
          (
            write, {
            required importedDayKeys,
            required importedActivities,
            required keyedByOffsetMinutes,
          }) => restoreTrackedDays(
            scope,
            config,
            write: write,
            importedDayKeys: importedDayKeys,
            importedActivities: importedActivities,
            keyedByOffsetMinutes: keyedByOffsetMinutes,
          ),
      forkExtras: _extras(scope, profile, open),
    );
  }

  static FavouriteMealRepository _favouriteRepository(HiveDBProvider scope) =>
      FavouriteMealRepository(
        FavouriteMealDataSource(scope),
        CustomMealDataSource(scope),
        RecipeDataSource(scope),
      );

  static bool _isPhoto(String name) =>
      name.startsWith('${UserImageKind.meal.subdir}/') ||
      name.startsWith('${UserImageKind.recipe.subdir}/');

  static Archive _folder(Archive archive, String profileId) {
    final prefix = '$folderPrefix$profileId/';
    final folder = Archive();
    for (final file in archive.files) {
      if (!file.isFile || !file.name.startsWith(prefix)) continue;
      folder.addFile(
        ArchiveFile.bytes(
          file.name.substring(prefix.length),
          file.content as List<int>,
        ),
      );
    }
    return folder;
  }

  /// Decodes a folder's files as its import will, so a broken one is found
  /// before the first write.
  static void _validate(String profileId, Archive folder) =>
      _guard('Could not parse the folder of profile $profileId', () {
        List<Map<String, dynamic>> rows(String name, {bool required = false}) {
          final file = folder.findFile(name);
          if (file == null) {
            if (required) throw FormatException('Missing $name');
            return const [];
          }
          return (_decodeFinite(file) as List).cast<Map<String, dynamic>>();
        }

        rows(_activity, required: true).forEach(UserActivityDBO.fromJson);
        rows(_intake, required: true).forEach(IntakeDBO.fromJson);
        rows(_trackedDay, required: true).forEach(TrackedDayDBO.fromJson);
        rows(_weightLog).forEach(WeightLogDBO.fromJson);
        rows(BackupExtras.waterFileName).forEach(WaterIntakeDBO.fromJson);
      });

  static ({String? mainId, List<ProfileDBO> profiles}) _decodeProfiles(
    ArchiveFile file,
  ) {
    final json = _decodeFinite(file) as Map<String, dynamic>;
    return (
      mainId: json['mainProfileId'] as String?,
      profiles: [
        for (final row in (json['profiles'] as List).cast<Map>())
          ProfileDBO(
            id: row['id'] as String,
            name: row['name'] as String,
            createdAt: DateTime.parse(row['createdAt'] as String),
            boxSuffix: row['boxSuffix'] as String? ?? '',
          ),
      ],
    );
  }

  static T _guard<T>(String message, T Function() body) =>
      ExportImportFailure.guardSync(
        ExportImportFailureReason.unreadableOrWrongFormat,
        message,
        body,
      );

  static Object? _decodeFinite(ArchiveFile file) => jsonDecode(
    utf8.decode(file.content as List<int>),
    reviver: (key, value) {
      if (value is double && !value.isFinite) {
        throw FormatException('Not a finite number', '$key');
      }
      return value;
    },
  );

  static void _addJson(Archive archive, String name, Object json) =>
      archive.addFile(ArchiveFile.bytes(name, utf8.encode(jsonEncode(json))));
}

/// A [HiveDBProvider] handing out one profile's per-profile boxes and the
/// app's shared ones, so upstream's data sources run unchanged on a
/// profile that is not active. Unlike upstream's `ScopedHiveDBProvider`,
/// it carries every per-profile box.
class ProfileBoxScope extends HiveDBProvider {
  final HiveDBProvider _shared;
  final String _profileId;
  final Box<ConfigDBO> _config;
  final Box<IntakeDBO> _intake;
  final Box<UserActivityDBO> _userActivity;
  final Box<UserDBO> _user;
  final Box<TrackedDayDBO> _trackedDay;
  final Box<WeightLogDBO> _weightLog;
  final Box<WaterIntakeDBO> _waterIntake;
  final Box<FastingSessionDBO> _fasting;
  final Box<FavouriteMealDBO> _favouriteMeal;

  ProfileBoxScope({
    required HiveDBProvider shared,
    required String profileId,
    required Box<ConfigDBO> config,
    required Box<IntakeDBO> intake,
    required Box<UserActivityDBO> userActivity,
    required Box<UserDBO> user,
    required Box<TrackedDayDBO> trackedDay,
    required Box<WeightLogDBO> weightLog,
    required Box<WaterIntakeDBO> waterIntake,
    required Box<FastingSessionDBO> fasting,
    required Box<FavouriteMealDBO> favouriteMeal,
  }) : _shared = shared,
       _profileId = profileId,
       _config = config,
       _intake = intake,
       _userActivity = userActivity,
       _user = user,
       _trackedDay = trackedDay,
       _weightLog = weightLog,
       _waterIntake = waterIntake,
       _fasting = fasting,
       _favouriteMeal = favouriteMeal;

  @override
  String get activeProfileId => _profileId;
  @override
  Box<ConfigDBO> get configBox => _config;
  @override
  Box<IntakeDBO> get intakeBox => _intake;
  @override
  Box<UserActivityDBO> get userActivityBox => _userActivity;
  @override
  Box<UserDBO> get userBox => _user;
  @override
  Box<TrackedDayDBO> get trackedDayBox => _trackedDay;
  @override
  Box<WeightLogDBO> get weightLogBox => _weightLog;
  @override
  Box<WaterIntakeDBO> get waterIntakeBox => _waterIntake;
  @override
  Box<FastingSessionDBO> get fastingBox => _fasting;
  @override
  Box<FavouriteMealDBO> get favouriteMealBox => _favouriteMeal;

  @override
  Box<ConfigDBO> get appConfigBox => _shared.appConfigBox;
  @override
  Box<ProfileDBO> get profileBox => _shared.profileBox;
  @override
  Box<MealDBO> get customMealBox => _shared.customMealBox;
  @override
  Box<RecipeDBO> get recipeBox => _shared.recipeBox;
  @override
  Box<CustomActivityTemplateDBO> get customActivityTemplateBox =>
      _shared.customActivityTemplateBox;
  @override
  Box<MealDBO> get cachedOffMealBox => _shared.cachedOffMealBox;
  @override
  Box<int> get cachedOffMealTimestampsBox => _shared.cachedOffMealTimestampsBox;
}
