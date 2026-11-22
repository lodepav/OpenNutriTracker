import 'package:intl/intl.dart' as intl;
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/utils/calc/calendar_day_calc.dart';
import 'package:opennutritracker/fork/goal/goal_chart.dart' show GoalBand;
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/report/rate_text.dart';
import 'package:opennutritracker/fork/units/weight_text.dart';

/// Days of a plan before its verdict: under two weeks the trend's pace is
/// mostly water and noise.
const verdictFloorDays = 14;

/// How far the recent pace's arrival may sit from the plan's, either way,
/// and still be on plan: two weeks, a fortnight of weigh-ins' wobble.
const verdictMarginDays = 14;

/// Where a goal stands against its plan, as Goal progress's chip says it.
enum GoalVerdict {
  reached('Target reached'),
  tooEarly('Too early to tell'),
  behind('Behind plan'),
  ahead('Ahead of plan'),
  onPlan('On plan');

  final String label;
  const GoalVerdict(this.label);
}

/// The verdict on a goal [planDays] into its plan: [paceArrival] is when
/// the recent pace ([recentKgPerWeek], null without a week of trend)
/// reaches the target, null when it leads away; [planArrival] is when the
/// plan's pace from today does, null when it never does; [behindKg] is how
/// far the trend is behind the plan today at [planKgPerWeek].
GoalVerdict goalVerdict({
  required bool reached,
  required int planDays,
  required double? recentKgPerWeek,
  required DateTime? paceArrival,
  required DateTime? planArrival,
  required double behindKg,
  required double planKgPerWeek,
}) {
  if (reached) return GoalVerdict.reached;
  if (planDays < verdictFloorDays || recentKgPerWeek == null) {
    return GoalVerdict.tooEarly;
  }
  if (paceArrival == null) return GoalVerdict.behind;
  // Ground already lost counts too: the plan's date runs from today.
  final marginKg = planKgPerWeek.abs() / 7 * verdictMarginDays;
  final kgBehind = behindKg > (marginKg < 0.2 ? 0.2 : marginKg);
  if (kgBehind) return GoalVerdict.behind;
  if (planArrival == null) return GoalVerdict.onPlan;
  final late = CalendarDayCalc.daysBetween(planArrival, paceArrival);
  if (late > verdictMarginDays) return GoalVerdict.behind;
  if (late < -verdictMarginDays) return GoalVerdict.ahead;
  return GoalVerdict.onPlan;
}

/// A change of [kg] as [weightChangeText] prints it.
String signedWeightText(double kg, BodyWeightUnit unit) =>
    weightChangeText(kg, unit);

/// A pace of [kgPerWeek] as Goal progress prints it, "−0.20 kg a week", in
/// kg or in pounds for lb and st.
String signedPaceText(double kgPerWeek, BodyWeightUnit unit) =>
    '${signedRate(unit == BodyWeightUnit.kg ? kgPerWeek : kgPerWeek * 2.20462)} '
    '${unit == BodyWeightUnit.kg ? 'kg' : 'lb'} a week';

/// [start] – [end] in [format]; one date when both fall on the same day.
String dateRangeText(intl.DateFormat format, DateTime start, DateTime end) {
  final from = format.format(start);
  return CalendarDayCalc.daysBetween(start, end) == 0
      ? from
      : '$from – ${format.format(end)}';
}

/// A goal's length from [start] to [end]: in days under a week, at least
/// one, else in weeks as [goalWeeks] counts them.
String goalLengthText(DateTime start, DateTime end) {
  final days = CalendarDayCalc.daysBetween(start, end);
  if (days < 7) {
    final d = days < 1 ? 1 : days;
    return '$d ${d == 1 ? 'day' : 'days'}';
  }
  final w = goalWeeks(start, end);
  return '$w ${w == 1 ? 'week' : 'weeks'}';
}

/// The kinds of [bands] the goal chart draws over [trendLength] points a
/// day from [first]: as its painter, clamped to the trend, none empty.
Set<PhaseKind> drawnKinds(
  List<GoalBand> bands,
  DateTime first,
  int trendLength,
) {
  if (trendLength < 2) return const {};
  final last = trendLength - 1;
  return {
    for (final b in bands)
      if (CalendarDayCalc.daysBetween(first, b.end).clamp(0, last) >
          CalendarDayCalc.daysBetween(first, b.start).clamp(0, last))
        b.kind,
  };
}
