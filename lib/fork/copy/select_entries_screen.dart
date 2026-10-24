import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/fork/copy/copy_entries.dart';
import 'package:opennutritracker/fork/copy/copy_ui.dart';

/// Where the selected entries go.
sealed class CopyMoment {
  const CopyMoment();
}

/// All at one moment: "now", or [time] on the logical day [at].
class CopyAt extends CopyMoment {
  final DateTime at;
  final TimeOfDay? time;

  const CopyAt(this.at, {this.time});
}

/// To a logical day, each entry at its own time of day.
class CopySameTimes extends CopyMoment {
  final DateTime day;

  const CopySameTimes(this.day);
}

/// The diary's "Select entries" (seam S26): a day's entries, picked one by
/// one, by meal or by the hour they were logged in, then copied to now, to
/// today at the same times, or to a day and time the user picks, into their
/// own meals or one meal. As MacroFactor's multi-select copy.
class SelectEntriesScreen extends StatefulWidget {
  final DateTime day;
  final CopyEntries? copier;

  /// The logical today and the moment "now", for tests.
  final DateTime Function()? now;

  const SelectEntriesScreen({
    super.key,
    required this.day,
    this.copier,
    this.now,
  });

  @override
  State<SelectEntriesScreen> createState() => _SelectEntriesScreenState();
}

class _SelectEntriesScreenState extends State<SelectEntriesScreen> {
  late final _copier = widget.copier ?? CopyEntries.fromLocator();
  late final _entries = _copier.intakesOf(widget.day);
  final _selected = <String>{};

  DateTime get _now => (widget.now ?? DateTime.now)();

  static DateTime _hourOf(IntakeEntity intake) {
    final at = intake.dateTime;
    return DateTime(at.year, at.month, at.day, at.hour);
  }

  void _toggleAll(Iterable<IntakeEntity> group, bool on) => setState(() {
    for (final intake in group) {
      on ? _selected.add(intake.id) : _selected.remove(intake.id);
    }
  });

  bool? _stateOf(Iterable<IntakeEntity> group) {
    final picked = group.where((i) => _selected.contains(i.id)).length;
    if (picked == 0) return false;
    return picked == group.length ? true : null;
  }

  Future<void> _copy(List<IntakeEntity> entries) async {
    final chosen = [
      for (final intake in entries)
        if (_selected.contains(intake.id)) intake,
    ];
    final target = await showModalBottomSheet<(CopyMoment, IntakeTypeEntity?)>(
      context: context,
      builder: (_) => _TargetSheet(now: _now),
    );
    if (target == null || !mounted) return;
    final (moment, meal) = target;
    // The logical day written to; null when a profile switch stopped it.
    final DateTime? day = switch (moment) {
      CopyAt(:final at, :final time) => await _copier.copyIntakesAt(
        chosen,
        at,
        time: time,
        type: meal,
      ),
      CopySameTimes(day: final to) =>
        await _copier.copyIntakes(chosen, to, type: meal) ? to : null,
    };
    refreshAfterCopy();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          day == null
              ? 'Nothing copied: the profile changed.'
              : 'Copied ${chosen.length} '
                    '${chosen.length == 1 ? 'entry' : 'entries'} to '
                    '${DateFormat.MMMEd().format(day)}',
        ),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<IntakeEntity>>(
    future: _entries,
    builder: (context, snapshot) {
      final entries = snapshot.data;
      return Scaffold(
        appBar: AppBar(
          title: Text(
            _selected.isEmpty
                ? 'Select entries'
                : '${_selected.length} selected',
          ),
          actions: [
            if (entries != null && entries.isNotEmpty)
              TextButton(
                key: const Key('fork-select-all'),
                onPressed: () =>
                    _toggleAll(entries, _selected.length != entries.length),
                child: Text(
                  _selected.length == entries.length ? 'None' : 'All',
                ),
              ),
          ],
        ),
        body: entries == null
            ? const Center(child: CircularProgressIndicator())
            : entries.isEmpty
            ? const Center(child: Text('Nothing logged on this day'))
            : _list(context, entries),
        bottomNavigationBar: entries == null || _selected.isEmpty
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton.icon(
                    key: const Key('fork-copy-selected'),
                    icon: const Icon(Icons.copy_rounded),
                    label: Text('Copy ${_selected.length}…'),
                    onPressed: () => _copy(entries),
                  ),
                ),
              ),
      );
    },
  );

  Widget _list(BuildContext context, List<IntakeEntity> entries) {
    final byHour = <DateTime, List<IntakeEntity>>{};
    for (final intake in entries) {
      byHour.putIfAbsent(_hourOf(intake), () => []).add(intake);
    }
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Wrap(
            spacing: 8,
            children: [
              for (final meal in IntakeTypeEntity.values)
                if (entries.where((i) => i.type == meal) case final group
                    when group.isNotEmpty)
                  FilterChip(
                    key: Key('fork-select-meal-${meal.name}'),
                    label: Text(mealLabel(context, meal)),
                    selected: _stateOf(group) == true,
                    onSelected: (on) => _toggleAll(group, on),
                  ),
            ],
          ),
        ),
        for (final MapEntry(key: hour, value: group) in byHour.entries) ...[
          CheckboxListTile(
            key: Key('fork-select-hour-${hour.hour}'),
            tristate: true,
            value: _stateOf(group),
            onChanged: (_) => _toggleAll(group, _stateOf(group) != true),
            title: Text(
              '${DateFormat.Hm().format(hour)}–'
              '${DateFormat.Hm().format(hour.add(const Duration(hours: 1)))}',
              style: textTheme.titleSmall,
            ),
          ),
          for (final intake in group)
            CheckboxListTile(
              key: Key('fork-select-${intake.id}'),
              contentPadding: const EdgeInsets.only(left: 32, right: 16),
              value: _selected.contains(intake.id),
              onChanged: (on) => _toggleAll([intake], on ?? false),
              title: Text(intake.meal.name ?? ''),
              subtitle: Text(
                '${_amount(intake)} · ${mealLabel(context, intake.type)} · '
                '${DateFormat.Hm().format(intake.dateTime)} · '
                '${intake.totalKcal.round()} kcal',
              ),
            ),
        ],
      ],
    );
  }

  static String _amount(IntakeEntity intake) {
    final amount = intake.amount;
    final text = amount == amount.roundToDouble()
        ? amount.toInt().toString()
        : amount.toStringAsFixed(1);
    return '$text ${intake.unit}';
  }
}

