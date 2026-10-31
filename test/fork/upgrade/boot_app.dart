import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final String root;
  _Paths(this.root);

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationCachePath() async => root;
}

/// Starts the app's storage as on a phone, on the files in [dir], with the same
/// Hive key every fixture was written with: 32 bytes of a fixed value, base64url.
Future<void> bootApp(Directory dir) async {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  // What the plugins answer on a phone isn't under test: an unanswered call only
  // has to not throw.
  for (final name in const [
    'com.llfbandit.app_links/messages',
    'com.llfbandit.app_links/events',
    'dexterous.com/flutter/local_notifications',
    'plugins.flutter.io/connectivity',
    'dev.fluttercommunity.plus/connectivity',
    'dev.fluttercommunity.plus/package_info',
    'dev.fluttercommunity.plus/device_info',
    'home_widget',
  ]) {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      MethodChannel(name),
      (_) async => null,
    );
  }
  PathProviderPlatform.instance = _Paths(dir.path);
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({
    'HiveEncryptionTag': base64Url.encode(List.filled(32, 7)),
  });
  await initLocator();
}
