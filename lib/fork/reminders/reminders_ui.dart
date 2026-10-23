import 'package:flutter/material.dart';
import 'package:opennutritracker/fork/reminders/reminders.dart';

String _time(BuildContext context, ReminderTime time) =>
    TimeOfDay(hour: time.hour, minute: time.minute).format(context);

/// Seam S46: "Weigh-in and check-in reminders" in Settings, beside the
/// target's settings.
class RemindersTile extends StatefulWidget {
  final Reminders? reminders;

  const RemindersTile({super.key, this.reminders});

  @override
  State<RemindersTile> createState() => _RemindersTileState();
}

class _RemindersTileState extends State<RemindersTile> {
  late final _reminders = widget.reminders ?? Reminders();
  late Future<Map<ReminderKind, ReminderTime?>> _times = _load();

  @override
  void initState() {
    super.initState();
    Reminders.changes.addListener(_reload);
  }

  @override
  void dispose() {
    Reminders.changes.removeListener(_reload);
    super.dispose();
  }

  Future<Map<ReminderKind, ReminderTime?>> _load() async {
    try {
      return {
        for (final kind in ReminderKind.values)
          kind: await _reminders.timeOf(kind),
      };
    } catch (_) {
      return {};
    }
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _times = _load();
    });
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<Map<ReminderKind, ReminderTime?>>(
        future: _times,
        builder: (context, snapshot) {
          final times = snapshot.data ?? const {};
          final on = [
            for (final MapEntry(:key, :value) in times.entries)
              if (value != null)
                '${key == ReminderKind.weighIn ? 'Weigh-in' : 'Check-in'} '
                    '${_time(context, value)}',
          ];
          return ListTile(
            key: const ValueKey('reminders-tile'),
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Weigh-in and check-in reminders'),
            subtitle: Text(on.isEmpty ? 'Off' : on.join(' · ')),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => _RemindersDialog(_reminders),
            ),
          );
        },
      );
}

class _RemindersDialog extends StatefulWidget {
  final Reminders reminders;

  const _RemindersDialog(this.reminders);

  @override
  State<_RemindersDialog> createState() => _RemindersDialogState();
}

class _RemindersDialogState extends State<_RemindersDialog> {
  static const _defaults = {
    ReminderKind.weighIn: (hour: 7, minute: 30),
    ReminderKind.checkIn: (hour: 9, minute: 0),
  };

  final _times = <ReminderKind, ReminderTime?>{};
  var _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final kind in ReminderKind.values) {
      try {
        _times[kind] = await widget.reminders.timeOf(kind);
      } catch (_) {
        _times[kind] = null;
      }
    }
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _set(ReminderKind kind, ReminderTime? time) async {
    final done = await widget.reminders.set(kind, time);
    if (!mounted) return;
    if (!done) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reminders need the notification permission.'),
        ),
      );
      return;
    }
    setState(() => _times[kind] = time);
  }

  Future<void> _pickTime(ReminderKind kind, ReminderTime current) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked != null) {
      await _set(kind, (hour: picked.hour, minute: picked.minute));
    }
  }

  Widget _row(ReminderKind kind, String title, String explanation) {
    final time = _times[kind];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          key: ValueKey('reminder-${kind.name}'),
          contentPadding: EdgeInsets.zero,
          title: Text(title),
          subtitle: Text(explanation),
          value: time != null,
          onChanged: (on) => _set(kind, on ? _defaults[kind] : null),
        ),
        if (time != null)
          TextButton.icon(
            key: ValueKey('reminder-${kind.name}-time'),
            onPressed: () => _pickTime(kind, time),
            icon: const Icon(Icons.schedule_rounded),
            label: Text(_time(context, time)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Reminders'),
    content: !_loaded
        ? const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator()),
          )
        : SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _row(
                  ReminderKind.weighIn,
                  'Weigh-in',
                  'Every day; skipped once today\'s weight is in.',
                ),
                _row(
                  ReminderKind.checkIn,
                  'Weekly check-in',
                  'On the day it falls due, with the adaptive target on.',
                ),
              ],
            ),
          ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