/// Now, today at the same times, or a day and time to pick; and the meal.
class _TargetSheet extends StatefulWidget {
  final DateTime now;

  const _TargetSheet({required this.now});

  @override
  State<_TargetSheet> createState() => _TargetSheetState();
}

class _TargetSheetState extends State<_TargetSheet> {
  IntakeTypeEntity? _meal;

  void _done(CopyMoment moment) => Navigator.of(context).pop((moment, _meal));

  Future<void> _choose() async {
    final now = widget.now;
    final day = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2000),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (day == null || !mounted) return;
    final sameTimes = await showDialog<bool>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(DateFormat.yMMMEd().format(day)),
        children: [
          SimpleDialogOption(
            key: const Key('fork-copy-same-times'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('At the times they were logged'),
          ),
          SimpleDialogOption(
            key: const Key('fork-copy-pick-time'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('All at a time I pick'),
          ),
        ],
      ),
    );
    if (sameTimes == null || !mounted) return;
    if (sameTimes) return _done(CopySameTimes(day));
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (time == null || !mounted) return;
    _done(CopyAt(DateTime(day.year, day.month, day.day), time: time));
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              'Copy to',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            trailing: DropdownButton<IntakeTypeEntity?>(
              key: const Key('fork-copy-meal'),
              value: _meal,
              onChanged: (meal) => setState(() => _meal = meal),
              items: [
                const DropdownMenuItem(child: Text('Their own meals')),
                for (final meal in IntakeTypeEntity.values)
                  DropdownMenuItem(
                    value: meal,
                    child: Text(mealLabel(context, meal)),
                  ),
              ],
            ),
          ),
          ListTile(
            key: const Key('fork-copy-now'),
            leading: const Icon(Icons.schedule_rounded),
            title: const Text('Now'),
            subtitle: Text(DateFormat.Hm().format(now)),
            onTap: () => _done(CopyAt(now)),
          ),
          ListTile(
            key: const Key('fork-copy-today'),
            leading: const Icon(Icons.today_rounded),
            title: const Text('Today, at the same times'),
            onTap: () async {
              _done(CopySameTimes(await logicalToday()));
            },
          ),
          ListTile(
            key: const Key('fork-copy-choose'),
            leading: const Icon(Icons.event_rounded),
            title: const Text('Choose day and time…'),
            onTap: _choose,
          ),
        ],
      ),
    );
  }
}

/// Opens [SelectEntriesScreen] for [day], beside "Copy day".
class SelectEntriesButton extends StatelessWidget {
  final DateTime day;

  const SelectEntriesButton({super.key, required this.day});

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('fork-select-entries'),
    tooltip: 'Select entries to copy',
    icon: const Icon(Icons.checklist_rounded),
    onPressed: () => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SelectEntriesScreen(day: day)),
    ),
  );
}
