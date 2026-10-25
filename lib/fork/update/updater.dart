import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// The fork's releases (D16): fork/tools/release-apk.sh publishes each one
/// there, tagged `openbite-v<version>`, with its APK and the APK's SHA-256.
const releasesRepo = 'lodepav/OpenNutriTracker';
const releasesPage = 'https://github.com/$releasesRepo/releases/latest';
const _latestUrl = 'https://api.github.com/repos/$releasesRepo/releases/latest';
const _tagPrefix = 'openbite-v';

/// The app id of the build that checks: the full flavour. The develop one
/// (`.develop`) installs beside it and never offers it.
const _releaseAppId = 'io.github.lodepav.openbite';

/// What the latest release offers the installed version.
class UpdateInfo {
  final bool hasUpdate;
  final String latestVersion;
  final String? apkUrl;
  final String? hashUrl;

  /// False for a build that never asks (debug, profile, develop).
  final bool checked;

  const UpdateInfo({
    required this.hasUpdate,
    required this.latestVersion,
    this.apkUrl,
    this.hashUrl,
    this.checked = true,
  });

  const UpdateInfo.none(String version, {bool checked = true})
    : this(hasUpdate: false, latestVersion: version, checked: checked);
}

/// 1 when [a] is newer than [b], -1 when older, 0 when the same. Build
/// metadata ("1.2.3+4") plays no part, as semver says.
int compareSemver(String a, String b) {
  List<int> parts(String v) => [
    for (final p
        in v.replaceFirst(RegExp('^v'), '').split('+').first.split('.'))
      int.tryParse(p) ?? 0,
  ];
  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < 3; i++) {
    final diff = (i < pa.length ? pa[i] : 0) - (i < pb.length ? pb[i] : 0);
    if (diff != 0) return diff.sign;
  }
  return 0;
}

/// The version an OpenBite tag names, or '' for any other tag: upstream's
/// `v` tags share the repository, and a release made from one would offer
/// upstream's higher number as an update.
String tagVersion(String? tag) => tag != null && tag.startsWith(_tagPrefix)
    ? tag.substring(_tagPrefix.length)
    : '';

/// The release's APK and the checksum named after it, never just the first
/// `.sha256` in the list.
({String? apk, String? hash}) pickApk(List<Object?> assets) {
  final named = {
    for (final a in assets)
      if (a is Map) '${a['name']}': a['browser_download_url'] as String?,
  };
  final apk = named.keys
      .where((n) => n.toLowerCase().endsWith('.apk'))
      .firstOrNull;
  return (apk: named[apk], hash: apk == null ? null : named['$apk.sha256']);
}

/// The first word of a `sha256sum` line, when it is 64 hex characters.
String? parseChecksum(String text) {
  final hex = text.trim().split(RegExp(r'\s')).first.toLowerCase();
  return RegExp(r'^[0-9a-f]{64}$').hasMatch(hex) ? hex : null;
}

/// The in-app updater (D16), after openGym-Hevier's `lib/update.js`: asks
/// GitHub for the fork's latest release, once per app session, downloads its
/// APK into the cache directory and has `UpdateInstallChannel.kt` (S76) check
/// it against the release's SHA-256 before Android's installer opens. The
/// releases API is public: no token, 60 requests an hour per address.
class Updater {
  static final instance = Updater();
  static const _channel = MethodChannel('openbite/update_install');

  final http.Client _client;
  final Future<PackageInfo> Function() _package;
  final Future<Directory> Function() _cacheDir;
  final bool _release;
  Future<UpdateInfo>? _cached;

  Updater({
    http.Client? client,
    Future<PackageInfo> Function()? package,
    Future<Directory> Function()? cacheDir,
    bool release = kReleaseMode,
  }) : _client = client ?? http.Client(),
       _package = package ?? PackageInfo.fromPlatform,
       _cacheDir = cacheDir ?? getTemporaryDirectory,
       _release = release;

  /// The latest release against the installed version. The answer is kept
  /// for the session; a failure is not, and is thrown.
  Future<UpdateInfo> check() =>
      _cached ??= _fetch().catchError((Object e, StackTrace s) {
        _cached = null;
        Error.throwWithStackTrace(e, s);
      });

  /// Asks GitHub again, as when the user taps Settings' Updates row.
  Future<UpdateInfo> recheck() {
    _cached = null;
    return check();
  }

  Future<UpdateInfo> _fetch() async {
    final package = await _package();
    final installed = package.version;
    // A debug, profile or develop build never checks: a release would
    // install beside it, or fail on its other key.
    if (!_release || package.packageName != _releaseAppId) {
      return UpdateInfo.none(installed, checked: false);
    }
    final res = await _client.get(
      Uri.parse(_latestUrl),
      headers: {'Accept': 'application/vnd.github+json'},
    );
    // No release published yet.
    if (res.statusCode == 404) return UpdateInfo.none(installed);
    if (res.statusCode != 200) {
      throw HttpException('GitHub API ${res.statusCode}');
    }
    final latest = jsonDecode(res.body) as Map<String, Object?>;
    final version = tagVersion(latest['tag_name'] as String?);
    if (version.isEmpty) return UpdateInfo.none(installed);
    final picked = pickApk(latest['assets'] as List<Object?>? ?? const []);
    return UpdateInfo(
      hasUpdate: compareSemver(version, installed) > 0,
      latestVersion: version,
      apkUrl: picked.apk,
      hashUrl: picked.hash,
    );
  }

  /// The release's published SHA-256 of its APK, or null.
  Future<String?> checksum(String? hashUrl) async {
    if (hashUrl == null) return null;
    final res = await _client.get(Uri.parse(hashUrl));
    return res.statusCode == 200 ? parseChecksum(res.body) : null;
  }

  /// Downloads [info]'s APK straight to disk, with [onProgress] (received
  /// bytes, and the total or null), and opens the installer. Refuses a
  /// release without a checksum; the Android side refuses a mismatch.
  Future<void> install(
    UpdateInfo info, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final hash = await checksum(info.hashUrl);
    if (info.apkUrl == null || hash == null) {
      throw const UpdateException('Checksum not available, so not installing');
    }
    // The provider shares only this folder of the cache (fork_update_paths).
    const name = 'openbite-update/openbite.apk';
    final file = File('${(await _cacheDir()).path}/$name');
    await file.parent.create(recursive: true);
    final res = await _client.send(
      http.Request('GET', Uri.parse(info.apkUrl!)),
    );
    if (res.statusCode != 200) {
      throw UpdateException('Download failed (${res.statusCode})');
    }
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, res.contentLength);
      }
    } finally {
      await sink.close();
    }
    try {
      await _channel.invokeMethod<void>('install', {
        'fileName': name,
        'sha256': hash,
      });
    } on PlatformException catch (e) {
      throw UpdateException(switch (e.code) {
        'mismatch' => 'The download does not match its checksum',
        'missing' => 'The download is gone',
        _ => 'Could not open the installer',
      });
    }
  }
}

class UpdateException implements Exception {
  final String message;

  const UpdateException(this.message);

  @override
  String toString() => message;
}
