import 'package:flutter/widgets.dart';
import 'package:opennutritracker/fork/adaptive/activity.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/copy/copy_ui.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';

/// What a logged activity does to the day's goal. Upstream adds what it
/// burned; a fixed or adaptive target leaves it out, but for the daily
/// activity mode (D17), which counts it up to [maxDailyActivityKcal], and
/// the weekly one, which takes the week's at the check-in.
enum ActivityCredit {
  added,
  dailyCapped,
  atCheckIn,
  notCounted;

  /// Under the energy an activity burns.
  String note(BuildContext context) => switch (this) {
    added => "burned, adds to the day's budget",
    dailyCapped =>
      "burned; today's goal counts activity, up to "
          '${energyText(context, maxDailyActivityKcal)}',
    atCheckIn => 'burned; counted at the next check-in, not added today',
    notCounted => 'burned; your target does not add activity',
  };

  /// Whether Home's Burned is added to the goal it shows.
  bool get raisesGoal => this == added || this == dailyCapped;
}

/// [ActivityCredit] for today, from the settings in memory.
/// Upstream's [ActivityCredit.added] when the day can not be read.
Future<ActivityCredit> activityCredit() async {
  final ForkKcalGoal goal;
  try {
    goal = await forkKcalGoal(await logicalToday());
  } catch (_) {
    return ActivityCredit.added;
  }
  if (goal.target == null) return ActivityCredit.added;
  final settings = AdaptiveStore.settings.value;
  if (settings.fixedTarget) return ActivityCredit.notCounted;
  return switch (settings.activityMode) {
    ActivityMode.daily => ActivityCredit.dailyCapped,
    ActivityMode.weekly => ActivityCredit.atCheckIn,
    ActivityMode.off => ActivityCredit.notCounted,
  };
}
