import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/meal_type_suggester.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_screen.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/fork/copy/copy_entries.dart';
import 'package:opennutritracker/fork/units/energy_text.dart';

/// An entry added to a day with no time picked sits at its midnight.
bool hasNoTime(IntakeEntity intake) {
  final at = intake.dateTime;
  return at.hour == 0 && at.minute == 0 && at.second == 0;
}

/// [intakes] by the hour they were eaten, earliest first; those with no
/// time first, under null.
List<(DateTime? hour, List<IntakeEntity> intakes)> timelineHours(
  List<IntakeEntity> intakes,
) {
  final sorted = [...intakes]..sort((a, b) => a.dateTime.compareTo(b.dateTime));
  final groups = <(DateTime?, List<IntakeEntity>)>[];
  for (final intake in sorted) {
    final at = intake.dateTime;
    final hour = hasNoTime(intake)
        ? null
        : DateTime(at.year, at.month, at.day, at.hour);
    if (groups.isNotEmpty && groups.last.$1 == hour) {
      groups.last.$2.add(intake);
    } else {
      groups.add((hour, [intake]));
    }
  }
  return groups;
}

/// The intake store under the timeline, swapped out in tests.
class TimelineEntries {
  final Future<List<IntakeEntity>> Function(DateTime day) of;
  final Future<void> Function(IntakeEntity moved) replace;
  final Future<ConfigEntity> Function() config;

  const TimelineEntries({
    required this.of,
    required this.replace,
    required this.config,
  });

  /// Moving an entry within its day leaves the tracked day as it is, so
  /// the stored entry is swapped for one at the new time, its id (and so
  /// its meal group, S7) kept: upstream's update changes only the amount.
  factory TimelineEntries.fromLocator() {
    final copier = CopyEntries.fromLocator();
    final intakes = locator<IntakeRepository>();
    return TimelineEntries(
      of: copier.intakesOf,
      replace: (moved) async {
        await intakes.deleteIntake(moved);
        await intakes.addIntake(moved);
      },
      config: locator<GetConfigUsecase>().getConfig,
    );
  }
}

/// The diary's "Timeline" (seam S26): MacroFactor's day by the clock. The
/// day's foods by the hour they were eaten, each with its energy and the
/// running total; tapping one moves it to another time of the same day,
/// and "Add food at a time" logs a food at the time picked, into the meal that
/// time suggests.
class TimelineButton extends StatelessWidget {
  final DateTime day;

  const TimelineButton({super.key, required this.day});

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('timeline'),
    tooltip: 'Timeline',
    icon: const Icon(Icons.schedule_rounded),
    onPressed: () => Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => TimelineScreen(day: day)),
    ),
  );
}

class TimelineScreen extends StatefulWidget {
  final DateTime day;
  final TimelineEntries? entries;

  /// Opens upstream's food search for a meal at a moment.
  final Future<void> Function(
    BuildContext context,
    IntakeTypeEntity meal,
    DateTime at,
  )
  addAt;

  /// Material's time picker in the app.
  final Future<TimeOfDay?> Function(BuildContext context, TimeOfDay initial)
  pickTime;

  const TimelineScreen({
    super.key,
    required this.day,
    this.entries,
    this.addAt = _openAddMeal,
    this.pickTime = _showPicker,
  });

  static Future<TimeOfDay?> _showPicker(
    BuildContext context,
    TimeOfDay initial,
  ) => showTimePicker(context: context, initialTime: initial);

  static Future<void> _openAddMeal(
    BuildContext context,
    IntakeTypeEntity meal,
    DateTime at,
  ) => Navigator.of(context).pushNamed(
    NavigationOptions.addMealRoute,
    arguments: AddMealScreenArguments(
      AddMealExtension.fromIntakeTypeEntity(meal),
      at,
    ),
  );

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  late final _entries = widget.entries ?? TimelineEntries.fromLocator();
  late Future<List<IntakeEntity>> _day = _entries.of(widget.day);

  void _reload() {
    if (!mounted) return;
    setState(() {
      _day = _entries.of(widget.day);
    });
  }

  Future<TimeOfDay?> _pickTime(TimeOfDay initial) =>
      widget.pickTime(context, initial);

  Future<void> _move(IntakeEntity intake) async {
    final time = await _pickTime(
      hasNoTime(intake)
          ? const TimeOfDay(hour: 12, minute: 0)
          : TimeOfDay.fromDateTime(intake.dateTime),
    );
    if (time == null) return;
    final offset = (await _entries.config()).dayStartOffsetTotalMinutes;
    await _entries.replace(
      IntakeEntity(
        id: intake.id,
        unit: intake.unit,
        amount: intake.amount,
        type: intake.type,
        meal: intake.meal,
        dateTime: momentOn(widget.day, time, offset),
      ),
    );
    _reload();
  }

  Future<void> _add() async {
    final time = await _pickTime(TimeOfDay.now());
    if (time == null || !mounted) return;
    final config = await _entries.config();
    final at = momentOn(widget.day, time, config.dayStartOffsetTotalMinutes);
    final meal = MealTypeSuggester.suggestFromTime(
      at,
      mealSharesPct: config.mealKcalSharesPct,
    );
    if (!mounted) return;
    await widget.addAt(context, meal, at);
    _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('Timeline, ${DateFormat.MMMEd().format(widget.day)}'),
    ),
    floatingActionButton: FloatingActionButton.extended(
      key: const ValueKey('timeline-add'),
      onPressed: _add,
      icon: const Icon(Icons.add_rounded),
      label: const Text('Add food at a time'),
    ),
    body: FutureBuilder<List<IntakeEntity>>(
      future: _day,
      builder: (context, snapshot) {
        final intakes = snapshot.data;
        if (intakes == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (intakes.isEmpty) {
          return const Center(child: Text('Nothing logged this day.'));
        }
        final theme = Theme.of(context);
        var running = 0.0;
        final hours = [
          for (final (hour, group) in timelineHours(intakes))
            (hour, [for (final i in group) (i, running += i.totalKcal)]),
        ];
        return ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            for (final (hour, group) in hours) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Semantics(
                  header: true,
                  child: Text(
                    hour == null ? 'No time' : DateFormat.Hm().format(hour),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
              for (final (intake, total) in group)
                ListTile(
                  key: ValueKey('timeline-${intake.id}'),
                  leading: Text(
                    hasNoTime(intake)
                        ? '–'
                        : DateFormat.Hm().format(intake.dateTime),
                  ),
                  title: Text(intake.meal.name ?? '?'),
                  subtitle: Text(
                    '${intake.amount.round()} ${intake.unit} · '
                    '${energyText(context, intake.totalKcal)}',
                  ),
                  // The day's total up to this entry, said so on screen.
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        energyText(context, total),
                        style: theme.textTheme.bodySmall,
                      ),
                      Text('so far', style: theme.textTheme.labelSmall),
                    ],
                  ),
                  onTap: () => _move(intake),
                ),
            ],
          ],
        );
      },
    ),
  );
}
