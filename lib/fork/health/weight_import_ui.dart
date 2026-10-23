import 'package:flutter/material.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:opennutritracker/fork/dev/fake_health.dart';
import 'package:opennutritracker/fork/health/body_fat_import.dart';
import 'package:opennutritracker/fork/health/weight_import.dart';

/// After an import filed something: the weight chart, BMI and the goals.
void refreshAfterWeightImport() {
  locator<ProfileBloc>().add(LoadProfileEvent());
  locator<DiaryBloc>().updateHomePage();
}

/// "Import weight" on the health sync screen (seam S27), under upstream's
/// workout import, with its own switch and permission. Hidden where the
/// import was not started.
class WeightImportTile extends StatelessWidget {
  /// Health store present and the screen not busy.
  final bool available;

  const WeightImportTile({super.key, required this.available});

  @override
  Widget build(BuildContext context) {
    final import = WeightImport.current;
    return import == null
        ? const SizedBox.shrink()
        : HealthImportTile(
            key: const Key('fork-weight-import'),
            available: available,
            icon: Icons.monitor_weight_outlined,
            title: 'Import weight',
            subtitle:
                'Weigh-ins from a smart scale fill the weight log, one a day. '
                'A weight you enter or edit is never replaced.',
            what: 'weight',
            offMessage: 'Weight import off; imported weights stay in the log',
            noneMessage: 'Weight import on; no new weigh-ins',
            isOn: import.isOn,
            turnOn: () async {
              final days = await import.turnOn();
              if (days != null && days > 0) refreshAfterWeightImport();
              return days;
            },
            turnOff: import.turnOff,
          );
  }
}

/// "Import body fat" beside it: a smart scale's body fat % into the body
/// measurements.
class BodyFatImportTile extends StatelessWidget {
  final bool available;

  const BodyFatImportTile({super.key, required this.available});

  @override
  Widget build(BuildContext context) {
    final import = BodyFatImport.current;
    return import == null
        ? const SizedBox.shrink()
        : HealthImportTile(
            key: const Key('fork-body-fat-import'),
            available: available,
            icon: Icons.percent_rounded,
            title: 'Import body fat',
            subtitle:
                'Body fat % from a smart scale fills the body measurements, '
                'one a day. A value you enter is never replaced.',
            what: 'body fat',
            offMessage: 'Body fat import off; imported values stay',
            noneMessage: 'Body fat import on; no new readings',
            isOn: import.isOn,
            turnOn: import.turnOn,
            turnOff: import.turnOff,
          );
  }
}

/// A health import's switch: asks for the permission when turned on, and
/// says what came of it in a snackbar.
class HealthImportTile extends StatefulWidget {
  final bool available;
  final IconData icon;
  final String title;
  final String subtitle;

  /// What is read, in "Could not read [what]".
  final String what;
  final String offMessage;
  final String noneMessage;
  final Future<bool> Function() isOn;

  /// The days filed, or null when the permission was refused.
  final Future<int?> Function() turnOn;
  final Future<void> Function() turnOff;

  const HealthImportTile({
    super.key,
    required this.available,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.what,
    required this.offMessage,
    required this.noneMessage,
    required this.isOn,
    required this.turnOn,
    required this.turnOff,
  });

  @override
  State<HealthImportTile> createState() => _HealthImportTileState();
}

class _HealthImportTileState extends State<HealthImportTile> {
  bool? _on;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.isOn().then((on) {
      if (mounted) setState(() => _on = on);
    });
  }

  Future<void> _toggle(bool on) async {
    setState(() => _busy = true);
    String message;
    try {
      if (!on) {
        await widget.turnOff();
        message = widget.offMessage;
      } else {
        final days = await widget.turnOn();
        message = switch (days) {
          null => 'Permission to read ${widget.what} was not given',
          0 => widget.noneMessage,
          _ => 'Imported $days ${days == 1 ? 'day' : 'days'} of ${widget.what}',
        };
      }
    } catch (_) {
      message = 'Could not read ${widget.what} from the health store';
    }
    final now = await widget.isOn();
    if (!mounted) return;
    setState(() {
      _on = now;
      _busy = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
    secondary: Icon(widget.icon),
    title: Text(widget.title),
    subtitle: Text(widget.subtitle),
    value: _on ?? false,
    onChanged: _on == null || _busy || !(widget.available || forkFakeHealth)
        ? null
        : _toggle,
  );
}
