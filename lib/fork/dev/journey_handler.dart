// The journey check's entry point is a debug build only, so it may use the
// test packages: flutter_driver and flutter_test are dev dependencies, the
// picker interfaces come with image_picker and file_picker.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_driver/flutter_driver.dart' show SerializableFinder;
import 'package:flutter_test/flutter_test.dart'
    show ChainedFinder, Finder, Plurality, find;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:opennutritracker/core/data/data_source/remote_search_cache_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/data/repository/tracked_day_repository.dart';
import 'package:opennutritracker/core/data/repository/weight_log_repository.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/usecase/create_profile_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/switch_profile_usecase.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/demo/demo_seeder.dart';
import 'package:opennutritracker/core/utils/extensions.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/onboarding/presentation/bloc/onboarding_bloc.dart';
import 'package:opennutritracker/features/profile/presentation/utils/profile_switch_coordinator.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/backup/auto_backup.dart';
import 'package:opennutritracker/fork/demo/demo_profile.dart';
import 'package:opennutritracker/fork/dev/fake_ai.dart';
import 'package:opennutritracker/fork/dev/fake_health.dart';
import 'package:opennutritracker/fork/backup/profile_wipe.dart';
import 'package:opennutritracker/fork/health/weight_import.dart';
import 'package:opennutritracker/fork/off/off_contribution.dart';
import 'package:path_provider/path_provider.dart';

/// The hosts the offline guard refused this run, for `{"cmd":"network"}`.
final journeyBlocked = <String>{};

/// No connection leaves the app during a journey: Open Food Facts, the
/// hosted backend and images fail as offline would, so search reads the
/// bundled tables only (S1) and a run does not depend on what a server
/// holds that day. The fake AI answers before a request gets here.
class JourneyOffline extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..connectionFactory = (uri, proxyHost, proxyPort) {
          journeyBlocked.add(uri.host);
          return Future.error(
            SocketException('journey check: offline (${uri.host})'),
          );
        };
}

/// A Semantics identifier (the ids ux-drive.sh taps), or a text, tooltip
/// or scrollable matched by a pattern; `index` picks one of several.
class JourneyFind extends SerializableFinder {
  final Map<String, String> params;

  const JourneyFind(this.params);

  @override
  String get finderType => 'Journey';

  @override
  Map<String, String> serialize() => super.serialize()..addAll(params);
}

class JourneyFinder extends FinderExtension {
  @override
  String get finderType => 'Journey';

  @override
  SerializableFinder deserialize(
    Map<String, String> params,
    DeserializeFinderFactory finderFactory,
  ) => JourneyFind({
    for (final k in ['by', 'value', 'index', 'any']) k: ?params[k],
  });

  @override
  Finder createFinder(
    SerializableFinder finder,
    CreateFinderFactory finderFactory,
  ) {
    final p = (finder as JourneyFind).params;
    final value = p['value'] ?? '';
    final pattern = RegExp(value);
    final found = switch (p['by']) {
      'id' => find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.identifier == value,
        description: 'Semantics identifier "$value"',
      ),
      'text' => find.byElementPredicate(
        (e) => switch (e.widget) {
          Text(:final data?) => pattern.hasMatch(data),
          Text(:final textSpan?) => pattern.hasMatch(textSpan.toPlainText()),
          // a Text's own RichText would match a second time
          RichText(:final text) =>
            !_builtByText(e) && pattern.hasMatch(text.toPlainText()),
          _ => false,
        },
        description: 'text /$value/',
      ),
      'tooltip' => find.byWidgetPredicate(
        (w) => w is Tooltip && pattern.hasMatch(w.message ?? ''),
        description: 'tooltip /$value/',
      ),
      // the page's own list, or with value "horizontal" a row of chips
      'scrollable' => find.byWidgetPredicate(
        (w) =>
            w is Scrollable &&
            axisDirectionToAxis(w.axisDirection) ==
                (value == 'horizontal' ? Axis.horizontal : Axis.vertical),
        description:
            '${value == 'horizontal' ? 'horizontal' : 'vertical'} '
            'scrollable',
      ),
      final by => throw ArgumentError('no finder by $by'),
    };
    // only what is on screen: a route below or a list row out of sight is
    // not what the user sees, and tap needs one match
    // "any" also takes one built out of view, for scrollIntoView to bring in
    final seen = p['any'] == '1' ? found : found.hitTestable();
    return _Nth(seen, int.tryParse(p['index'] ?? '') ?? 0);
  }
}

bool _builtByText(Element e) {
  var depth = 0;
  var byText = false;
  e.visitAncestorElements((a) {
    byText = a.widget is Text;
    return !byText && ++depth < 4;
  });
  return byText;
}

