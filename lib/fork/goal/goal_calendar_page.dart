import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/calendar_day_calc.dart';
import 'package:opennutritracker/fork/goal/goal_actions.dart';
import 'package:opennutritracker/fork/goal/goal_plan_view.dart' show goalTitle;
import 'package:opennutritracker/fork/goal/phase_colors.dart';
import 'package:opennutritracker/fork/goal/planner_screen.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/units/weight_text.dart';

DateTime _date(DateTime t) => DateTime(t.year, t.month, t.day);

DateTime _addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

/// Edits the running goal, or queued goal [upcomingIndex]; true once
/// saved.
typedef EditGoal =
    Future<bool> Function(BuildContext context, int? upcomingIndex);

Future<bool> _editGoal(BuildContext context, int? upcomingIndex) =>
    openGoalPlanner(context, upcomingIndex: upcomingIndex);

/// Opens the goal calendar at today's month.
Future<void> openGoalCalendar(
  BuildContext context,
  BodyWeightUnit unit,
  double? nowKg,
) => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => GoalCalendarPage(unit: unit, nowKg: nowKg),
  ),
);

/// Where a day stands among the goals: in the running goal, in queued
/// goal [queued], or in a completed [record], and its phase's kind.
typedef GoalDay = ({
  PhaseKind kind,
  bool current,
  int? queued,
  GoalRecord? record,
});

/// The goals on the calendar: completed, running and queued.
class CalendarGoals {
  final PhasePlan? plan;
  final List<PhasePlan> upcoming;
  final List<GoalRecord> history;

  const CalendarGoals({
    required this.plan,
    this.upcoming = const [],
    this.history = const [],
  });

  bool get isEmpty => plan == null && upcoming.isEmpty && history.isEmpty;

  /// [day] among the goals; null on a day none covers.
  GoalDay? on(DateTime day) {
    final date = _date(day);
    if (plan case final plan?) {
      final i = plan.indexOn(date);
      if (i >= 0 && i < plan.phases.length) {
        return (
          kind: plan.phases[i].kind,
          current: true,
          queued: null,
          record: null,
        );
      }
    }
    for (final (q, p) in upcoming.indexed) {
      final i = p.indexOn(date);
      if (i >= 0 && i < p.phases.length) {
        return (
          kind: p.phases[i].kind,
          current: false,
          queued: q,
          record: null,
        );
      }
    }
    for (final r in history.reversed) {
      if (!date.isBefore(_date(r.start)) && !date.isAfter(_date(r.end))) {
        return (kind: r.kind, current: false, queued: null, record: r);
      }
    }
    return null;
  }

  /// The first day of the first goal and the last of the last, and
  /// [today] between them; null with no goal.
  ({DateTime first, DateTime last})? span(DateTime today) {
    if (isEmpty) return null;
    final starts = [
      for (final r in history) _date(r.start),
      if (plan case final plan?) _date(plan.start),
      for (final p in upcoming) _date(p.start),
      _date(today),
    ];
    final ends = [
      for (final r in history) _date(r.end),
      if (plan case final plan?) _addDays(plan.end, -1),
      for (final p in upcoming) _addDays(p.end, -1),
      _date(today),
    ];
    return (
      first: starts.reduce((a, b) => a.isBefore(b) ? a : b),
      last: ends.reduce((a, b) => a.isAfter(b) ? a : b),
    );
  }

  /// The stretches of one kind, each phase of a plan and each completed
  /// goal, first to last.
  List<CalendarBand> bands(BodyWeightUnit unit) {
    List<CalendarBand> ofPlan(PhasePlan p, String tag) => [
      for (final (i, phase) in p.phases.indexed)
        CalendarBand(
          start: p.startOf(i),
          end: p.startOf(i + 1),
          kind: phase.kind,
          name: phase.kind == p.kind
              ? goalTitle(p, unit)
              : phaseName(phase.kind, inCut: p.kind == PhaseKind.cut),
          tag: tag,
        ),
    ];
    return [
      for (final r in history)
        CalendarBand(
          start: _date(r.start),
          end: _addDays(r.end, 1),
          kind: r.kind,
          name: r.kind != PhaseKind.maintain && r.targetKg != null
              ? '${r.kind.label} to ${weightText(r.targetKg!, unit)}'
              : r.kind.label,
          tag: 'done',
        ),
      if (plan case final plan?) ...ofPlan(plan, ''),
      for (final p in upcoming) ...ofPlan(p, 'up next'),
    ];
  }
}

