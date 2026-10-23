import 'package:flutter/services.dart';

/// Why the backup folder could not be used: `access_denied` (the grant is
/// gone, e.g. after a reinstall: pick the folder again), `io`, or
/// `unavailable` (no Android side, as in tests).
class BackupFolderException implements Exception {
  final String code;

  const BackupFolderException(this.code);

  @override
  String toString() => 'BackupFolderException($code)';
}

/// A folder picked with the system's folder picker, reached through
/// `BackupFolderChannel.kt` (seam S22). [uri] is its persisted grant.
class BackupFolder {
  static const _channel = MethodChannel('openbite/backup_folder');

  const BackupFolder();

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw BackupFolderException(e.code);
    } on MissingPluginException {
      throw const BackupFolderException('unavailable');
    }
  }

  /// The picked folder, or null when the user cancelled.
  Future<({String uri, String name})?> pick() async {
    final picked = await _call<Map<Object?, Object?>>('pick');
    if (picked == null) return null;
    return (uri: picked['uri'] as String, name: picked['name'] as String);
  }

  Future<List<String>> list(String uri) async =>
      (await _call<List<Object?>>('list', {'uri': uri}))?.cast<String>() ??
      const [];

  Future<void> write(String uri, String name, Uint8List bytes) =>
      _call<void>('write', {'uri': uri, 'name': name, 'bytes': bytes});

  Future<Uint8List?> read(String uri, String name) =>
      _call<Uint8List>('read', {'uri': uri, 'name': name});

  Future<void> delete(String uri, String name) =>
      _call<void>('delete', {'uri': uri, 'name': name});
}
