import 'dart:io';

import 'package:opennutritracker/core/utils/user_image_storage.dart';
import 'package:opennutritracker/fork/display/sized_file_image.dart'
    show evictPhoto;

/// A photo an editor picked or removed, held back until Save (H3): a pick
/// waits in a staged file beside the stored one, a removal only marks the
/// stored file. Save calls [commit]; an editor left without it calls
/// [discard], and the stored photo stays as it was.
// shortcut: a staged file outlives an app killed mid-edit, and nothing sweeps
// it (no code lists the image folders, so it is only space); sweep
// `*.staged*` at startup if that ever adds up.
class StagedPhoto {
  final UserImageKind kind;

  StagedPhoto(this.kind);

  String? _staged;
  String? _target;
  String? _removed;

  /// A pick or a removal that Save has not written yet.
  bool get pending => _staged != null || _removed != null;

  /// What the picker shows, given the path Save will write.
  String? shown(String? path) => _staged ?? path;

  /// Stages the photo at [sourcePath] for [ownerId] and returns the path
  /// Save writes on the row, the one the stored photo has.
  Future<String> pick({
    required String ownerId,
    required String sourcePath,
  }) async {
    // A new name each time: an Image goes on showing a path it has drawn.
    final staged = await UserImageStorage.importFrom(
      kind: kind,
      ownerId: '$ownerId.staged${DateTime.now().microsecondsSinceEpoch}',
      sourcePath: sourcePath,
    );
    await _dropStaged();
    _staged = staged;
    return _target = UserImageStorage.relativePathFor(kind, ownerId);
  }

  /// Drops a staged pick and marks [path], if any, to go on Save.
  Future<void> remove(String? path) async {
    await _dropStaged();
    if (path != null) _removed = path;
  }

  /// Writes what was staged: call it once the row is saved. False when the
  /// file work failed; the stored photo is then as it was.
  Future<bool> commit() async {
    try {
      final removed = _removed;
      final staged = _staged;
      final target = _target;
      // A pick after the removal replaces that file below.
      if (removed != null && (staged == null || removed != target)) {
        await UserImageStorage.delete(removed);
      }
      _removed = null;
      if (staged == null || target == null) return true;
      final to = await UserImageStorage.absolutePath(target);
      // A rename replaces the stored photo in one step, so a failure
      // leaves it whole.
      await File(await UserImageStorage.absolutePath(staged)).rename(to);
      _staged = null;
      // A demo photo's credit (UserImageStorage.writeCredit) is not this one's.
      final credit = File('$to.credit.json');
      if (await credit.exists()) await credit.delete();
      await evictPhoto(target);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Leaves the stored photo as it was.
  Future<void> discard() async {
    _removed = null;
    await _dropStaged();
  }

  Future<void> _dropStaged() async {
    final staged = _staged;
    if (staged == null) return;
    _staged = null;
    await UserImageStorage.delete(staged);
  }
}