/// A stretch from [start] to the day before [end], for a month's lines.
class CalendarBand {
  final DateTime start;
  final DateTime end;
  final PhaseKind kind;
  final String name;

  /// "done", "up next", or empty for the running goal.
  final String tag;

  const CalendarBand({
    required this.start,
    required this.end,
    required this.kind,
    required this.name,
    required this.tag,
  });

  /// Its line in the month from [month] to [next]: "Cut to 80 kg · from
  /// Oct 5"; null when it is not in that month.
  String? lineIn(DateTime month, DateTime next, String locale) {
    if (!start.isBefore(next) || !end.isAfter(month)) return null;
    final last = _addDays(end, -1);
    final day = intl.DateFormat.MMMd(locale);
    final starts = !start.isBefore(month);
    final ends = !end.isAfter(next);
    final when = starts && ends
        ? '${day.format(start)} – '
              '${last.month == start.month ? last.day : day.format(last)}'
        : starts
        ? 'from ${day.format(start)}'
        : ends
        ? 'until ${day.format(last)}'
        : null;
    return [name, ?when, if (tag.isNotEmpty) tag].join(' · ');
  }
}

/// The goal calendar (FgCal): a month a card from the first goal to the
/// last one planned, each day in its phase's colour, queued goals
/// striped, today outlined. Tapping a day of the running or a queued goal
/// opens what can be done with it.
class GoalCalendarPage extends StatefulWidget {
  final BodyWeightUnit unit;

  /// The trend now; null before the first weigh-in.
  final double? nowKg;
  final DateTime? today;

  /// Where the goals are kept; the active profile's by default.
  final PhaseStore? store;
  final GoalActions? actions;
  final EditGoal? edit;

  const GoalCalendarPage({
    super.key,
    required this.unit,
    required this.nowKg,
    this.today,
    this.store,
    this.actions,
    this.edit,
  });

  @override
  State<GoalCalendarPage> createState() => _GoalCalendarPageState();
}

class _GoalCalendarPageState extends State<GoalCalendarPage> {
  late final PhaseStore _store;

  // Made as the page opens: its profile is the one acted on.
  late final GoalActions _actions;
  CalendarGoals? _goals;
  final _todayKey = GlobalKey();
  var _scrolled = false;

