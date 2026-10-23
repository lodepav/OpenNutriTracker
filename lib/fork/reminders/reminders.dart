import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/data/repository/weight_log_repository.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/notification_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/check_in.dart';
import 'package:timezone/timezone.dart' as tz;

/// A time of day a reminder goes off.
typedef ReminderTime = ({int hour, int minute});

enum ReminderKind {
  weighIn(
    100,
    'weighInReminder',
    'Time to weigh in',
    'A morning weigh-in keeps the trend and the expenditure accurate.',
  ),
  checkIn(
    101,
    'checkInReminder',
    'Your weekly check-in is ready',
    'Open OpenBite to review the week and confirm the new target.',
  );

  /// The notification's id; upstream uses 0 and 1.
  final int id;
  final String key;
  final String title;
  final String body;

  const ReminderKind(this.id, this.key, this.title, this.body);
}

/// A reminder to schedule: [repeatsDaily] from [at], or once at [at].
typedef PlannedReminder = ({ReminderKind kind, DateTime at, bool repeatsDaily});

DateTime _at(DateTime day, ReminderTime time) =>
    DateTime(day.year, day.month, day.day, time.hour, time.minute);

/// The first [time] after [now], [from] that day on.
DateTime _next(DateTime now, DateTime from, ReminderTime time) {
  var at = _at(from, time);
  while (!at.isAfter(now)) {
    at = _at(DateTime(at.year, at.month, at.day + 1), time);
  }
  return at;
}

/// What to schedule at [now]. The weigh-in repeats daily, from tomorrow
/// when today's weight is in; the check-in goes off once, on the day it
/// falls due ([checkInDueDay], null with the adaptive target off), or at
/// the next [ReminderTime] when it is already due.
List<PlannedReminder> planReminders({
  required DateTime now,
  required ReminderTime? weighIn,
  required ReminderTime? checkIn,
  required bool weighedToday,
  required DateTime? checkInDueDay,
}) {
  final today = DateTime(now.year, now.month, now.day);
  return [
    if (weighIn != null)
      (
        kind: ReminderKind.weighIn,
        at: _next(
          now,
          weighedToday ? DateTime(now.year, now.month, now.day + 1) : today,
          weighIn,
        ),
        repeatsDaily: true,
      ),
    if (checkIn != null && checkInDueDay != null)
      (
        kind: ReminderKind.checkIn,
        at: _next(
          now,
          checkInDueDay.isAfter(today) ? checkInDueDay : today,
          checkIn,
        ),
        repeatsDaily: false,
      ),
  ];
}

/// The check-in reminder's text when the week's data gives a result:
/// MacroFactor tells the outcome in the notification. [previousKcal] is
/// the target the last check-in set, null before the first.
String? checkInMessage(
  CheckIn checkIn, {
  double? previousKcal,
  bool kilojoules = false,
}) {
  if (!checkIn.enoughData) return null;
  final number = NumberFormat.decimalPattern();
  String energy(double kcal) =>
      number.format((kilojoules ? UnitCalc.kcalToKj(kcal) : kcal).round());
  final unit = kilojoules ? 'kJ' : 'kcal';
  final change = previousKcal == null
      ? null
      : (kilojoules
                ? UnitCalc.kcalToKj(checkIn.proposedTargetKcal) -
                      UnitCalc.kcalToKj(previousKcal)
                : checkIn.proposedTargetKcal - previousKcal)
            .round();
  final changeText = switch (change) {
    null => '',
    0 => ', no change',
    > 0 => ', +${number.format(change)}',
    _ => ', −${number.format(-change)}',
  };
  return 'Expenditure ${energy(checkIn.expenditureKcal)} $unit, new target '
      '${energy(checkIn.proposedTargetKcal)} $unit$changeText. '
      'Open OpenBite to confirm it.';
}

/// Puts reminders in the OS.
abstract class ReminderScheduler {
  Future<bool> requestPermission();

  /// [body] in place of the kind's own text.
  Future<void> schedule(PlannedReminder reminder, {String? body});
  Future<void> cancel(ReminderKind kind);
}

class LocalNotificationScheduler implements ReminderScheduler {
  static const _channelId = 'fork_reminders';

  const LocalNotificationScheduler();

  @override
  Future<bool> requestPermission() =>
      locator<NotificationService>().requestPermission();

  @override
  Future<void> schedule(PlannedReminder reminder, {String? body}) async {
    // Upstream's initialize sets the local time zone the times use.
    await locator<NotificationService>().initialize();
    await FlutterLocalNotificationsPlugin().zonedSchedule(
      id: reminder.kind.id,
      title: reminder.kind.title,
      body: body ?? reminder.kind.body,
      scheduledDate: tz.TZDateTime.from(reminder.at, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Weigh-in and check-in',
          channelDescription: 'Reminders to weigh in and to check in.',
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: reminder.repeatsDaily
          ? DateTimeComponents.time
          : null,
    );
  }

  @override
  Future<void> cancel(ReminderKind kind) async {
    await locator<NotificationService>().initialize();
    await FlutterLocalNotificationsPlugin().cancel(id: kind.id);
  }
}

/// MacroFactor's weigh-in and check-in reminders. The times are per
/// profile, in the fork's box; the schedule is planned again whenever the
/// app opens or leaves, the profile switches, or the target settings
/// change (a check-in saves them), so a weigh-in already logged moves the
/// next reminder to tomorrow. The check-in's tells the result the data so
/// far gives, worked out each time it is planned again.
class Reminders {
  static final _log = Logger('Reminders');

