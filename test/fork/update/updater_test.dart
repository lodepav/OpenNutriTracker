// The in-app updater (D16): which release it offers, and how it installs it.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/fork/update/updater.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _hash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

PackageInfo _package({
  String version = '0.1.0',
  String id = 'io.github.lodepav.openbite',
}) => PackageInfo(
  appName: 'OpenBite',
  packageName: id,
  version: version,
  buildNumber: '100',
);

Map<String, Object?> _release(String tag) => {
  'tag_name': tag,
  'assets': [
    {
      'name': 'openbite-0.2.0.apk.sha256',
      'browser_download_url': 'h',
      'url': 'hApi',
    },
    {'name': 'openbite-0.2.0.apk', 'browser_download_url': 'a', 'url': 'aApi'},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('versions compare as semver, build metadata aside', () {
    expect(compareSemver('0.2.0', '0.1.9'), 1);
    expect(compareSemver('0.1.10', '0.1.9'), 1);
    expect(compareSemver('1.0.0', '1.0.0+4'), 0);
    expect(compareSemver('v0.1.0', '0.1.1'), -1);
  });

  test("only OpenBite's tags name a version; upstream's do not", () {
    expect(tagVersion('openbite-v0.2.0'), '0.2.0');
    expect(tagVersion('v2.6.0'), '');
    expect(tagVersion(null), '');
  });

  test("the checksum is the one named after the APK, and must be hex", () {
    expect(pickApk(_release('x')['assets'] as List<Object?>), (
      apk: 'a',
      hash: 'h',
      apkApi: 'aApi',
      hashApi: 'hApi',
    ));
    expect(
      pickApk([
        {'name': 'other.apk.sha256', 'browser_download_url': 'h'},
        {'name': 'openbite.apk', 'browser_download_url': 'a'},
      ]),
      (apk: 'a', hash: null, apkApi: null, hashApi: null),
    );
    expect(parseChecksum('$_hash  openbite-0.2.0.apk\n'), _hash);
    expect(parseChecksum('not a hash'), isNull);
  });

  group('check', () {
    test('offers a newer OpenBite release, once per session', () async {
      var asked = 0;
      final updater = Updater(
        release: true,
        package: () async => _package(),
        client: MockClient((req) async {
          asked++;
          expect(
            req.url.path,
            '/repos/lodepav/OpenNutriTracker/releases/latest',
          );
          return http.Response(jsonEncode(_release('openbite-v0.2.0')), 200);
        }),
      );
      final info = await updater.check();
      expect(info.hasUpdate, isTrue);
      expect(info.latestVersion, '0.2.0');
      expect((info.apkUrl, info.hashUrl), ('a', 'h'));
      expect((info.apkApiUrl, info.hashApiUrl), ('aApi', 'hApi'));
      await updater.check();
      expect(asked, 1);
      // Settings' row asks again when tapped.
      await updater.recheck();
      expect(asked, 2);
    });

    test(
      "no update: no release yet, an upstream tag, the same version",
      () async {
        Future<UpdateInfo> answer(http.Response res) => Updater(
          release: true,
          package: () async => _package(version: '0.2.0'),
          client: MockClient((_) async => res),
        ).check();
        expect((await answer(http.Response('', 404))).hasUpdate, isFalse);
        expect(
          (await answer(
            http.Response(jsonEncode(_release('v2.6.0')), 200),
          )).hasUpdate,
          isFalse,
        );
        expect(
          (await answer(
            http.Response(jsonEncode(_release('openbite-v0.2.0')), 200),
          )).hasUpdate,
          isFalse,
        );
      },
    );

    test('a debug or develop build never asks', () async {
      final never = MockClient((_) async => fail('asked GitHub'));
      expect(
        (await Updater(
          package: () async => _package(),
          client: never,
        ).check()).hasUpdate,
        isFalse,
      );
      expect(
        (await Updater(
          release: true,
          package: () async =>
              _package(id: 'io.github.lodepav.openbite.develop'),
          client: never,
        ).check()).hasUpdate,
        isFalse,
      );
      expect(
        (await Updater(
          package: () async => _package(),
          client: never,
        ).check()).checked,
        isFalse,
      );
    });

    test('a failure is thrown and not kept', () async {
      var fails = true;
      final updater = Updater(
        release: true,
        package: () async => _package(),
        client: MockClient(
          (_) async => fails
              ? http.Response('', 500)
              : http.Response(jsonEncode(_release('openbite-v0.2.0')), 200),
        ),
      );
      await expectLater(updater.check(), throwsA(isA<HttpException>()));
      fails = false;
      expect((await updater.check()).hasUpdate, isTrue);
    });
  });

  group('install', () {
    const channel = MethodChannel('openbite/update_install');
    late Directory cache;
    MethodCall? call;

    setUp(() async {
      cache = await Directory.systemTemp.createTemp('update');
      call = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (c) async {
            call = c;
            return null;
          });
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await cache.delete(recursive: true);
    });

    Updater updater(String checksum) => Updater(
      cacheDir: () async => cache,
      client: MockClient(
        (req) async => req.url.path == '/h'
            ? http.Response(checksum, 200)
            : http.Response.bytes([1, 2, 3], 200),
      ),
    );
    const info = UpdateInfo(
      hasUpdate: true,
      latestVersion: '0.2.0',
      apkUrl: 'https://x/a',
      hashUrl: 'https://x/h',
    );

    test('downloads into the shared cache folder and hands it over', () async {
      final seen = <(int, int?)>[];
      await updater(
        _hash,
      ).install(info, onProgress: (r, t) => seen.add((r, t)));
      expect(call?.method, 'install');
      expect(call?.arguments, {
        'fileName': 'openbite-update/openbite.apk',
        'sha256': _hash,
      });
      expect(
        File('${cache.path}/openbite-update/openbite.apk').readAsBytesSync(),
        [1, 2, 3],
      );
      expect(seen.last.$1, 3);
    });

    test('refuses a release without a checksum', () async {
      await expectLater(
        updater('nope').install(info),
        throwsA(isA<UpdateException>()),
      );
      expect(call, isNull);
    });

    // github.com's download link answered 504 on 2026-11-09 while the API's
    // asset link served the file.
    const withApi = UpdateInfo(
      hasUpdate: true,
      latestVersion: '0.2.0',
      apkUrl: 'https://x/a',
      hashUrl: 'https://x/h',
      apkApiUrl: 'https://api/a',
      hashApiUrl: 'https://api/h',
    );

    test('the checksum comes from the github.com link alone', () async {
      final asked = <String>[];
      final updater = Updater(
        client: MockClient((req) async {
          asked.add('${req.url}');
          return http.Response(_hash, 200);
        }),
      );
      expect(
        await updater.checksum(withApi.hashUrl, withApi.hashApiUrl),
        _hash,
      );
      expect(asked, ['https://x/h']);
    });

    test('a 504 from github.com falls back to the API link', () async {
      final asked = <(String, String?)>[];
      final updater = Updater(
        cacheDir: () async => cache,
        client: MockClient((req) async {
          asked.add(('${req.url}', req.headers['Accept']));
          return switch (req.url.host) {
            'x' => http.Response('', 504),
            _ when req.url.path == '/h' => http.Response(_hash, 200),
            _ => http.Response.bytes([4, 5], 200),
          };
        }),
      );
      await updater.install(withApi);
      expect(asked, [
        ('https://x/h', null),
        ('https://api/h', 'application/octet-stream'),
        ('https://x/a', null),
        ('https://api/a', 'application/octet-stream'),
      ]);
      expect(call?.arguments, {
        'fileName': 'openbite-update/openbite.apk',
        'sha256': _hash,
      });
      expect(
        File('${cache.path}/openbite-update/openbite.apk').readAsBytesSync(),
        [4, 5],
      );
    });

    test('a thrown request falls back too', () async {
      final updater = Updater(
        client: MockClient(
          (req) async => req.url.host == 'x'
              ? throw http.ClientException('reset')
              : http.Response(_hash, 200),
        ),
      );
      expect(
        await updater.checksum(withApi.hashUrl, withApi.hashApiUrl),
        _hash,
      );
    });

    test('both links failing gives no checksum and no install', () async {
      final updater = Updater(
        cacheDir: () async => cache,
        client: MockClient(
          (req) async => req.url.host == 'x'
              ? http.Response('', 504)
              : http.Response('not a hash', 200),
        ),
      );
      expect(
        await updater.checksum(withApi.hashUrl, withApi.hashApiUrl),
        isNull,
      );
      await expectLater(
        updater.install(withApi),
        throwsA(isA<UpdateException>()),
      );
      expect(call, isNull);
    });

    test('an APK neither link serves is not installed', () async {
      final updater = Updater(
        cacheDir: () async => cache,
        client: MockClient(
          (req) async => req.url.path == '/h'
              ? http.Response(_hash, 200)
              : http.Response('', 504),
        ),
      );
      await expectLater(
        updater.install(withApi),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            'Download failed (504)',
          ),
        ),
      );
      expect(call, isNull);
    });

    test("names the Android side's mismatch", () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => throw PlatformException(code: 'mismatch'),
          );
      await expectLater(
        updater(_hash).install(info),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            contains('checksum'),
          ),
        ),
      );
    });
  });
}
