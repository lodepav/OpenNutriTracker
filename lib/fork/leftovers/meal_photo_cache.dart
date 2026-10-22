import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:path_provider/path_provider.dart';

/// Keeps the photo a meal was logged from for 24 hours, so a photo of the
/// leftovers can be read against it (D14). App-private support storage,
/// outside the documents directory the export reads, and Android backup is
/// off for the whole app. Off by a setting for anyone who wants no photo
/// kept; turning it off deletes what is kept.
class MealPhotoCache {
  static const keepFor = Duration(hours: 24);
  static const _flagsBox = 'fork_flags';
  static const _flag = 'keepMealPhotos';

  static const _extensions = {'image/webp': 'webp', 'image/jpeg': 'jpg'};

  final Future<Directory> Function() _dir;
  final Future<Box<bool>> Function() _flags;
  final DateTime Function() _now;

  MealPhotoCache({
    Future<Directory> Function()? dir,
    Future<Box<bool>> Function()? flags,
    DateTime Function()? now,
  }) : _dir = dir ?? _supportDir,
       _flags = flags ?? (() => Hive.openBox<bool>(_flagsBox)),
       _now = now ?? DateTime.now;

  static Future<Directory> _supportDir() async => Directory(
    '${(await getApplicationSupportDirectory()).path}/fork_meal_photos',
  );

  Future<bool> get enabled async =>
      (await _flags()).get(_flag, defaultValue: true)!;

  /// [enabled] for the photo sheet, false when the setting cannot be read:
  /// then [save] cannot read it either, so no copy is kept.
  Future<bool> get keepsPhotos async {
    try {
      return await enabled;
    } catch (_) {
      return false;
    }
  }

  Future<void> setEnabled(bool enabled) async {
    await (await _flags()).put(_flag, enabled);
    if (!enabled) await _delete((_) => true);
  }

  /// Saves [photo] and returns its path, or null when keeping is off or the
  /// format is not one the encoder makes. The name is the time it was
  /// kept, which is all its age is read from.
  Future<String?> save(MealPhoto photo) async {
    final extension = _extensions[photo.mediaType];
    if (extension == null || !await enabled) return null;
    final dir = await _dir();
    await dir.create(recursive: true);
    final file = File(
      '${dir.path}/${_now().millisecondsSinceEpoch}.$extension',
    );
    await file.writeAsBytes(photo.bytes);
    return file.path;
  }

  /// The photo at [path] while it is under 24 hours old.
  Future<MealPhoto?> read(String? path) async {
    if (path == null || _isStale(path)) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final extension = path.split('.').last;
    final mediaType = _extensions.entries
        .where((e) => e.value == extension)
        .firstOrNull
        ?.key;
    if (mediaType == null) return null;
    return MealPhoto(bytes: await file.readAsBytes(), mediaType: mediaType);
  }

  /// Deletes every photo over 24 hours old. Run at start-up.
  Future<void> prune() => _delete(_isStale);

  bool _isStale(String path) {
    final name = path.split('/').last.split('.').first;
    final keptAt = int.tryParse(name);
    if (keptAt == null) return true;
    return _now().difference(DateTime.fromMillisecondsSinceEpoch(keptAt)) >=
        keepFor;
  }

  Future<void> _delete(bool Function(String path) which) async {
    final dir = await _dir();
    if (!await dir.exists()) return;
    await for (final file in dir.list()) {
      if (file is File && which(file.path)) await file.delete();
    }
  }
}

/// Seam S8: replaces upstream's "keeps no copy" sentence in the photo
/// sheet while photos are kept.
const keptPhotoDisclosure =
    'OpenNutriTracker keeps a copy on this phone for 24 hours, to compare '
    'with a photo of the leftovers (Settings, Privacy turns this off). It is '
    'never included in your exports.';

/// Seam S11: the setting, in the privacy dialog beside crash reports. It
/// saves as it is switched, since it only ever deletes.
class KeepMealPhotosSwitch extends StatefulWidget {
  final MealPhotoCache? cache;

  const KeepMealPhotosSwitch({super.key, this.cache});

  @override
  State<KeepMealPhotosSwitch> createState() => _KeepMealPhotosSwitchState();
}

class _KeepMealPhotosSwitchState extends State<KeepMealPhotosSwitch> {
  late final _cache = widget.cache ?? MealPhotoCache();
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    _cache.enabled.then((enabled) {
      if (mounted) setState(() => _enabled = enabled);
    });
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: const Text('Keep meal photos for 24 hours'),
    subtitle: const Text(
      'Lets a photo of the leftovers be compared with the meal. '
      'Kept on this phone only, never backed up.',
    ),
    value: _enabled ?? false,
    onChanged: _enabled == null
        ? null
        : (enabled) async {
            setState(() => _enabled = enabled);
            await _cache.setEnabled(enabled);
          },
  );
}
