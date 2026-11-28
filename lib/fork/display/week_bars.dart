import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/display/contrast.dart';
import 'package:opennutritracker/fork/screens/home/home_loads.dart';
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

  /// Home's loads, for tests; the app's from the HomeBloc.
  final Stream<Object?>? homeLoads;

  const WeekBars({
    super.key,
    required this.today,
    required this.todayKcal,
    required this.todayGoalKcal,
    this.load = _trackedDays,
    this.homeLoads,
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

  // A past day edited in the Diary reaches Home as a load.
  late final StreamSubscription<Object?> _homeLoads;

  @override
  void initState() {
    super.initState();
    _homeLoads = (widget.homeLoads ?? homeLoads()).listen(
      (_) => setState(() {
        // a failed read shows empty days, as the first one does
        _days = _load()..ignore();
      }),
    );
  }

  @override
  void dispose() {
    _homeLoads.cancel();
    super.dispose();
  }

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

/// Today's bar and the past days' in [accent] on [surface]: past days a
/// paler tint, today further from the card, both at 3:1 on it (WCAG 1.4.11)
/// and 1.5:1 apart, so a pale accent pinned at the floor still tells them
/// apart by more than hue.
({Color today, Color past}) weekBarColors(Color accent, Color surface) {
  final mark = chartSafe(accent, surface);
  final tint = Color.alphaBlend(mark.withValues(alpha: 0.45), surface);
  // At chartSafe's floor exactly, the demo's blue in dark drew at 3.00:1
  // in 8-bit colour and measured under 3, so the past days keep a margin.
  final past = shiftUntil(
    tint,
    surface,
    3.1,
    darken: surface.computeLuminance() > 0.18,
  );
  final today = contrastRatio(mark, past) >= 1.5
      ? mark
      : shiftUntil(mark, past, 1.5, darken: surface.computeLuminance() > 0.18);
  return (today: today, past: past);
}

class _Bars extends StatelessWidget {
  final List<_Day> week;

  const _Bars({required this.week});

  static const _height = 36.0;

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final (:today, :past) = weekBarColors(
      Theme.of(context).colorScheme.primary,
      palette.surface,
    );
    final label = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: palette.textMuted);
    final top = week
        .expand((d) => [d.kcal, d.goal])
        .fold(1.0, (a, b) => b > a ? b : a);
    final unit = energyUnit(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    String spoken(_Day d) =>
        '${DateFormat.EEEE(locale).format(d.day)} ${energyValue(context, d.kcal)}'
        '${d.goal > 0 ? ' of ${energyValue(context, d.goal)}' : ''} $unit';
    // One node for the week, apart from the day's totals above it.
    return Semantics(
      container: true,
      label: 'Last 7 days: ${week.map(spoken).join(', ')}',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (i, d) in week.indexed)
            Expanded(
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
                            color: i == week.length - 1 ? today : past,
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
                    DateFormat.EEEEE(locale).format(d.day),
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
        ],
      ),
    );
  }
}
