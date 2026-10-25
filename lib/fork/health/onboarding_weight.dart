import 'package:flutter/material.dart';
import 'package:opennutritracker/fork/dev/fake_health.dart';
import 'package:opennutritracker/fork/health/weight_import.dart';

/// What reading the health store's latest weigh-in came to.
sealed class HealthWeightRead {
  const HealthWeightRead();
}

class HealthWeightFound extends HealthWeightRead {
  final double kg;
  final DateTime measuredAt;
  const HealthWeightFound(this.kg, this.measuredAt);
}

class HealthWeightRefused extends HealthWeightRead {
  const HealthWeightRefused();
}

class HealthWeightNone extends HealthWeightRead {
  const HealthWeightNone();
}

/// The latest weigh-in of the past [WeightImport.backfill], asking for the
/// permission first. Onboarding has no profile to file a weight log in yet,
/// so this reads the source alone; the import proper is in Settings.
Future<HealthWeightRead> readLatestHealthWeight(
  WeightSource source, {
  DateTime Function() clock = DateTime.now,
}) async {
  try {
    if (!await source.requestPermission()) return const HealthWeightRefused();
    final now = clock();
    final readings = await source.read(
      now.subtract(WeightImport.backfill),
      now,
    );
    if (readings.isEmpty) return const HealthWeightNone();
    final latest = readings.reduce((a, b) => b.ranksAfter(a) ? b : a);
    return HealthWeightFound(latest.kg, latest.measuredAt);
  } catch (_) {
    return const HealthWeightRefused();
  }
}

/// Onboarding's "Get from Health Connect" beside the typed weight (seam
/// S99): fills the field with the latest weigh-in, or says why it can't
/// through [onNote], for the page to show under the field.
class HealthWeightButton extends StatefulWidget {
  final void Function(double kg) onWeight;
  final void Function(String note) onNote;

  /// The store to read; the device's (or the emulator's fake) when null.
  final WeightSource? source;

  const HealthWeightButton({
    super.key,
    required this.onWeight,
    required this.onNote,
    this.source,
  });

  @override
  State<HealthWeightButton> createState() => _HealthWeightButtonState();
}

class _HealthWeightButtonState extends State<HealthWeightButton> {
  bool _reading = false;

  Future<void> _read() async {
    setState(() => _reading = true);
    final source =
        widget.source ??
        (forkFakeHealth ? FakeWeights() : const HealthStoreWeights());
    final read = await readLatestHealthWeight(source);
    if (!mounted) return;
    setState(() => _reading = false);
    widget.onNote(switch (read) {
      HealthWeightFound(:final measuredAt) =>
        'From Health Connect, weighed ${_date(measuredAt)}.',
      HealthWeightRefused() =>
        "Health Connect didn't share your weight. Type it instead.",
      HealthWeightNone() =>
        'No weigh-ins in Health Connect from the past 30 days. '
            'Type your weight instead.',
    });
    if (read case HealthWeightFound(:final kg)) widget.onWeight(kg);
  }

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    key: const ValueKey('onboarding-health-weight'),
    onPressed: _reading ? null : _read,
    icon: _reading
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.monitor_weight_outlined),
    label: const Text('Get from Health Connect'),
  );
}
