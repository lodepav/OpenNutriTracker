import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';

/// The tracked days from one day to another, both included.
typedef TrackedDaysLoader =
    Future<List<TrackedDayEntity>> Function(DateTime from, DateTime to);

// Async, so a store not there (a widget test of the card) is a failed
// future, and the bars show empty days, not a build error.
Future<List<TrackedDayEntity>> _trackedDays(DateTime from, DateTime to) async =>
    locator<GetTrackedDayUsecase>().getTrackedDaysByRange(from, to);

/// The last seven days on Home's card (seam S119, MacroFactor's week): a
/// bar a day of the energy eaten, the goal a tick across it, today's bar
/// from what Home shows rather than the stored day, which can lag it.
class WeekBars extends StatefulWidget {
  final DateTime today;
  final double todayKcal;
  final double todayGoalKcal;
  final TrackedDaysLoader load;

  const WeekBars({
    super.key,
    required this.today,
    required this.todayKcal,
    required this.todayGoalKcal,
    this.load = _trackedDays,
  });

  @override
  State<WeekBars> createState() => _WeekBarsState();
}

typedef _Day = ({DateTime day, double kcal, double goal});

class _WeekBarsState extends State<WeekBars> {
  late Future<List<TrackedDayEntity>> _days = _load();

  DateTime get _first =>
      DateTime(widget.today.year, widget.today.month, widget.today.day - 6);

  Future<List<TrackedDayEntity>> _load() =>
      widget.load(_first, DateUtils.dateOnly(widget.today));

  @override
  void didUpdateWidget(WeekBars old) {
    super.didUpdateWidget(old);
    // A day passed, or an entry was logged on Home.
    if (!DateUtils.isSameDay(old.today, widget.today) ||
        old.todayKcal != widget.todayKcal) {
      _days = _load();
    }
  }

  List<_Day> _week(List<TrackedDayEntity> tracked) {
    _Day on(DateTime day) {
      for (final t in tracked) {
        if (DateUtils.isSameDay(t.day, day)) {
          return (day: day, kcal: t.caloriesTracked, goal: t.calorieGoal);
        }
      }
      return (day: day, kcal: 0.0, goal: 0.0);
    }

    return [
      for (var i = 0; i < 6; i++)
        on(DateTime(_first.year, _first.month, _first.day + i)),
      (
        day: DateUtils.dateOnly(widget.today),
        kcal: widget.todayKcal,
        goal: widget.todayGoalKcal,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<TrackedDayEntity>>(
    future: _days,
    builder: (context, snapshot) {
      final week = _week(snapshot.data ?? const []);
      return _Bars(week: week);
    },
  );
}

class _Bars extends StatelessWidget {
  final List<_Day> week;

  const _Bars({required this.week});

  static const _height = 36.0;

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final scheme = Theme.of(context).colorScheme;
    final label = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: palette.textMuted);
    final top = week
        .expand((d) => [d.kcal, d.goal])
        .fold(1.0, (a, b) => b > a ? b : a);
    final unit = energyUnit(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final (i, d) in week.indexed)
          Expanded(
            child: Semantics(
              label:
                  '${DateFormat.EEEE().format(d.day)}: '
                  '${energyValue(context, d.kcal)} of '
                  '${energyValue(context, d.goal)} $unit',
              excludeSemantics: true,
              child: Column(
                children: [
                  SizedBox(
                    height: _height,
                    width: 14,
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        Container(
                          height: _height * (d.kcal / top).clamp(0.0, 1.0),
                          decoration: BoxDecoration(
                            color: i == week.length - 1
                                ? scheme.primary
                                : scheme.primary.withValues(alpha: 0.45),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3),
                            ),
                          ),
                        ),
                        if (d.goal > 0)
                          Positioned(
                            bottom: _height * (d.goal / top) - 1,
                            left: -3,
                            right: -3,
                            child: Container(
                              height: 2,
                              color: palette.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Dimens.spacing4),
                  Text(
                    DateFormat.E().format(d.day).substring(0, 1),
                    style: i == week.length - 1
                        ? label?.copyWith(
                            color: palette.textStrong,
                            fontWeight: FontWeight.w700,
                          )
                        : label,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
