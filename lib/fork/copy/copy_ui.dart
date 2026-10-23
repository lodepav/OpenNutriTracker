import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/fork/copy/copy_entries.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Where a copy goes: a day, and for entries a meal (null: each its own).
typedef CopyTarget = ({DateTime day, IntakeTypeEntity? meal, bool activities});

String _mealLabel(BuildContext context, IntakeTypeEntity meal) =>
    switch (meal) {
      IntakeTypeEntity.breakfast => S.of(context).breakfastLabel,
      IntakeTypeEntity.lunch => S.of(context).lunchLabel,
      IntakeTypeEntity.dinner => S.of(context).dinnerLabel,
      IntakeTypeEntity.snack => S.of(context).snackLabel,
    };

Future<DateTime> _logicalToday() async {
  final config = await locator<GetConfigUsecase>().getConfig();
  return DayBoundaryCalc.currentLogicalDayMinutes(
    config.dayStartOffsetTotalMinutes,
  );
}

void _refresh() {
  locator<DiaryBloc>()
    ..add(const LoadDiaryYearEvent())
    ..updateHomePage();
  locator<CalendarDayBloc>().add(const RefreshCalendarDayEvent());
}

/// Copies [intakes] (one entry, or a meal section) to a day and meal the
/// user picks: seams S24 (an entry) and S25 (a section), in place of
/// upstream's copy-to-today dialog.
Future<void> copyIntakesWithDialog(
  BuildContext context,
  List<IntakeEntity> intakes,
  IntakeTypeEntity meal,
) async {
  final today = await _logicalToday();
  if (!context.mounted) return;
  final target = await showDialog<CopyTarget>(
    context: context,
    builder: (_) => CopyTargetDialog(initialDay: today, initialMeal: meal),
  );
  if (target == null) return;
  await CopyEntries.fromLocator().copyIntakes(
    intakes,
    target.day,
    type: target.meal,
  );
  _refresh();
  if (context.mounted) _copied(context, target.day);
}

void _copied(BuildContext context, DateTime day) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied to ${DateFormat.MMMEd().format(day)}')),
    );

/// "Copy day" beside the diary's date (seam S26): every entry of [day],
/// each in its own meal, and its activities if wanted.
class CopyDayButton extends StatelessWidget {
  final DateTime day;

  const CopyDayButton({super.key, required this.day});

  Future<void> _copy(BuildContext context) async {
    final today = await _logicalToday();
    if (!context.mounted) return;
    final target = await showDialog<CopyTarget>(
      context: context,
      builder: (_) => CopyTargetDialog(initialDay: today, wholeDay: true),
    );
    if (target == null) return;
    await CopyEntries.fromLocator().copyDay(
      day,
      target.day,
      activities: target.activities,
    );
    _refresh();
    if (context.mounted) _copied(context, target.day);
  }

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('fork-copy-day'),
    tooltip: 'Copy day',
    icon: const Icon(Icons.copy_all_rounded),
    onPressed: () => _copy(context),
  );
}

class CopyTargetDialog extends StatefulWidget {
  final DateTime initialDay;

  /// The meal the copies go into; null with [wholeDay], where each entry
  /// keeps its own.
  final IntakeTypeEntity? initialMeal;
  final bool wholeDay;

  const CopyTargetDialog({
    super.key,
    required this.initialDay,
    this.initialMeal,
    this.wholeDay = false,
  });

  @override
  State<CopyTargetDialog> createState() => _CopyTargetDialogState();
}

class _CopyTargetDialogState extends State<CopyTargetDialog> {
  late DateTime _day = widget.initialDay;
  late IntakeTypeEntity? _meal = widget.initialMeal;
  bool _activities = false;

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2000),
      lastDate: widget.initialDay.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _day = picked);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.wholeDay ? 'Copy day' : S.of(context).copyDialogTitle),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          key: const Key('fork-copy-target-day'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_rounded),
          title: Text(DateFormat.yMMMEd().format(_day)),
          subtitle: const Text('Tap to change'),
          onTap: _pickDay,
        ),
        if (!widget.wholeDay)
          DropdownButton<IntakeTypeEntity>(
            value: _meal,
            isExpanded: true,
            onChanged: (meal) => setState(() => _meal = meal),
            items: [
              for (final meal in IntakeTypeEntity.values)
                DropdownMenuItem(
                  value: meal,
                  child: Text(_mealLabel(context, meal)),
                ),
            ],
          )
        else
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _activities,
            onChanged: (value) => setState(() => _activities = value ?? false),
            title: const Text('Include activities'),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(S.of(context).dialogCancelLabel),
      ),
      TextButton(
        onPressed: () => Navigator.of(
          context,
        ).pop((day: _day, meal: _meal, activities: _activities)),
        child: Text(S.of(context).dialogOKLabel),
      ),
    ],
  );
}
