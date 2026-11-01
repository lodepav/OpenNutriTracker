import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/secure_app_storage_provider.dart';
import 'package:opennutritracker/fork/startup.dart';

void main() {
  tearDown(locator.reset);

  test('a retry starts from nothing registered', () async {
    locator.registerLazySingleton(SecureAppStorageProvider.new);
    await forkResetForRetry();
    expect(locator.isRegistered<SecureAppStorageProvider>(), isFalse);
  });

  test('a first start leaves the locator alone', () async {
    locator.registerSingleton<int>(1);
    await forkResetForRetry();
    expect(locator.isRegistered<int>(), isTrue);
  });
}
