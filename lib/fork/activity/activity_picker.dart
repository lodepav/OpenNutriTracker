import 'dart:math';

import 'package:flutter/material.dart';
import 'package:opennutritracker/core/utils/calc/calendar_day_calc.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/domain/entity/physical_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/met_calc.dart';
import 'package:opennutritracker/core/utils/id_generator.dart';
import 'package:opennutritracker/features/activity_detail/presentation/widget/activity_info_button.dart';
import 'package:opennutritracker/fork/adaptive/activity_credit.dart';
import 'package:opennutritracker/fork/widget/toolbar_height.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';
import 'package:opennutritracker/fork/display/sheet_inset.dart';

/// The durations the sheet offers at a tap, in minutes.
const activityDurations = [15, 30, 45, 60];

/// The list's estimate is for this many minutes.
const _listMinutes = 30;

/// An entry of [activity] for [minutes] on [day], its energy from the
/// activity's MET and [user]'s weight.
UserActivityEntity activityEntry(
  PhysicalActivityEntity activity,
  UserEntity user,
  int minutes,
  DateTime day,
) => UserActivityEntity(
  IdGenerator.getUniqueID(),
  minutes.toDouble(),
  METCalc.getTotalBurnedKcal(user, activity, minutes.toDouble()),
  day,
  activity,
);

/// [recent] logged again on [day]: the same minutes at today's weight, or
/// for a Custom activity, the same energy.
UserActivityEntity repeatEntry(
  UserActivityEntity recent,
  UserEntity user,
  DateTime day,
) {
  final activity = recent.physicalActivityEntity;
  if (activity.isCustom) {
    return UserActivityEntity(
      IdGenerator.getUniqueID(),
      0,
      recent.burnedKcal,
      day,
      activity,
      userKcal: recent.burnedKcal,
    );
  }
  return activityEntry(activity, user, recent.duration.round(), day);
}

/// "Today", "Yesterday" or the date.
String dayLabel(DateTime day, DateTime today) {
  final ago = CalendarDayCalc.daysBetween(day, today);
  if (ago == 0) return 'Today';
  if (ago == 1) return 'Yesterday';
  return DateFormat.MMMEd().format(day);
}

/// Seam S128: Add activity as MacroFactor's (ActivityAB). The recent
/// activities as chips that log again at a tap, then every activity with
/// what half an hour of it burns for this user; a row opens [DurationSheet].
class ActivityPickerView extends StatelessWidget {
  final String title;

  /// Null while they load.
  final List<PhysicalActivityEntity>? activities;
  final List<UserActivityEntity> recent;

  /// Null while it loads; the estimates wait for it.
  final UserEntity? user;

  /// "81 kg", in the user's unit.
  final String? weightText;
  final DateTime day;
  final ValueChanged<String> onSearch;
  final ValueChanged<UserActivityEntity> onLog;

  /// The Custom activity, which takes energy and not minutes.
  final ValueChanged<PhysicalActivityEntity> onOpenCustom;
  final VoidCallback onQuickAdd;
  final VoidCallback onCustom;

  /// Shown in place of the list when it failed to load.
  final Widget? error;
  final DateTime? today;

  /// What a logged activity does to the goal, said in the minutes sheet.
  final ActivityCredit credit;