  DateTime get _today => _date(widget.today ?? DateTime.now());

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? PhaseStore();
    _actions = widget.actions ?? GoalActions(store: _store);
    PhaseStore.changes.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    PhaseStore.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final goals = CalendarGoals(
      plan: await _store.plan(),
      upcoming: await _store.upcoming(),
      history: await _store.history(),
    );
    if (!mounted) return;
    setState(() => _goals = goals);
    if (!_scrolled) {
      _scrolled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _toToday(false));
    }
  }

  void _toToday(bool animate) {
    final context = _todayKey.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: animate ? const Duration(milliseconds: 300) : Duration.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    final goals = _goals;
    final span = goals?.span(_today);
    final locale = Localizations.localeOf(context).toLanguageTag();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          Semantics(
            identifier: 'goal-calendar-today',
            child: TextButton(
              onPressed: span == null ? null : () => _toToday(true),
              child: const Text('Today'),
            ),
          ),
        ],
      ),
      body: goals == null
          ? const Center(child: CircularProgressIndicator())
          : span == null
          ? const Center(child: Text('No goals yet.'))
          : SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                Dimens.spacing12,
                0,
                Dimens.spacing12,
                Dimens.spacing32 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: _Legend(),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                    child: Text(
                      'From your first goal to the last one planned. Tap a '
                      'day to edit or remove its goal.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  for (
                    var m = DateTime(span.first.year, span.first.month);
                    !m.isAfter(span.last);
                    m = DateTime(m.year, m.month + 1)
                  )
                    Padding(
                      key: m.year == _today.year && m.month == _today.month
                          ? _todayKey
                          : null,
                      padding: const EdgeInsets.only(bottom: Dimens.spacing12),
                      child: _Month(
                        month: m,
                        goals: goals,
                        bands: goals.bands(widget.unit),
                        today: _today,
                        locale: locale,
                        onDay: (day) => _openDay(context, goals, day),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Future<void> _openDay(
    BuildContext context,
    CalendarGoals goals,
    GoalDay day,
  ) async {
    final plan = goals.plan;
    if (day.current && plan != null) {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheet) => _NowSheet(
          plan: plan,
          next: goals.upcoming.firstOrNull,
          unit: widget.unit,
          nowKg: widget.nowKg,
          today: _today,
          onEdit: () => _edit(sheet, null),
          onComplete: () => _act(
            sheet,
            confirm: (
              title: 'Complete the goal now?',
              body: 'It is kept among your completed goals.',
              action: 'Complete',
            ),
            () => _actions.complete(plan, widget.nowKg),
          ),
          onRemove: () => _act(
            sheet,
            confirm: (
              title: 'Remove the goal?',
              body: 'It is kept nowhere, not among your completed goals.',
              action: 'Remove',
            ),
            () => _actions.remove(widget.nowKg),
          ),
        ),
      );
    } else if (day.queued case final i?) {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheet) => _NextSheet(
          upcoming: goals.upcoming,
          index: i,
          unit: widget.unit,
          onEdit: () => _edit(sheet, i),
          onEarlier: i == 0
              ? null
              : () => _act(sheet, () => _actions.moveUpcoming(i, i - 1)),
          onLater: i == goals.upcoming.length - 1
              ? null
              : () => _act(sheet, () => _actions.moveUpcoming(i, i + 1)),
          onRemove: () => _act(
            sheet,
            confirm: (
              title: 'Remove this goal?',
              body: 'It is taken out of the goals up next.',
              action: 'Remove',
            ),
            () => _actions.removeUpcoming(i),
          ),
        ),
      );
    }
  }

  Future<void> _edit(BuildContext sheet, int? upcomingIndex) async {
    Navigator.of(sheet).pop();
    await (widget.edit ?? _editGoal)(context, upcomingIndex);
  }

  /// Runs [action] from the sheet, once [confirm]ed, and closes it.
  Future<void> _act(
    BuildContext sheet,
    Future<bool> Function() action, {
    ({String title, String body, String action})? confirm,
  }) async {
    if (confirm != null) {
      final sure = await showDialog<bool>(
        context: sheet,
        builder: (dialog) => AlertDialog(
          title: Text(confirm.title),
          content: Text(confirm.body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(false),
              child: const Text('Cancel'),
            ),
            Semantics(
              identifier: 'goal-calendar-confirm',
              child: TextButton(
                onPressed: () => Navigator.of(dialog).pop(true),
                child: Text(confirm.action),
              ),
            ),
          ],
        ),
      );
      if (sure != true) return;
    }
    final done = await action();
    if (!mounted) return;
    if (sheet.mounted) Navigator.of(sheet).pop();
    if (done) {
      await _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not saved: the profile changed.')),
      );
    }
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        for (final kind in PhaseKind.values)
          _Key(color: phaseColor(context, kind), label: kind.label),
        _Key(
          color: phaseColor(context, PhaseKind.bulk),
          label: 'Up next',
          striped: true,
        ),
      ],
    ),
  );
}

class _Key extends StatelessWidget {
  final Color color;
  final String label;
  final bool striped;

