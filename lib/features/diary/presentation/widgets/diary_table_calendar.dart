import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/extensions.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
// [fork] S118 diary-header
import 'package:opennutritracker/fork/display/day_ring.dart';
// [/fork]

class DiaryTableCalendar extends StatefulWidget {
  final Function(DateTime, Map<String, TrackedDayEntity>) onDateSelected;
  final Duration calendarDurationDays;
  final DateTime focusedDate;
  final DateTime currentDate;
  final DateTime selectedDate;

  final Map<String, TrackedDayEntity> trackedDaysMap;

  const DiaryTableCalendar({
    super.key,
    required this.onDateSelected,
    required this.calendarDurationDays,
    required this.focusedDate,
    required this.currentDate,
    required this.selectedDate,
    required this.trackedDaysMap,
  });

  @override
  State<DiaryTableCalendar> createState() => _DiaryTableCalendarState();
}

/// What one line of [style] actually needs at the current text scale.
///
/// Measured rather than scaled from the package's 16.0: that constant only
/// equals a heading's height by coincidence — it is `labelSmall`'s line
/// height today — and scaling it lands fractionally short at some scales
/// (20.8 against the 21.0 wanted at 1.3x), which clips just as surely.
double _weekdayRowHeight(BuildContext context, TextStyle style) =>
    (TextPainter(
      // Any single line measures the same: the height comes from the font's
      // metrics, not from which glyphs are in it.
      text: TextSpan(text: 'Mon', style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout())
        .height;

class _DiaryTableCalendarState extends State<DiaryTableCalendar> {
  // [fork] S118 diary-header: a week of day rings, the month a tap on the
  // title away
  var _format = CalendarFormat.week;

  Widget _ring(DateTime day, {bool selected = false, bool today = false,
          bool outside = false}) =>
      DayRing(
        day: day,
        trackedDay: widget.trackedDaysMap[day.toParsedDay()],
        selected: selected,
        today: today,
        outside: outside,
      );
  // [/fork]

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final accent = Theme.of(context).colorScheme.primary;
    final textTheme = Theme.of(context).textTheme;
    final weekdayStyle =
        textTheme.labelSmall?.copyWith(color: palette.textMuted) ??
            const TextStyle();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Dimens.spacing16,
        Dimens.spacing8,
        Dimens.spacing16,
        Dimens.spacing4,
      ),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(
          Dimens.spacing8,
          Dimens.spacing12,
          Dimens.spacing8,
          Dimens.spacing12,
        ),
        child: TableCalendar(
          // [fork] S118 diary-header
          calendarFormat: _format,
          // A swipe steps the Diary a day (S176); the arrows page the weeks.
          availableGestures: AvailableGestures.none,
          onFormatChanged: (format) => setState(() => _format = format),
          rowHeight: 48,
          // [/fork]
          headerStyle: HeaderStyle(
            titleCentered: true,
            formatButtonVisible: false,
            titleTextStyle: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: palette.textStrong,
                ) ??
                const TextStyle(),
            // [fork] S92 a11y-labels-2: the chevrons are spoken, as far as
            // they move: a week in the week strip (S118)
            leftChevronIcon: Icon(Icons.chevron_left_rounded,
                color: palette.textMuted, size: 26,
                semanticLabel: _format == CalendarFormat.week
                    ? 'Previous week'
                    : 'Previous month'),
            rightChevronIcon: Icon(Icons.chevron_right_rounded,
                color: palette.textMuted, size: 26,
                semanticLabel: _format == CalendarFormat.week
                    ? 'Next week'
                    : 'Next month'),
            // [/fork]
            headerPadding: const EdgeInsets.symmetric(vertical: Dimens.spacing8),
          ),
          daysOfWeekStyle: DaysOfWeekStyle(
            weekdayStyle: weekdayStyle,
            weekendStyle: weekdayStyle,
          ),
          // The package default is a flat 16.0, and `labelSmall` is 11sp on a
          // 1.45 line height — exactly 16 logical pixels. So the row has no
          // slack at all at the default text size, and every step above it
          // cuts the headings: 21px of text in 16 at 1.3x, 32 in 16 at 2x.
          //
          // Nothing throws and no overflow stripes appear, because each
          // heading sits in a `SizedBox` of this height, and a tight
          // constraint squeezes its child rather than overflowing (#766).
          daysOfWeekHeight: _weekdayRowHeight(context, weekdayStyle),
          focusedDay: widget.focusedDate,
          // The package marks DateTime.now() as today unless told
          // otherwise; the Diary's today is the logical day (#1360).
          currentDay: widget.currentDate,
          firstDay: widget.currentDate.subtract(widget.calendarDurationDays),
          lastDay: widget.currentDate.add(widget.calendarDurationDays),
          startingDayOfWeek: StartingDayOfWeek.monday,
          onDaySelected: (selectedDay, focusedDay) {
            widget.onDateSelected(selectedDay, widget.trackedDaysMap);
          },
          calendarStyle: CalendarStyle(
            markersMaxCount: 1,
            defaultTextStyle: textTheme.bodyMedium?.copyWith(color: palette.textStrong) ?? const TextStyle(),
            weekendTextStyle: textTheme.bodyMedium?.copyWith(color: palette.textStrong) ?? const TextStyle(),
            outsideTextStyle: textTheme.bodyMedium?.copyWith(color: palette.textMuted) ?? const TextStyle(),
            todayTextStyle: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: accent,
                ) ??
                const TextStyle(),
            todayDecoration: BoxDecoration(
              border: Border.all(color: accent, width: 2.0),
              shape: BoxShape.circle,
            ),
            selectedTextStyle: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onPrimary,
                ) ??
                const TextStyle(),
            selectedDecoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
            ),
          ),
          selectedDayPredicate: (day) => isSameDay(widget.selectedDate, day),
          calendarBuilders: CalendarBuilders(
            // [fork] S118 diary-header: the day rings in place of
            // upstream's marker dot
            // (a title of its own goes without the package's tap)
            headerTitleBuilder: (context, day) => Semantics(
              button: true,
              label: _format == CalendarFormat.week
                  ? 'Show the month'
                  : 'Show the week',
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(
                  () => _format = _format == CalendarFormat.week
                      ? CalendarFormat.month
                      : CalendarFormat.week,
                ),
                child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat.yMMMM().format(day),
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: palette.textStrong,
                    ),
                  ),
                  Icon(
                    _format == CalendarFormat.week
                        ? Icons.expand_more_rounded
                        : Icons.expand_less_rounded,
                    color: palette.textMuted,
                  ),
                ],
              ),
              ),
            ),
            defaultBuilder: (context, day, _) => _ring(day),
            outsideBuilder: (context, day, _) => _ring(day, outside: true),
            todayBuilder: (context, day, _) => _ring(day, today: true),
            selectedBuilder: (context, day, _) => _ring(
              day,
              selected: true,
              today: isSameDay(day, widget.currentDate),
            ),
            // [/fork]
          ),
        ),
      ),
    );
  }
}
