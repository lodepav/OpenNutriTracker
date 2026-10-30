import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/fork/copy/copy_entries.dart';
import 'package:opennutritracker/generated/l10n.dart';

String mealLabel(BuildContext context, IntakeTypeEntity meal) => switch (meal) {
  IntakeTypeEntity.breakfast => S.of(context).breakfastLabel,
  IntakeTypeEntity.lunch => S.of(context).lunchLabel,
  IntakeTypeEntity.dinner => S.of(context).dinnerLabel,
  IntakeTypeEntity.snack => S.of(context).snackLabel,
};

Future<DateTime> logicalToday() async {
  final config = await locator<GetConfigUsecase>().getConfig();
  return DayBoundaryCalc.currentLogicalDayMinutes(
    config.dayStartOffsetTotalMinutes,
  );
}

void refreshAfterCopy() {
  // Widget tests copy without the diary's blocs.
  if (!locator.isRegistered<DiaryBloc>()) return;
  locator<DiaryBloc>()
    ..add(const LoadDiaryYearEvent())
    ..updateHomePage();
  locator<CalendarDayBloc>().add(const RefreshCalendarDayEvent());
}

/// What the "where to" sheet picked: copy or move, the moment, the meal
/// (null: each its own) and, for a whole day, whether activities go too.
typedef WhereTo = ({
  bool move,
  CopyMoment moment,
  IntakeTypeEntity? meal,
  bool activities,
});

/// Copies or moves [intakes], listed under the logical day [from] (one
/// entry, a meal, or a selection), to where the user picks: seams S24
/// (an entry) and S25 (a section), in place of upstream's copy-to-today
/// dialog. [move] opens the sheet on Move.
Future<void> copyOrMoveIntakes(
  BuildContext context,
  List<IntakeEntity> intakes, {
  required DateTime from,
  bool move = false,
}) async {
  if (intakes.isEmpty) return;
  final today = await logicalToday();
  if (!context.mounted) return;
  final where = await showModalBottomSheet<WhereTo>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => WhereToSheet(
      today: today,
      now: DateTime.now(),
      from: from,
      move: move,
      meals: {for (final intake in intakes) intake.type},
      count: intakes.length,
    ),
  );
  if (where == null || !context.mounted) return;
  await placeWithUndo(
    context,
    intakes,
    where.moment,
    meal: where.meal,
    movedFrom: where.move ? from : null,
  );
}

/// Moves [intake], listed under the logical day [day], into [meal] at the
/// same time: the long-press sheet's meal chips and the edit dialog's.
Future<void> moveToMeal(
  BuildContext context,
  IntakeEntity intake,
  DateTime day,
  IntakeTypeEntity meal,
) => placeWithUndo(
  context,
  [intake],
  CopySameTimes(day),
  meal: meal,
  movedFrom: day,
);

/// Copies [intakes] to [moment] into [meal], or with [movedFrom] moves
/// them, then says where with an Undo that takes the copies back or puts
/// the moved entries back where they were.
Future<void> placeWithUndo(
  BuildContext context,
  List<IntakeEntity> intakes,
  CopyMoment moment, {
  IntakeTypeEntity? meal,
  DateTime? movedFrom,
  CopyEntries? copier,
}) async {
  final entries = copier ?? CopyEntries.fromLocator();
  final messenger = ScaffoldMessenger.maybeOf(context);
  final mealName = meal == null ? null : mealLabel(context, meal);
  final stamp = ProfileStamp.now();
  final placed = await entries.placeIntakes(
    intakes,
    moment,
    type: meal,
    movedFrom: movedFrom,
  );
  refreshAfterCopy();
  if (messenger == null) return;
  final verb = movedFrom == null ? 'Copied' : 'Moved';
  messenger.removeCurrentSnackBar();
  if (placed == null) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('Nothing ${verb.toLowerCase()}: the profile changed.'),
      ),
    );
    return;
  }
  final to = [
    ?mealName,
    if (movedFrom == null || !DateUtils.isSameDay(placed.day, movedFrom))
      DateFormat.MMMEd().format(placed.day),
  ];
  final count = intakes.length;
  messenger.showSnackBar(
    SnackBar(
      // An action keeps a bar up until dismissed: this one goes.
      persist: false,
      content: Text(
        '$verb${count == 1 ? '' : ' $count entries'}'
        '${to.isEmpty ? '' : ' to ${to.join(', ')}'}',
      ),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          final undone = await entries.undoPlace(
            placed,
            startedOn: stamp,
            moved: movedFrom == null ? null : intakes,
            from: movedFrom,
          );
          refreshAfterCopy();
          if (!undone) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Not undone: the profile changed.')),
            );
          }
        },
      ),
    ),
  );
}