/// The [n]th match, or none while there are fewer, so waitFor keeps
/// waiting where Finder.at would throw.
class _Nth extends ChainedFinder {
  final int n;

  _Nth(super.parent, this.n);

  @override
  String get description => '${parent.describeMatch(Plurality.many)} #$n';

  @override
  Iterable<Element> filter(Iterable<Element> parentCandidates) =>
      parentCandidates.skip(n).take(1);
}

/// The camera and the gallery give one of the bundled meal photos: the
/// emulator has neither a camera worth reading nor photos of its own.
class JourneyImagePicker extends ImagePickerPlatform {
  static const photo = 'assets/demo/meals/1548807371-30dc1bbe6cb5.jpg';

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    final bytes = await rootBundle.load(photo);
    final dir = await getTemporaryDirectory();
    // in the cache, which the app clears after encoding (MealPhotoEncoder)
    final file = File(
      '${dir.path}/journey-${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(bytes.buffer.asUint8List());
    return XFile(file.path);
  }
}

final class _PickedFile extends PlatformFile {
  final File _file;

  _PickedFile(String path) : _file = File(path);

  @override
  String get name => _file.uri.pathSegments.last;

  @override
  Uri get uri => _file.uri;

  @override
  XFile get xFile => XFile(_file.path);

  @override
  int? lengthSync() => _file.lengthSync();

  @override
  Future<int?> length() => _file.length();

  @override
  Future<Uint8List> readAsBytes() => _file.readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() =>
      _file.openRead().map(Uint8List.fromList);
}

/// The file picker answers with [path], as if the user had picked it.
class _OnePick extends FilePickerPlatform {
  final String path;

  _OnePick(this.path);

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => [_PickedFile(path)];
}

/// `requestData` commands from fork/tools/journey-check.mjs, as JSON:
/// {"ok": true, ...} or {"ok": false, "error": "..."}.
Future<String> journeyHandler(String? message) async {
  try {
    final cmd = jsonDecode(message ?? '{}') as Map<String, dynamic>;
    final out = switch (cmd['cmd']) {
      'hello' => {'journey': true},
      'state' => await _state(DateTime.parse(cmd['date'] as String)),
      'network' => await _network(),
      'importMacroFactor' => _armPicker(cmd['path'] as String),
      'weightImportOn' => await _weightImportOn(),
      'weightImportNow' => await _weightImportNow(),
      'openBoxes' => await _openBoxes(),
      'seedDemo' => await _seedDemo(),
      'ownerProfile' => await _ownerProfile(cmd['name'] as String),
      'cacheProduct' => await _cacheProduct(cmd),
      'checkInDue' => await _checkInDue(),
      final other => throw ArgumentError('unknown cmd $other'),
    };
    return jsonEncode({'ok': true, ...out});
  } catch (error) {
    return jsonEncode({'ok': false, 'error': '$error'});
  }
}

double _r(num? v, [int places = 1]) =>
    double.parse((v ?? 0).toStringAsFixed(places));

Map<String, Object?> _entry(IntakeEntity i) {
  final n = i.meal.nutriments;
  return {
    'meal': i.type.name,
    'name': i.meal.name,
    'amount': _r(i.amount, 2),
    'unit': i.unit,
    'kcal': _r(i.totalKcal),
    'protein': _r(i.totalProteinsGram),
    'carbs': _r(i.totalCarbsGram),
    'fat': _r(i.totalFatsGram),
    'per100': {
      'kcal': n.energyKcal100,
      'protein': n.proteins100,
      'carbs': n.carbohydrates100,
      'fat': n.fat100,
    },
    'source': i.meal.source.name,
  };
}

