import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:opennutritracker/fork/health/health_grants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('openbite/health_grants');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const types = [HealthDataType.WEIGHT];
  const access = [HealthDataAccess.READ];

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'asks the channel by the grant names, and says what it answers',
    () async {
      MethodCall? asked;
      messenger.setMockMethodCallHandler(channel, (call) async {
        asked = call;
        return true;
      });

      expect(await hasHealthGrants(['READ_WEIGHT'], types, access), isTrue);
      expect(asked?.method, 'hasGrants');
      expect(asked?.arguments, {
        'names': ['READ_WEIGHT'],
      });
    },
  );

  group('Health Connect refuses the call', () {
    setUp(
      () => messenger.setMockMethodCallHandler(
        channel,
        (_) async =>
            throw PlatformException(code: 'health_connect_unavailable'),
      ),
    );

    test('a check reports it to its caller', () {
      expect(
        hasHealthGrants(['READ_WEIGHT'], types, access),
        throwsA(isA<PlatformException>()),
      );
    });

    test('right after a request it counts as not granted', () async {
      expect(
        await hasHealthGrantsOrFalse(['READ_WEIGHT'], types, access),
        isFalse,
      );
    });
  });
}