/// Copies [activities] to a day the user picks (seam S24's activity
/// long-press), from any day, today's included.
Future<void> copyActivitiesWithDialog(
  BuildContext context,
  List<UserActivityEntity> activities,
) async {
  final today = await logicalToday();
  if (!context.mounted) return;
  final where = await showModalBottomSheet<WhereTo>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => WhereToSheet(
      today: today,
      now: DateTime.now(),
      count: activities.length,
    ),
  );
  if (where == null) return;
  final day = (where.moment as CopySameTimes).day;
  final copied = await CopyEntries.fromLocator().copyActivities(
    activities,
    day,
  );
  refreshAfterCopy();
  if (context.mounted) _copied(context, copied ? day : null);
}

/// "Copied to [day]", or, null, that a profile switch stopped the copy.
void _copied(BuildContext context, DateTime? day) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          day == null
              ? 'Nothing copied: the profile changed.'
              : 'Copied to ${DateFormat.MMMEd().format(day)}',
        ),
      ),
    );

/// "Copy day" beside the diary's date (seam S26): every entry of [day],
/// each in its own meal, and its activities if wanted.
class CopyDayButton extends StatelessWidget {
  final DateTime day;

  const CopyDayButton({super.key, required this.day});

  Future<void> _copy(BuildContext context) async {
    final today = await logicalToday();
    if (!context.mounted) return;
    final where = await showModalBottomSheet<WhereTo>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => WhereToSheet(
        today: today,
        now: DateTime.now(),
        count: 1,
        wholeDay: true,
      ),
    );
    if (where == null) return;
    final to = (where.moment as CopySameTimes).day;
    final copied = await CopyEntries.fromLocator().copyDay(
      day,
      to,
      activities: where.activities,
    );
    refreshAfterCopy();
    if (context.mounted) _copied(context, copied ? to : null);
  }

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('fork-copy-day'),
    tooltip: 'Copy day',
    icon: const Icon(Icons.copy_all_rounded),
    onPressed: () => _copy(context),
  );
}

enum _When { same, now, picked }

/// Where a copy or a move goes, picked with chips: the day (yesterday,
/// today, tomorrow or any), for foods the time (the same, now, or one
/// picked) and the meal, and for a whole day whether activities go too.
/// With [meals], the meals the foods are in, it copies or moves foods;
/// without, it copies activities, or with [wholeDay] a day, to a day.
class WhereToSheet extends StatefulWidget {
  /// The logical today, and the moment "now".
  final DateTime today;
  final DateTime now;

  /// The logical day the foods are listed under; a move to the same day,
  /// time and meal would change nothing.
  final DateTime? from;
  final bool move;
  final Set<IntakeTypeEntity>? meals;
  final int count;
  final bool wholeDay;

  const WhereToSheet({
    super.key,
    required this.today,
    required this.now,
    this.from,
    this.move = false,
    this.meals,
    required this.count,
    this.wholeDay = false,
  });

  @override
  State<WhereToSheet> createState() => _WhereToSheetState();
}

class _WhereToSheetState extends State<WhereToSheet> {
  late bool _move = widget.move;
  late DateTime _day = widget.today;
  var _when = _When.same;
  TimeOfDay? _time;
  late IntakeTypeEntity? _meal = widget.meals?.length == 1
      ? widget.meals!.single
      : null;
  var _activities = false;

  bool get _foods => widget.meals != null;

