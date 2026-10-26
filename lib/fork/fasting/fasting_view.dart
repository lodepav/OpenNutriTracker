import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/fasting/domain/entity/fasting_session_entity.dart';
import 'package:opennutritracker/features/fasting/presentation/bloc/fasting_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// The plans offered, by their fasting hours: 16 is 16:8.
const fastingPlans = [14, 16, 18, 20];

/// A fast in the history bars: its start, how long it went, its target.
typedef PastFast = ({
  DateTime start,
  Duration length,
  Duration target,
  bool ongoing,
});

/// The last [count] fasts, oldest first: those ended, by how long they ran
/// to their end, and the one under way at [now].
List<PastFast> recentFasts(
  List<FastingSessionEntity> sessions,
  DateTime now, {
  int count = 7,
}) {
  final fasts = [
    for (final s in sessions)
      if ((s.completedAt ?? s.cancelledAt ?? (s.isActive ? now : null))
          case final end?)
        (
          start: s.startedAt,
          length: end.difference(s.startedAt),
          target: s.targetDuration,
          ongoing: s.isActive,
        ),
  ]..sort((a, b) => a.start.compareTo(b.start));
  return fasts.length > count ? fasts.sublist(fasts.length - count) : fasts;
}

/// The last [time] at or before [now]: one still to come today was
/// yesterday's.
DateTime fastStartAt(TimeOfDay time, DateTime now) {
  final today = DateTime(now.year, now.month, now.day, time.hour, time.minute);
  return today.isAfter(now)
      ? DateTime(now.year, now.month, now.day - 1, time.hour, time.minute)
      : today;
}

/// "10h 59m".
String hoursMinutes(Duration d) {
  final m = d.isNegative ? 0 : d.inMinutes;
  return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
}

/// Seam S123: the fasting timer as MacroFactor's (FastingA): a ring with
/// the time left and beside it the time fasted, when it started (which can
/// be moved) and ends, the plan, the last seven fasts against their
/// targets, and End fast. The screen keeps the bloc, the warning, the
/// notification and the end's confirmation.
class FastingView extends StatefulWidget {
  /// [FastingIdle] or [FastingActive].
  final FastingState state;

  /// Every session, for the history bars.
  final Future<List<FastingSessionEntity>> history;

  final ValueChanged<int> onStart;
  final VoidCallback onEnd;

  /// The fast under way, moved to start at another time or given another
  /// target.
  final ValueChanged<FastingSessionEntity> onChange;

  /// Asks for a custom number of hours, starting from the given one.
  final Future<int?> Function(int hours) pickHours;

  const FastingView({
    super.key,
    required this.state,
    required this.history,
    required this.onStart,
    required this.onEnd,
    required this.onChange,
    required this.pickHours,
  });

  @override
  State<FastingView> createState() => _FastingViewState();
}

class _FastingViewState extends State<FastingView> {
  var _hours = 16;

  FastingActive? get _active =>
      widget.state is FastingActive ? widget.state as FastingActive : null;

  int get _planHours {
    final active = _active;
    return active == null ? _hours : active.target.inMinutes ~/ 60;
  }

  void _pick(int hours) {
    final active = _active;
    if (active == null) {
      setState(() => _hours = hours);
      return;
    }
    final s = active.session;
    if (s.targetDurationMinutes == hours * 60) return;
    widget.onChange(
      FastingSessionEntity(
        id: s.id,
        startedAt: s.startedAt,
        targetDurationMinutes: hours * 60,
      ),
    );
  }

  Future<void> _custom() async {
    final hours = await widget.pickHours(_planHours);
    if (hours != null && mounted) _pick(hours);
  }