  const ActivityPickerView({
    super.key,
    required this.title,
    required this.activities,
    required this.recent,
    required this.user,
    required this.weightText,
    required this.day,
    required this.onSearch,
    required this.onLog,
    required this.onOpenCustom,
    required this.onQuickAdd,
    required this.onCustom,
    this.error,
    this.today,
    this.credit = ActivityCredit.added,
  });

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final text = Theme.of(context).textTheme;
    final activities = this.activities;
    final user = this.user;
    final header = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(
          Dimens.spacing12,
          0,
          Dimens.spacing12,
          Dimens.spacing8,
        ),
        child: Semantics(
          identifier: 'add-activity-search',
          child: TextField(
            decoration: InputDecoration(
              filled: true,
              fillColor: palette.surface,
              prefixIcon: Icon(Icons.search_rounded, color: palette.textMuted),
              hintText: 'Search activities',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide(color: palette.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide(color: palette.border),
              ),
            ),
            onChanged: onSearch,
          ),
        ),
      ),
      if (recent.isNotEmpty && user != null) ...[
        const _Heading('Recent · one tap logs it again'),
        SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing12),
            itemCount: recent.length,
            separatorBuilder: (_, _) => const SizedBox(width: Dimens.spacing8),
            itemBuilder: (context, i) => _RecentChip(
              entry: recent[i],
              onTap: () => onLog(repeatEntry(recent[i], user, day)),
            ),
          ),
        ),
      ],
      _Heading('Estimated for you, per $_listMinutes min'),
    ];
    final footer = weightText == null
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(
              Dimens.spacing16,
              Dimens.spacing4,
              Dimens.spacing16,
              Dimens.spacing24,
            ),
            child: Column(
              children: [
                Text(
                  'Based on $weightText. Tap a row to pick the duration.',
                  style: text.bodySmall?.copyWith(color: palette.textMuted),
                ),
                // Where the MET figures come from, as the detail screen had.
                const ActivityInfoButton(),
              ],
            ),
          );
    return Scaffold(
      backgroundColor: palette.canvas,
      appBar: AppBar(
        backgroundColor: palette.canvas,
        toolbarHeight: twoLineToolbarHeight(context),
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        actions: [
          Semantics(
            identifier: 'add-activity-quick-add',
            child: TextButton(
              onPressed: onQuickAdd,
              child: const Text('Quick add'),
            ),
          ),
          Semantics(
            identifier: 'add-activity-custom',
            child: IconButton(
              tooltip: 'Custom activity',
              onPressed: onCustom,
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverList.list(children: header),
          if (error != null)
            SliverToBoxAdapter(child: error)
          else if (activities == null || user == null)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 32),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (activities.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(Dimens.spacing24),
                child: Text(
                  'No activity by that name',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: palette.textMuted),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing12),
              // Some 200 rows: built as they scroll in, each its slice of
              // one card.
              sliver: SliverList.builder(
                itemCount: activities.length,
                itemBuilder: (context, i) {
                  final activity = activities[i];
                  const r = Radius.circular(14);
                  // A border with corners must be one colour all round, so
                  // the slices take the surface alone and a divider.
                  return Container(
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.vertical(
                        top: i == 0 ? r : Radius.zero,
                        bottom: i == activities.length - 1 ? r : Radius.zero,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Material(
                      type: MaterialType.transparency,
                      child: Column(
                        children: [
                          if (i > 0)
                            Divider(height: 1, color: palette.surfaceMuted),
                          _ActivityRow(
                            activity: activity,
                            kcal: activity.isCustom
                                ? null
                                : METCalc.getTotalBurnedKcal(
                                    user,
                                    activity,
                                    _listMinutes.toDouble(),
                                  ),
                            onTap: () => activity.isCustom
                                ? onOpenCustom(activity)
                                : _openSheet(context, activity, user),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          if (footer != null && activities != null && user != null)
            SliverToBoxAdapter(child: footer),
        ],
      ),
    );
  }

  Future<void> _openSheet(
    BuildContext context,
    PhysicalActivityEntity activity,
    UserEntity user,
  ) async {
    final entry = await showModalBottomSheet<UserActivityEntity>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => DurationSheet(
        credit: credit,
        activity: activity,
        user: user,
        day: day,
        today: today ?? DateTime.now(),
      ),
    );
    if (entry != null) onLog(entry);
  }
}

class _Heading extends StatelessWidget {
  final String text;

  const _Heading(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      Dimens.spacing16,
      Dimens.spacing8,
      Dimens.spacing16,
      Dimens.spacing4,
    ),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: paletteOf(context).textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

/// The activity's icon on a muted square.
class _Thumb extends StatelessWidget {
  final PhysicalActivityEntity activity;
  final double size;

  const _Thumb(this.activity, {this.size = 36});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: paletteOf(context).surfaceMuted,
      borderRadius: BorderRadius.circular(size / 4),
    ),
    child: Icon(
      activity.displayIcon,
      size: size / 2,
      color: Theme.of(context).colorScheme.primary,
    ),
  );
}

class _RecentChip extends StatelessWidget {
  final UserActivityEntity entry;
  final VoidCallback onTap;

  const _RecentChip({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final activity = entry.physicalActivityEntity;
    final name = activity.getName(context);
    final amount = activity.isCustom
        ? energyText(context, entry.burnedKcal)
        : '${entry.duration.round()} min';
    return Center(
      child: Semantics(
        identifier: 'add-activity-recent-${activity.code}',
        button: true,
        label: 'Log $name, $amount, again',
        // Its own tap, since the chip's below is left out.
        onTap: onTap,
        excludeSemantics: true,
        child: ActionChip(
          avatar: Icon(activity.displayIcon, size: 18),
          label: Text.rich(
            TextSpan(
              text: '$name ',
              children: [
                TextSpan(
                  text: amount,
                  style: TextStyle(color: palette.textMuted),
                ),
              ],
            ),
          ),
          shape: const StadiumBorder(),
          side: BorderSide(color: palette.border),
          backgroundColor: palette.surface,
          materialTapTargetSize: MaterialTapTargetSize.padded,
          onPressed: onTap,
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final PhysicalActivityEntity activity;

  /// For the list's minutes; null for the Custom activity.
  final double? kcal;
  final VoidCallback onTap;

  const _ActivityRow({
    required this.activity,
    required this.kcal,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final text = Theme.of(context).textTheme;
    final kcal = this.kcal;
    final description = activity.getDescription(context);
    // Merged at the top, so the button says what it is (A2).
    return MergeSemantics(
      child: Semantics(
        identifier: 'add-activity-row-${activity.code}',
        button: true,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Dimens.spacing12,
                vertical: Dimens.spacing8,
              ),
              child: Row(
                children: [
                  ExcludeSemantics(child: _Thumb(activity)),
                  const SizedBox(width: Dimens.spacing12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(activity.getName(context), style: text.bodyLarge),
                        if (description.isNotEmpty)
                          Text(
                            description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(
                              color: palette.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Dimens.spacing8),
                  if (kcal == null)
                    Text(
                      'Enter energy',
                      style: text.bodySmall?.copyWith(color: palette.textMuted),
                    )
                  else
                    Text.rich(
                      TextSpan(
                        text: '${energyValue(context, kcal)}',
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        children: [
                          TextSpan(
                            text: ' ${energyUnit(context)}',
                            style: text.bodySmall?.copyWith(
                              color: palette.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How long, with what it burns; pops the entry to log, or nothing.
class DurationSheet extends StatefulWidget {
  final PhysicalActivityEntity activity;
  final UserEntity user;
  final DateTime day;
  final DateTime today;
  final ActivityCredit credit;

  const DurationSheet({
    super.key,
    required this.activity,
    required this.user,
    required this.day,
    required this.today,
    this.credit = ActivityCredit.added,
  });

  @override
  State<DurationSheet> createState() => _DurationSheetState();
}

class _DurationSheetState extends State<DurationSheet> {
  int _minutes = 30;
  late final _field = TextEditingController(text: '$_minutes');

  static const _step = 5;
  static const _max = 600;

  /// A stepper's tap or a chip: the field shows it too.
  void _set(int minutes) => setState(() {
    _minutes = minutes;
    _field.text = '$minutes';
  });

  /// What is typed, while it is a duration; null for 0, nothing or too long.
  int? get _typed => switch (int.tryParse(_field.text)) {
    final m? when m >= 1 && m <= _max => m,
    _ => null,
  };

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final text = Theme.of(context).textTheme;
    final activity = widget.activity;
    final name = activity.getName(context);
    final kcal = METCalc.getTotalBurnedKcal(
      widget.user,
      activity,
      _minutes.toDouble(),
    );
    final perMinute = METCalc.getTotalBurnedKcal(widget.user, activity, 1);
    final valid = _typed != null;
    return SingleChildScrollView(
      // Above the keyboard, or the navigation bar, so the field, its kcal
      // and Add stay in sight.
      padding: EdgeInsets.fromLTRB(
        Dimens.spacing16,
        0,
        Dimens.spacing16,
        Dimens.spacing24 + sheetBottomInset(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              ExcludeSemantics(child: _Thumb(activity, size: 44)),
              const SizedBox(width: Dimens.spacing12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        name,
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '${dayLabel(widget.day, widget.today)} · about '
                      '${energyText(context, perMinute)} a minute',
                      style: text.bodySmall?.copyWith(color: palette.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Dimens.spacing16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Semantics(
                identifier: 'activity-duration-less',
                child: IconButton.outlined(
                  iconSize: 28,
                  constraints: const BoxConstraints.tightFor(
                    width: 56,
                    height: 56,
                  ),
                  tooltip: '$_step minutes less',
                  // To the five below: 42 goes to 40, then 35.
                  onPressed: _minutes > _step
                      ? () => _set((_minutes - 1) ~/ _step * _step)
                      : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
              ),
              SizedBox(
                width: 120,
                child: Column(
                  children: [
                    Semantics(
                      identifier: 'activity-duration-field',
                      label: 'Minutes',
                      child: TextField(
                        controller: _field,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        textAlign: TextAlign.center,
                        style: text.displaySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          errorText: valid ? null : '1 to $_max',
                        ),
                        onChanged: (_) => setState(() {
                          if (_typed case final m?) _minutes = m;
                        }),
                      ),
                    ),
                    ExcludeSemantics(
                      child: Text(
                        'minutes',
                        style: text.bodySmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Semantics(
                identifier: 'activity-duration-more',
                child: IconButton.outlined(
                  iconSize: 28,
                  constraints: const BoxConstraints.tightFor(
                    width: 56,
                    height: 56,
                  ),
                  tooltip: '$_step minutes more',
                  onPressed: _minutes < _max
                      ? () => _set(min(_max, (_minutes ~/ _step + 1) * _step))
                      : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ),
            ],
          ),
          const SizedBox(height: Dimens.spacing12),
          Row(
            children: [
              for (final (i, m) in activityDurations.indexed) ...[
                if (i > 0) const SizedBox(width: Dimens.spacing8),
                Expanded(
                  child: Semantics(
                    identifier: 'activity-duration-$m',
                    child: ChoiceChip(
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      label: SizedBox(
                        width: double.infinity,
                        child: Text(
                          '$m',
                          textAlign: TextAlign.center,
                          semanticsLabel: '$m minutes',
                        ),
                      ),
                      selected: _minutes == m,
                      onSelected: (_) => _set(m),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: Dimens.spacing16),
          Semantics(
            liveRegion: true,
            child: Column(
              children: [
                Text(
                  '≈ ${energyText(context, kcal)}',
                  textAlign: TextAlign.center,
                  style: text.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                Text(
                  widget.credit.note(context),
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(color: palette.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: Dimens.spacing16),
          Semantics(
            identifier: 'activity-duration-add',
            child: FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: const StadiumBorder(),
              ),
              onPressed: valid
                  ? () => Navigator.of(context).pop(
                      activityEntry(
                        activity,
                        widget.user,
                        _minutes,
                        widget.day,
                      ),
                    )
                  : null,
              child: Text(
                'Add $_minutes min ${name.toLowerCase()}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