/// That day's entries as saved, its day row's totals (the Diary's), Home's
/// totals as it shows them (today only), its weigh-in, and the check-in's
/// numbers with the history's length and what Home adds to the target.
Future<Map<String, Object?>> _state(DateTime day) async {
  final config = await locator<GetConfigUsecase>().getConfig();
  final intakes = <IntakeEntity>[];
  for (final type in IntakeTypeEntity.values) {
    intakes.addAll(
      await locator<IntakeRepository>().getIntakeByDateAndType(
        type,
        day,
        dayStartOffsetHours: config.dayStartOffsetHours,
        dayStartOffsetMinutes: config.dayStartOffsetMinutes,
      ),
    );
  }
  intakes.sort((a, b) => a.dateTime.compareTo(b.dateTime));

  Map<String, Object?>? shown;
  final home = locator<HomeBloc>();
  final loaded = home.stream
      .firstWhere((s) => s is HomeLoadedState)
      .timeout(const Duration(seconds: 8));
  home.add(const LoadItemsEvent());
  final s = await loaded as HomeLoadedState;
  if (DateUtils.isSameDay(home.currentDay, day)) {
    shown = {
      'goalKcal': s.totalKcalDaily.round(),
      'eatenKcal': s.totalKcalSupplied.round(),
      'leftKcal': s.totalKcalLeft.round(),
      'protein': s.totalProteinsIntake.round(),
      'carbs': s.totalCarbsIntake.round(),
      'fat': s.totalFatsIntake.round(),
    };
  }

  final row = await locator<TrackedDayRepository>().getTrackedDay(day);
  final tracked = row == null
      ? null
      : {
          'kcal': _r(row.caloriesTracked),
          'protein': _r(row.proteinTracked),
          'carbs': _r(row.carbsTracked),
          'fat': _r(row.fatTracked),
        };

  Map<String, Object?>? weight;
  if (await locator<WeightLogRepository>().getEntry(day) case final w?) {
    final db = locator<HiveDBProvider>();
    final suffix = db.profileBox.get(db.activeProfileId)?.boxSuffix ?? '';
    final box = await db.openScopedBox<dynamic>(WeightImport.boxName, suffix);
    final filed =
        (box.get('filed', defaultValue: {}) as Map)[day.toParsedDay()];
    final fromHealth =
        filed is Map && (filed['kg'] as num?)?.toDouble() == w.weightKg;
    weight = {'kg': _r(w.weightKg), 'source': fromHealth ? 'health' : 'typed'};
  }

  Map<String, Object?>? adaptive;
  try {
    final service = AdaptiveService.fromLocator();
    final c = await service.checkIn();
    final last = await service.lastCheckIn();
    final goal = await forkKcalGoal(DateUtils.dateOnly(day));
    adaptive = {
      'due': await service.checkInDue(),
      'expenditureKcal': c.expenditureKcal.round(),
      'proposedTargetKcal': c.proposedTargetKcal.round(),
      'averageIntakeKcal': c.averageIntakeKcal?.round(),
      'trendKg': c.trendKg == null ? null : _r(c.trendKg),
      'weekChangeKg': c.weekChangeKg == null ? null : _r(c.weekChangeKg, 2),
      'loggedDays': c.loggedDays,
      'weighIns': c.weighIns,
      'checkIns': (await service.checkIns()).length,
      // what Home's goal holds besides the accepted target (seam S12)
      'goalOffsetKcal': goal.weekdayOffsetKcal.round(),
      'goalActivityKcal': goal.activityKcal.round(),
      'lastCheckIn': last == null
          ? null
          : {
              'daysAgo': DateUtils.dateOnly(
                day,
              ).difference(DateUtils.dateOnly(last.date)).inDays,
              'acceptedKcal': last.acceptedKcal.round(),
              'expenditureKcal': last.expenditureKcal.round(),
            },
    };
  } catch (error) {
    adaptive = {'error': '$error'};
  }

  return {
    'entries': intakes.map(_entry).toList(),
    'tracked': tracked,
    'shown': shown,
    'weight': weight,
    'adaptive': adaptive,
  };
}

/// Which paths off the device are on; the runner refuses a journey while
/// any is.
Future<Map<String, Object?>> _network() async {
  final on = <String>[];
  final ai = locator<AiCredentialStorage>();
  for (final provider in AiProvider.values) {
    final key = await ai.readApiKey(provider: provider);
    final endpoint = provider == AiProvider.ownServer
        ? await ai.readEndpoint(provider: provider)
        : null;
    // the fake answers Anthropic's endpoint itself
    final fake = provider == AiProvider.anthropic && forkFakeAi;
    if (!fake && (key != null || endpoint != null)) {
      on.add('an AI key for ${provider.name}');
    }
  }
  if ((await OffAccountStore().load()).isReady) {
    on.add('an Open Food Facts contribution account');
  }
  if (!forkFakeHealth && (await WeightImport.current?.isOn() ?? false)) {
    on.add('the weight import from Health Connect (not the fake one)');
  }
  final config = await locator<GetConfigUsecase>().getConfig();
  if (config.healthImportEnabled) {
    on.add('the workout import from Health Connect');
  }
  if (AutoBackup.state.value.folderUri case final _?) {
    on.add(
      'auto-backup to the folder ${AutoBackup.state.value.folderName ?? ''}',
    );
  }
  return {
    'on': on,
    'foodSourceToggles': config.foodSourceToggles,
    'blocked': journeyBlocked.toList()..sort(),
  };
}

Map<String, Object?> _armPicker(String path) {
  if (!File(path).existsSync()) throw ArgumentError('no file at $path');
  FilePickerPlatform.instance = _OnePick(path);
  return {'armed': path};
}

Future<Map<String, Object?>> _weightImportOn() async {
  final import = WeightImport.current;
  if (import == null) throw StateError('the weight import did not start');
  return {'filed': await import.turnOn()};
}