  Future<void> _editStart(FastingActive active) async {
    final s = active.session;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(s.startedAt),
      helpText: 'Fast started at',
    );
    if (picked == null || !mounted) return;
    final start = fastStartAt(picked, DateTime.now());
    if (start == s.startedAt) return;
    widget.onChange(
      FastingSessionEntity(
        id: s.id,
        startedAt: start,
        targetDurationMinutes: s.targetDurationMinutes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;
    final l10n = S.of(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(
        Dimens.spacing12,
        0,
        Dimens.spacing12,
        Dimens.spacing32 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        if (active != null)
          _Timer(active: active, onEditStart: () => _editStart(active))
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Dimens.spacing4,
              0,
              Dimens.spacing4,
              Dimens.spacing12,
            ),
            child: Text(
              l10n.fastingSubtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: paletteOf(context).textMuted,
              ),
            ),
          ),
        const SizedBox(height: Dimens.spacing8),
        _Plans(hours: _planHours, onPick: _pick, onCustom: _custom),
        const SizedBox(height: Dimens.spacing8),
        FutureBuilder(
          future: widget.history,
          builder: (context, snapshot) {
            final now = active?.now ?? DateTime.now();
            final fasts = recentFasts(snapshot.data ?? const [], now);
            return fasts.isEmpty
                ? const SizedBox.shrink()
                : _History(fasts: fasts);
          },
        ),
        const SizedBox(height: Dimens.spacing16),
        if (active != null)
          Semantics(
            identifier: 'fasting-cancel',
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(color: paletteOf(context).border),
              ),
              onPressed: widget.onEnd,
              child: Text(l10n.fastingCancel),
            ),
          )
        else
          Semantics(
            identifier: 'fasting-start',
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(l10n.fastingStart),
              onPressed: () => widget.onStart(_hours * 60),
            ),
          ),
      ],
    );
  }
}