  const _Key({required this.color, required this.label, this.striped = false});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: CustomPaint(
          foregroundPainter: striped ? const _Stripes() : null,
          child: Container(width: 14, height: 14, color: color),
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

/// One month: its name, its goals' lines and its days, Monday first.
class _Month extends StatelessWidget {
  final DateTime month;
  final CalendarGoals goals;
  final List<CalendarBand> bands;
  final DateTime today;
  final String locale;
  final ValueChanged<GoalDay> onDay;

  const _Month({
    required this.month,
    required this.goals,
    required this.bands,
    required this.today,
    required this.locale,
    required this.onDay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final next = DateTime(month.year, month.month + 1);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final blanks = month.weekday - 1;
    final cells = [
      for (var i = 0; i < blanks; i++) null,
      for (var d = 1; d <= days; d++) DateTime(month.year, month.month, d),
    ];
    final narrow = intl.DateFormat.EEEEE(locale);
    final monday = DateTime(2026, 10, 5);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              intl.DateFormat.yMMMM(locale).format(month),
              style: theme.textTheme.titleMedium,
            ),
          ),
          for (final band in bands)
            if (band.lineIn(month, next, locale) case final line?)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: _Swatch(
                        kind: band.kind,
                        striped: band.tag == 'up next',
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(line, style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 6),
          ExcludeSemantics(
            child: Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Text(
                      narrow.format(_addDays(monday, i)),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
          ),
          for (var w = 0; w < cells.length; w += 7)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  for (var i = w; i < w + 7; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: i < cells.length && cells[i] != null
                            ? _Day(
                                day: cells[i]!,
                                at: goals.on(cells[i]!),
                                today: today,
                                locale: locale,
                                onTap: onDay,
                              )
                            : const SizedBox(height: 40),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final PhaseKind kind;
  final bool striped;

  const _Swatch({required this.kind, this.striped = false});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: CustomPaint(
      foregroundPainter: striped ? const _Stripes() : null,
      child: Container(width: 14, height: 14, color: phaseColor(context, kind)),
    ),
  );
}

class _Day extends StatelessWidget {
  final DateTime day;
  final GoalDay? at;
  final DateTime today;
  final String locale;
  final ValueChanged<GoalDay> onTap;

  const _Day({
    required this.day,
    required this.at,
    required this.today,
    required this.locale,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final at = this.at;
    final isToday = day == today;
    final queued = at?.queued != null;
    final tappable = at != null && (at.current || queued);
    final color = at == null ? null : phaseColor(context, at.kind);
    final label = [
      intl.DateFormat.MMMd(locale).format(day),
      if (isToday) 'today',
      if (at != null) at.kind.label,
      if (queued) 'up next',
      if (at?.record != null) 'completed',
    ].join(', ');
    final cell = Container(
      height: 40,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(9),
        border: isToday
            ? Border.all(color: theme.colorScheme.onSurface, width: 2.5)
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        '${day.day}',
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
          color: at == null
              ? theme.colorScheme.onSurfaceVariant
              : onPhaseColor(context, at.kind),
        ),
      ),
    );
    return Semantics(
      identifier: 'goal-calendar-day-${day.year}-${day.month}-${day.day}',
      button: tappable,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: tappable ? () => onTap(at) : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: CustomPaint(
            foregroundPainter: queued ? const _Stripes() : null,
            child: cell,
          ),
        ),
      ),
    );
  }
}

/// Pale diagonal stripes: a goal up next.
class _Stripes extends CustomPainter {
  const _Stripes();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 3;
    for (var x = -size.height; x < size.width; x += 8) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Stripes old) => false;
}

String _ordinal(int n) => switch (n % 100) {
  11 || 12 || 13 => '${n}th',
  _ => switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  },
};

/// "Oct 5 – about Jan 17, 2027": a goal to a weight ends about then.
String _when(PhasePlan plan, String locale) {
  final day = intl.DateFormat.MMMd(locale);
  final last = _addDays(plan.end, -1);
  return '${day.format(plan.start)} – '
      '${plan.targetKg == null ? '' : 'about '}'
      '${intl.DateFormat.yMMMd(locale).format(last)}';
}

int _weeks(PhasePlan plan) => plan.phases.fold(0, (w, p) => w + p.weeks);

class _SheetHead extends StatelessWidget {
  final PhaseKind kind;
  final String pill;
  final String title;
  final String detail;

