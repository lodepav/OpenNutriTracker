import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/utils/id_generator.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:path_provider/path_provider.dart';

/// One progress photo; the image is `progress_photos/<id>.jpg` in the
/// app's documents directory.
class ProgressPhoto {
  final String id;
  final DateTime date;

  const ProgressPhoto({required this.id, required this.date});

  /// Where the image sits, relative to the documents directory and in a
  /// backup zip.
  String get relativePath => '${PhotoStore.dir}/$id.jpg';

  Map<String, Object> toJson() => {'id': id, 'date': date.toIso8601String()};

  static ProgressPhoto fromJson(Map<dynamic, dynamic> json) {
    final id = json['id'] as String;
    // The id names a file, so nothing that could leave the folder.
    if (!RegExp(r'^[A-Za-z0-9-]+$').hasMatch(id)) {
      throw FormatException('Not a photo id', id);
    }
    return ProgressPhoto(id: id, date: DateTime.parse(json['date'] as String));
  }
}

/// Progress photos (MacroFactor's): the index in the fork's per-profile
/// box, the images on the device. Ids are unique, so every profile's
/// images share one folder. Oldest first.
class PhotoStore {
  static const dir = 'progress_photos';
  static const _key = 'progressPhotos';

  /// Bumped on every write, so the Trends card reloads.
  static final changes = ValueNotifier(0);

  final Future<Box<dynamic>> Function() _box;
  final Future<Directory> Function() _root;

  PhotoStore([
    Future<Box<dynamic>> Function()? box,
    Future<Directory> Function()? root,
  ]) : _box = box ?? AdaptiveStore.openActiveBox,
       _root = root ?? getApplicationDocumentsDirectory;

  Future<List<ProgressPhoto>> all() async => [
    for (final json in (await _box()).get(_key, defaultValue: []) as List)
      ProgressPhoto.fromJson(json as Map),
  ]..sort((a, b) => a.date.compareTo(b.date));

  Future<File> file(ProgressPhoto photo) async =>
      File('${(await _root()).path}/${photo.relativePath}');

  /// Saves [bytes] as a photo of [date].
  Future<ProgressPhoto> add(DateTime date, List<int> bytes) async {
    final photo = ProgressPhoto(
      id: IdGenerator.getUniqueID(),
      date: DateTime(date.year, date.month, date.day),
    );
    await writeImage(photo, bytes);
    await _write([...await all(), photo]);
    return photo;
  }

  Future<void> writeImage(ProgressPhoto photo, List<int> bytes) async {
    final target = await file(photo);
    await target.parent.create(recursive: true);
    await target.writeAsBytes(bytes, flush: true);
  }

  Future<void> remove(String id) async {
    final photos = await all();
    for (final p in photos) {
      if (p.id != id) continue;
      final image = await file(p);
      if (await image.exists()) await image.delete();
    }
    await _write([
      for (final p in photos)
        if (p.id != id) p,
    ]);
  }

  /// Adds [photos] from a backup, writing the [images] it carried; one
  /// with an id already here replaces it.
  Future<void> merge(
    List<ProgressPhoto> photos,
    Map<String, List<int>> images,
  ) async {
    for (final p in photos) {
      if (images[p.id] case final bytes?) await writeImage(p, bytes);
    }
    final byId = {
      for (final p in [...await all(), ...photos]) p.id: p,
    };
    await _write(byId.values.toList());
  }

  Future<void> _write(List<ProgressPhoto> photos) async {
    await (await _box()).put(_key, [for (final p in photos) p.toJson()]);
    changes.value++;
  }
}
