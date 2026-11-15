import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/fork/launch/launch_actions.dart';
import 'package:opennutritracker/fork/reminders/reminders.dart';

final _log = Logger('ReminderTaps');

/// What a tap on a notification with [payload] opens: the weigh-in
/// reminder's the weigh-in dialog; any other, upstream's included, only the
/// app.
LaunchAction? reminderTapAction(String? payload) =>
    payload == ReminderKind.weighIn.key ? const WeighInDialogAction() : null;

/// The plugin's tap handler (seam S46), for a tap while the app runs.
void onNotificationTap(NotificationResponse response) {
  final action = reminderTapAction(response.payload);
  if (action != null) LaunchActionHost.deliver(action);
}

/// A tap that started the app; a failed read only skips it.
// shortcut: Android hands the same launch intent back after process death, so
// the dialog may open again then; track restores as S167 does if it bothers.
Future<void> openLaunchingTap() async {
  try {
    final details = await FlutterLocalNotificationsPlugin()
        .getNotificationAppLaunchDetails();
    final response = details?.notificationResponse;
    if (details?.didNotificationLaunchApp != true || response == null) return;
    onNotificationTap(response);
  } catch (error, stack) {
    _log.info('No notification launch read', error, stack);
  }
}