// The import waits out its interval after a run; a journey can't, so it runs it as that would.
Future<Map<String, Object?>> _weightImportNow() async {
  final import = WeightImport.current;
  if (import == null) throw StateError('the weight import did not start');
  return {'filed': await import.runNow()};
}

// Every box of the active profile on disk before the profile is saved: one the app opens first
// mid-journey would outlive the restore, holding that run's data.
Future<Map<String, Object?>> _openBoxes() async {
  final db = locator<HiveDBProvider>();
  final suffix = db.profileBox.get(db.activeProfileId)?.boxSuffix ?? '';
  for (final name in forkProfileBoxes) {
    await db.openScopedBox<dynamic>(name, suffix);
  }
  return {'opened': forkProfileBoxes.length};
}

Future<Map<String, Object?>> _seedDemo() async {
  await seedDemoData(DemoSeedOptions.dev);
  ProfileSwitchCoordinator.reloadTabBlocs();
  return {'seeded': true};
}

/// A new, empty profile through the app's own use cases (the profile
/// sheet's Add: CreateProfileUsecase, then the switch's
/// SwitchProfileUsecase and demo flag), made active and taken past
/// onboarding with the values its pages start on. The runner restarts the
/// app after, so every screen reads the new profile.
Future<Map<String, Object?>> _ownerProfile(String name) async {
  if (name.trim().isEmpty) throw ArgumentError('a profile needs a name');
  final profile = await locator<CreateProfileUsecase>().createProfile(
    name: name.trim(),
  );
  await locator<SwitchProfileUsecase>().switchProfile(profile);
  await syncDemoFlag();
  final onboarding = locator<OnboardingBloc>()..resetSelection();
  final pages = onboarding.userSelection;
  final now = DateTime.now();
  await onboarding.saveOnboardingData(
    UserEntity(
      birthday: DateTime(1990, 1, 1),
      heightCM: 180,
      weightKG: 80,
      gender: UserGenderEntity.male,
      goal: UserWeightGoalEntity.maintainWeight,
      pal: UserPALEntity.lowActive,
    ),
    pages.acceptDataCollection,
    pages.heightUsesImperial,
    pages.bodyWeightUnit,
    pages.foodUsesImperial,
    appTheme: pages.appTheme,
    foodSourceToggles: pages.foodSourceToggles,
    dailyReminderEnabled: false,
    reminderLocale: const Locale('en'),
    useMaterialYou: pages.useMaterialYou,
    accentColor: pages.accentColor,
  );
  // Onboarding files its weight as today's weigh-in. The owner's weigh-ins
  // come from the export and the scale: a made-up one would sit in the
  // trend, and as a typed row keep the scale's off today (WeightImport).
  await locator<WeightLogRepository>().deleteEntry(
    DateTime(now.year, now.month, now.day),
  );
  return {'profile': profile.id, 'name': profile.name};
}

/// An Open Food Facts product in the scan cache, as a scan made online
/// leaves it (full record, `detailed`), for the offline lookup of J5.
Future<Map<String, Object?>> _cacheProduct(Map<String, dynamic> cmd) async {
  final code = cmd['code'] as String;
  final per100 = (cmd['per100'] as Map).cast<String, num>();
  double v(String k) =>
      per100[k]?.toDouble() ?? (throw ArgumentError('per100 has no $k'));
  final product = MealEntity(
    code: code,
    name: cmd['name'] as String,
    url: null,
    mealQuantity: null,
    mealUnit: 'g',
    servingQuantity: null,
    servingUnit: null,
    servingSize: null,
    source: MealSourceEntity.off,
    detailed: true,
    nutriments: MealNutrimentsEntity(
      energyKcal100: v('kcal'),
      carbohydrates100: v('carbs'),
      fat100: v('fat'),
      proteins100: v('protein'),
      sugars100: null,
      saturatedFat100: null,
      fiber100: null,
    ),
  );
  await locator<RemoteSearchCacheDataSource>().cache(
    MealDBO.fromMealEntity(product),
  );
  return {'cached': code};
}

/// Makes the weekly check-in due the way the user would: the check-in day
/// (Settings, Expenditure and check-ins) set to today. Nothing when one is
/// due already, as on a profile without check-ins.
Future<Map<String, Object?>> _checkInDue() async {
  final service = AdaptiveService.fromLocator();
  var moved = false;
  if (!await service.checkInDue()) {
    await AdaptiveStore().save(
      AdaptiveStore.settings.value.copyWith(
        checkInWeekday: () => DateTime.now().weekday,
      ),
    );
    moved = true;
  }
  if (!await service.checkInDue()) {
    throw StateError(
      'no check-in is due on its day: is the target Adaptive, or was one '
      'accepted today?',
    );
  }
  return {'due': true, 'movedCheckInDay': moved};
}
