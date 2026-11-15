import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/notification_service.dart';
import 'package:opennutritracker/fork/launch/launch_actions.dart';
import 'package:opennutritracker/fork/reminders/reminder_taps.dart';
import 'package:opennutritracker/fork/reminders/reminders.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import '../../helpers/fake_notification_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tzdata.initializeTimeZones);

  group('tap action', () {
    test('the weigh-in reminder opens the weigh-in', () {
      expect(
        reminderTapAction(ReminderKind.weighIn.key),
        isA<WeighInDialogAction>(),
      );
    });

    test('nothing for the check-in, upstream\'s, or one not known', () {
      for (final payload in [null, '', ReminderKind.checkIn.key, 'weighIn']) {
        expect(reminderTapAction(payload), isNull, reason: '$payload');
      }
    });
  });

  group('on the plugin', () {
    final platform = FakeNotificationPlatform();

    setUp(() {
      platform.install();
      locator.registerSingleton<NotificationService>(NotificationService());
    });
    tearDown(() async {
      platform.uninstall();
      await locator.reset();
    });

    test('the weigh-in reminder is scheduled with its payload', () async {
      final at = DateTime.now().add(const Duration(days: 1));
      const scheduler = LocalNotificationScheduler();
      await scheduler.schedule((
        kind: ReminderKind.weighIn,
        at: at,
        repeatsDaily: true,
      ));
      await scheduler.schedule((
        kind: ReminderKind.checkIn,
        at: at,
        repeatsDaily: false,
      ));
      final weighIn = platform.pending[ReminderKind.weighIn.id]!['payload'];
      expect(reminderTapAction(weighIn as String?), isA<WeighInDialogAction>());
      final checkIn = platform.pending[ReminderKind.checkIn.id]!['payload'];
      expect(reminderTapAction(checkIn as String?), isNull);
    });

    test('a failed read of the launching tap does not throw', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (_) async => throw PlatformException(code: 'no_activity'),
          );
      await openLaunchingTap();
    });
  });
}