/// "Today", "Yesterday", "Tomorrow" or the date.
String _dayOf(BuildContext context, DateTime t, DateTime now) {
  final days = DateTime(
    t.year,
    t.month,
    t.day,
  ).difference(DateTime(now.year, now.month, now.day)).inHours;
  // Hours, rounded: a day across a clock change is 23 or 25 of them.
  return switch ((days / 24).round()) {
    0 => 'Today',
    -1 => 'Yesterday',
    1 => 'Tomorrow',
    _ => DateFormat.MMMd(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(t),
  };
}

class _Timer extends StatelessWidget {
  final FastingActive active;
  final VoidCallback onEditStart;

  const _Timer({required this.active, required this.onEditStart});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = paletteOf(context);
    final accent = Theme.of(context).colorScheme.primary;
    final target = active.target;
    final progress = target.inSeconds == 0
        ? 0.0
        : (active.elapsed.inSeconds / target.inSeconds).clamp(0.0, 1.0);
    final start = active.session.startedAt;
    final end = start.add(target);
    final targetHours = target.inMinutes / 60;
    final hoursText = targetHours == targetHours.roundToDouble()
        ? '${targetHours.round()}'
        : targetHours.toStringAsFixed(1);
    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing12),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 132,
                height: 132,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 12,
                        strokeCap: StrokeCap.round,
                        color: accent,
                        backgroundColor: palette.surfaceMuted,
                      ),
                    ),
                    // The ring is fixed; the text scales down into it at
                    // a large font.
                    Padding(
                      padding: const EdgeInsets.all(Dimens.spacing20),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: MergeSemantics(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                hoursMinutes(active.remaining),
                                style: text.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'left',
                                style: text.bodySmall?.copyWith(
                                  color: palette.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Dimens.spacing16),
              Expanded(
                child: MergeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Fasting for',
                        style: text.bodySmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                      Text(
                        hoursMinutes(active.elapsed),
                        style: text.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: Dimens.spacing8),
                      Text(
                        'of a $hoursText-hour fast · '
                        '${(progress * 100).floor()}%',
                        style: text.bodySmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Dimens.spacing12),
          Row(
            children: [
              Expanded(
                child: _Moment(
                  identifier: 'fasting-started',
                  label: 'Started',
                  time: TimeOfDay.fromDateTime(start).format(context),
                  day: '${_dayOf(context, start, active.now)} · edit',
                  onTap: onEditStart,
                ),
              ),
              const SizedBox(width: Dimens.spacing8),
              Expanded(
                child: _Moment(
                  identifier: 'fasting-ends',
                  label: 'Ends',
                  time: TimeOfDay.fromDateTime(end).format(context),
                  day: _dayOf(context, end, active.now),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Moment extends StatelessWidget {
  final String identifier;
  final String label;
  final String time;
  final String day;
  final VoidCallback? onTap;

  const _Moment({
    required this.identifier,
    required this.label,
    required this.time,
    required this.day,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = paletteOf(context);
    final muted = text.bodySmall?.copyWith(color: palette.textMuted);
    return Semantics(
      identifier: identifier,
      button: onTap != null,
      hint: onTap == null ? null : 'Change when the fast started',
      child: Material(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Dimens.spacing12,
                vertical: Dimens.spacing8,
              ),
              child: MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: muted),
                    Text(
                      time,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(day, style: muted),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Plans extends StatelessWidget {
  final int hours;
  final ValueChanged<int> onPick;
  final VoidCallback onCustom;

  const _Plans({
    required this.hours,
    required this.onPick,
    required this.onCustom,
  });

  @override
  Widget build(BuildContext context) {
    final custom = !fastingPlans.contains(hours);
    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Plan',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: paletteOf(context).textMuted,
            ),
          ),
          const SizedBox(height: Dimens.spacing8),
          Wrap(
            spacing: Dimens.spacing8,
            runSpacing: Dimens.spacing8,
            children: [
              for (final h in fastingPlans)
                Semantics(
                  identifier: 'fasting-plan-$h',
                  child: ChoiceChip(
                    label: Text(
                      '$h:${24 - h}',
                      semanticsLabel: '$h hours fasting, ${24 - h} eating',
                    ),
                    showCheckmark: false,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    selected: h == hours,
                    onSelected: (_) => onPick(h),
                  ),
                ),
              Semantics(
                identifier: 'fasting-preset-custom',
                child: ChoiceChip(
                  label: Text(
                    custom ? '$hours h' : S.of(context).fastingPresetCustom,
                  ),
                  showCheckmark: false,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  selected: custom,
                  onSelected: (_) => onCustom(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _History extends StatelessWidget {
  final List<PastFast> fasts;

  const _History({required this.fasts});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = paletteOf(context);
    final accent = Theme.of(context).colorScheme.primary;
    final muted = text.bodySmall?.copyWith(color: palette.textMuted);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final ended = fasts.where((f) => !f.ongoing).toList();
    final reached = ended.where((f) => f.length >= f.target).length;
    final targets = ended.map((f) => f.target).toSet();
    final targetText = targets.length == 1
        ? '${(targets.single.inMinutes / 60).round()} h'
        : 'their target';
    final top = fasts
        .expand((f) => [f.length, f.target])
        .reduce((a, b) => a > b ? a : b)
        .inMinutes;
    const barHeight = 56.0;
    double h(Duration d) =>
        top == 0 ? 0 : (d.inMinutes / top).clamp(0.0, 1.0) * barHeight;

    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                fasts.length == 1 ? 'Last fast' : 'Last ${fasts.length} fasts',
                style: muted,
              ),
              if (ended.isNotEmpty)
                Text(
                  '$reached of ${ended.length} reached $targetText',
                  style: muted,
                ),
            ],
          ),
          const SizedBox(height: Dimens.spacing8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final f in fasts)
                Semantics(
                  label:
                      '${DateFormat.EEEE(locale).format(f.start)}: '
                      '${hoursMinutes(f.length)} of '
                      '${hoursMinutes(f.target)}'
                      '${f.ongoing ? ', under way' : ''}',
                  excludeSemantics: true,
                  child: Column(
                    children: [
                      Container(
                        width: 16,
                        height: barHeight,
                        decoration: BoxDecoration(
                          color: palette.surfaceMuted,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.bottomCenter,
                          children: [
                            Container(
                              height: h(f.length),
                              decoration: BoxDecoration(
                                color: f.ongoing
                                    ? accent.withValues(alpha: 0.5)
                                    : accent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            Positioned(
                              left: -2,
                              right: -2,
                              bottom: h(f.target) - 1,
                              child: Container(
                                height: 2,
                                color: palette.textStrong.withValues(
                                  alpha: 0.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: Dimens.spacing4),
                      Text(
                        DateFormat.EEEEE(locale).format(f.start),
                        style: f.ongoing
                            ? text.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              )
                            : muted,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