  /// Bumped when a time changes, so the settings tile reloads.
  static final changes = ValueNotifier(0);

  final ReminderScheduler _scheduler;
  final Future<Box<dynamic>> Function() _box;
  final Future<bool> Function(DateTime day) _weighed;
  final Future<DateTime?> Function() _checkInDueDay;
  final Future<String?> Function() _checkInResult;
  final DateTime Function() _clock;

  Reminders({
    ReminderScheduler scheduler = const LocalNotificationScheduler(),
    Future<Box<dynamic>> Function()? box,
    Future<bool> Function(DateTime day)? weighed,
    Future<DateTime?> Function()? checkInDueDay,
    Future<String?> Function()? checkInResult,
    DateTime Function()? clock,
  }) : _scheduler = scheduler,
       _box = box ?? AdaptiveStore.openActiveBox,
       _weighed = weighed ?? _weighedInLog,
       _checkInDueDay = checkInDueDay ?? _dueFromStore,
       _checkInResult = checkInResult ?? _resultFromStore,
       _clock = clock ?? DateTime.now;

  static Future<bool> _weighedInLog(DateTime day) async =>
      await locator<WeightLogRepository>().getEntry(day) != null;

  static Future<DateTime?> _dueFromStore() async {
    final settings = AdaptiveStore.settings.value;
    if (!settings.adaptiveTarget || settings.fixedTarget) return null;
    final last = await AdaptiveStore().lastCheckIn();
    if (last == null) return DateTime(2000);
    final d = last.date;
    return DateTime(d.year, d.month, d.day + checkInEveryDays);
  }

  static Future<String?> _resultFromStore() async {
    final last = await AdaptiveStore().lastCheckIn();
    return checkInMessage(
      await AdaptiveService.fromLocator().checkIn(),
      previousKcal: last?.acceptedKcal,
      kilojoules:
          (await locator<GetConfigUsecase>().getConfig()).usesKilojoules,
    );
  }

  Future<ReminderTime?> timeOf(ReminderKind kind) async {
    final json = (await _box()).get(kind.key);
    return json is Map
        ? (hour: json['hour'] as int, minute: json['minute'] as int)
        : null;
  }

  /// Turns [kind] on at [time], or off with null; false when the
  /// notification permission was refused.
  Future<bool> set(ReminderKind kind, ReminderTime? time) async {
    if (time != null && !await _scheduler.requestPermission()) return false;
    final box = await _box();
    if (time == null) {
      await box.delete(kind.key);
    } else {
      await box.put(kind.key, {'hour': time.hour, 'minute': time.minute});
    }
    changes.value++;
    await replan();
    return true;
  }

  /// Schedules what [planReminders] gives and cancels the rest; failures
  /// are logged, since nobody waits on it.
  Future<void> replan() async {
    try {
      final now = _clock();
      final planned = planReminders(
        now: now,
        weighIn: await timeOf(ReminderKind.weighIn),
        checkIn: await timeOf(ReminderKind.checkIn),
        weighedToday: await _weighed(DateTime(now.year, now.month, now.day)),
        checkInDueDay: await _checkInDueDay(),
      );
      for (final kind in ReminderKind.values) {
        if (planned.any((p) => p.kind == kind)) continue;
        await _scheduler.cancel(kind);
      }
      for (final reminder in planned) {
        await _scheduler.schedule(
          reminder,
          body: reminder.kind == ReminderKind.checkIn
              ? await _resultOrNull()
              : null,
        );
      }
    } catch (error, stack) {
      _log.warning('Could not schedule the reminders', error, stack);
    }
  }

  /// A failed estimate leaves the reminder's own text.
  Future<String?> _resultOrNull() async {
    try {
      return await _checkInResult();
    } catch (error, stack) {
      _log.warning('Could not work out the check-in', error, stack);
      return null;
    }
  }

  /// Run at start-up (seam S6).
  static Future<void> start() async {
    final reminders = Reminders();
    void replan() => unawaited(reminders.replan());
    replan();
    AdaptiveStore.settings.addListener(replan);
    locator<HiveDBProvider>().addListener(replan);
    WidgetsBinding.instance.addObserver(_Lifecycle(replan));
  }
}

class _Lifecycle extends WidgetsBindingObserver {
  final void Function() _replan;

  _Lifecycle(this._replan);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.paused) {
      _replan();
    }
  }
}
