import 'package:flutter/material.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:opennutritracker/fork/dev/fake_health.dart';
import 'package:opennutritracker/fork/health/weight_import.dart';

/// After an import filed something: the weight chart, BMI and the goals.
void refreshAfterWeightImport() {
  locator<ProfileBloc>().add(LoadProfileEvent());
  locator<DiaryBloc>().updateHomePage();
}

/// "Import weight" on the health sync screen (seam S27), under upstream's
/// workout import, with its own switch and permission.
class WeightImportTile extends StatefulWidget {
  /// Health store present and the screen not busy.
  final bool available;

  const WeightImportTile({super.key, required this.available});

  @override
  State<WeightImportTile> createState() => _WeightImportTileState();
}

class _WeightImportTileState extends State<WeightImportTile> {
  final _import = WeightImport.instance;
  bool? _on;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _import.isOn().then((on) {
      if (mounted) setState(() => _on = on);
    });
  }

  Future<void> _toggle(bool on) async {
    setState(() => _busy = true);
    String message;
    try {
      if (!on) {
        await _import.turnOff();
        message = 'Weight import off; imported weights stay in the log';
      } else {
        final days = await _import.turnOn();
        if (days == null) {
          message = 'Permission to read weight was not given';
        } else {
          if (days > 0) refreshAfterWeightImport();
          message = days == 0
              ? 'Weight import on; no new weigh-ins'
              : 'Imported $days ${days == 1 ? 'day' : 'days'} of weight';
        }
      }
    } catch (_) {
      message = 'Could not read weight from the health store';
    }
    final now = await _import.isOn();
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
    key: const Key('fork-weight-import'),
    secondary: const Icon(Icons.monitor_weight_outlined),
    title: const Text('Import weight'),
    subtitle: const Text(
      'Weigh-ins from a smart scale fill the weight log, one a day. '
      'A weight you enter or edit is never replaced.',
    ),
    value: _on ?? false,
    onChanged: _on == null || _busy || !(widget.available || forkFakeHealth)
        ? null
        : _toggle,
  );
}