  const _SheetHead({
    required this.kind,
    required this.pill,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: phaseColor(context, kind),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              pill,
              style: theme.textTheme.labelMedium?.copyWith(
                color: onPhaseColor(context, kind),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(detail, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

Widget _row(
  BuildContext context, {
  required String id,
  required IconData icon,
  required String title,
  required String subtitle,
  required VoidCallback onTap,
  bool destructive = false,
}) {
  final error = Theme.of(context).colorScheme.error;
  return Semantics(
    identifier: id,
    child: ListTile(
      leading: Icon(icon),
      title: Text(title, style: destructive ? TextStyle(color: error) : null),
      subtitle: Text(subtitle),
      onTap: onTap,
    ),
  );
}

/// The running goal's sheet (FgSheetNow).
class _NowSheet extends StatelessWidget {
  final PhasePlan plan;
  final PhasePlan? next;
  final BodyWeightUnit unit;
  final double? nowKg;
  final DateTime today;
  final VoidCallback onEdit;
  final VoidCallback onComplete;
  final VoidCallback onRemove;

  const _NowSheet({
    required this.plan,
    required this.next,
    required this.unit,
    required this.nowKg,
    required this.today,
    required this.onEdit,
    required this.onComplete,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final ran = CalendarDayCalc.daysBetween(plan.start, today);
    final nowKg = this.nowKg;
    final then = next == null
        ? 'maintaining starts today'
        : '${goalTitle(next!, unit)} starts today';
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SheetHead(
              kind: plan.kind,
              pill: '${plan.kind.label} · now',
              title: goalTitle(plan, unit),
              detail: [
                _when(plan, locale),
                if (ran >= 0) 'week ${ran ~/ 7 + 1} of ${_weeks(plan)}',
                if (nowKg != null) '${weightText(nowKg, unit)} now',
              ].join(' · '),
            ),
            _row(
              context,
              id: 'goal-calendar-edit-now',
              icon: Icons.edit_rounded,
              title: 'Edit the plan',
              subtitle: 'The weeks so far stay as they were',
              onTap: onEdit,
            ),
            _row(
              context,
              id: 'goal-calendar-complete',
              icon: Icons.flag_rounded,
              title: 'Complete it now',
              subtitle: 'Keeps it in completed goals; $then',
              onTap: onComplete,
            ),
            _row(
              context,
              id: 'goal-calendar-remove-now',
              icon: Icons.delete_outline_rounded,
              title: 'Remove it',
              subtitle: 'Kept nowhere; $then',
              onTap: onRemove,
              destructive: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// A queued goal's sheet (FgSheetNext).
class _NextSheet extends StatelessWidget {
  final List<PhasePlan> upcoming;
  final int index;
  final BodyWeightUnit unit;
  final VoidCallback onEdit;
  final VoidCallback? onEarlier;
  final VoidCallback? onLater;
  final VoidCallback onRemove;

  const _NextSheet({
    required this.upcoming,
    required this.index,
    required this.unit,
    required this.onEdit,
    required this.onEarlier,
    required this.onLater,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final plan = upcoming[index];
    final weeks = _weeks(plan);
    final pace = plan.phases
        .where((p) => p.kind == plan.kind)
        .firstOrNull
        ?.kgPerWeek
        .abs();
    final last = index == upcoming.length - 1;
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SheetHead(
              kind: plan.kind,
              pill: '${plan.kind.label} · up next, ${_ordinal(index + 1)}',
              title: goalTitle(plan, unit),
              detail: [
                _when(plan, locale),
                '$weeks ${weeks == 1 ? 'week' : 'weeks'}',
                if (pace != null && pace > 0)
                  '${weightText(pace, unit)} a week',
              ].join(' · '),
            ),
            _row(
              context,
              id: 'goal-calendar-edit-next',
              icon: Icons.edit_rounded,
              title: 'Edit this goal',
              subtitle: 'Its pages, from where it starts',
              onTap: onEdit,
            ),
            if (onEarlier case final earlier?)
              _row(
                context,
                id: 'goal-calendar-earlier',
                icon: Icons.arrow_upward_rounded,
                title: 'Move before ${goalTitle(upcoming[index - 1], unit)}',
                subtitle:
                    'Then it starts '
                    '${intl.DateFormat.yMMMd(locale).format(upcoming[index - 1].start)}',
                onTap: earlier,
              ),
            if (onLater case final later?)
              _row(
                context,
                id: 'goal-calendar-later',
                icon: Icons.arrow_downward_rounded,
                title: 'Move after ${goalTitle(upcoming[index + 1], unit)}',
                subtitle: 'Then that one comes first',
                onTap: later,
              ),
            _row(
              context,
              id: 'goal-calendar-remove-next',
              icon: Icons.delete_outline_rounded,
              title: 'Remove this goal',
              subtitle: last
                  ? 'Nothing comes after it, so nothing moves'
                  : 'The goals after it move earlier',
              onTap: onRemove,
              destructive: true,
            ),
          ],
        ),
      ),
    );
  }
}