  DateTime _offset(int days) => DateUtils.addDaysToDate(widget.today, days);

  bool get _pickedDay => ![
    for (final days in [-1, 0, 1]) _offset(days),
  ].any((day) => DateUtils.isSameDay(day, _day));

  void _setDay(DateTime day) => setState(() {
    _day = day;
    if (_when == _When.now && !DateUtils.isSameDay(day, widget.today)) {
      _when = _When.same;
    }
  });

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2000),
      lastDate: widget.today.add(const Duration(days: 365)),
    );
    if (picked != null) _setDay(picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.fromDateTime(widget.now),
    );
    if (picked != null) {
      setState(() {
        _time = picked;
        _when = _When.picked;
      });
    }
  }

  CopyMoment get _moment => switch (_when) {
    _When.same => CopySameTimes(_day),
    _When.now => CopyAt(widget.now),
    _When.picked => CopyAt(_day, time: _time),
  };

  /// A move to where the foods already are.
  bool get _changesNothing =>
      _move &&
      _when == _When.same &&
      DateUtils.isSameDay(_day, widget.from) &&
      (_meal == null || widget.meals!.every((meal) => meal == _meal));

  Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );

  ChoiceChip _chip(
    String key,
    String label,
    bool selected,
    VoidCallback onSelected,
  ) => ChoiceChip(
    key: Key('fork-where-$key'),
    label: Text(label),
    selected: selected,
    onSelected: (_) => onSelected(),
  );

  @override
  Widget build(BuildContext context) {
    final meals = widget.meals;
    final many = widget.count > 1;
    final verb = _move ? 'Move' : 'Copy';
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_foods)
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Copy'),
                    icon: Icon(Icons.copy_rounded),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Move'),
                    icon: Icon(Icons.drive_file_move_outline),
                  ),
                ],
                selected: {_move},
                onSelectionChanged: (move) =>
                    setState(() => _move = move.single),
              )
            else
              Text(
                widget.wholeDay ? 'Copy day' : 'Copy to',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            _label(context, 'Day'),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final (days, label) in [
                  (-1, 'Yesterday'),
                  (0, 'Today'),
                  (1, 'Tomorrow'),
                ])
                  _chip(
                    'day$days',
                    label,
                    DateUtils.isSameDay(_day, _offset(days)),
                    () => _setDay(_offset(days)),
                  ),
                _chip(
                  'pick-day',
                  _pickedDay ? DateFormat.MMMEd().format(_day) : 'Pick…',
                  _pickedDay,
                  _pickDay,
                ),
              ],
            ),
            if (_foods) ...[
              _label(context, 'Time'),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _chip(
                    'same-time',
                    many ? 'Same times' : 'Same time',
                    _when == _When.same,
                    () => setState(() => _when = _When.same),
                  ),
                  if (DateUtils.isSameDay(_day, widget.today))
                    _chip(
                      'now',
                      'Now',
                      _when == _When.now,
                      () => setState(() => _when = _When.now),
                    ),
                  _chip(
                    'pick-time',
                    _when == _When.picked ? _time!.format(context) : 'Pick…',
                    _when == _When.picked,
                    _pickTime,
                  ),
                ],
              ),
              _label(context, 'Meal'),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (meals!.length > 1)
                    _chip(
                      'own-meals',
                      'Their own',
                      _meal == null,
                      () => setState(() => _meal = null),
                    ),
                  for (final meal in IntakeTypeEntity.values)
                    _chip(
                      'meal-${meal.name}',
                      mealLabel(context, meal),
                      _meal == meal,
                      () => setState(() => _meal = meal),
                    ),
                ],
              ),
            ],
            if (widget.wholeDay)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _activities,
                onChanged: (value) =>
                    setState(() => _activities = value ?? false),
                title: const Text('Include activities'),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('fork-where-done'),
                onPressed: _changesNothing
                    ? null
                    : () => Navigator.of(context).pop((
                        move: _move,
                        moment: _moment,
                        meal: _meal,
                        activities: _activities,
                      )),
                child: Text(many && _foods ? '$verb ${widget.count}' : verb),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
