import 'package:flutter/material.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/check_in.dart';

/// Seam S13: on home while a check-in is due; nothing otherwise.
/// [onAccepted] refreshes what shows the target.
class AdaptiveCheckInCard extends StatefulWidget {
  final VoidCallback onAccepted;
  final AdaptiveService? service;

  const AdaptiveCheckInCard({
    super.key,
    required this.onAccepted,
    this.service,
  });

  @override
  State<AdaptiveCheckInCard> createState() => _AdaptiveCheckInCardState();
}

class _AdaptiveCheckInCardState extends State<AdaptiveCheckInCard> {
  late final _service = widget.service ?? AdaptiveService.fromLocator();
  late Future<bool> _due = _service.checkInDue();

  @override
  void initState() {
    super.initState();
    AdaptiveStore.settings.addListener(_recheck);
  }

  @override
  void dispose() {
    AdaptiveStore.settings.removeListener(_recheck);
    super.dispose();
  }

  void _recheck() => setState(() => _due = _service.checkInDue());

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _due,
    builder: (context, snapshot) {
      if (snapshot.data != true) return const SizedBox.shrink();
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: ListTile(
          leading: const Icon(Icons.insights_rounded),
          title: const Text('Weekly check-in'),
          subtitle: const Text('Your expenditure and next target are ready.'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () async {
            final accepted = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => CheckInScreen(service: _service),
              ),
            );
            if (accepted == true) {
              _recheck();
              widget.onAccepted();
            }
          },
        ),
      );
    },
  );
}

class CheckInScreen extends StatefulWidget {
  final AdaptiveService service;

  const CheckInScreen({super.key, required this.service});

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  late final Future<CheckIn> _checkIn = widget.service.checkIn();
  final _target = TextEditingController();

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  static String _kcal(double value) => '${value.round()} kcal';

  static String _kg(double value, {bool signed = false}) =>
      '${signed && value > 0 ? '+' : ''}${value.toStringAsFixed(1)} kg';

  static String _eta(int days) {
    final date = DateTime.now().add(Duration(days: days));
    final weeks = (days / 7).round();
    return 'about $weeks week${weeks == 1 ? '' : 's'} '
        '(${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')})';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Weekly check-in')),
    body: FutureBuilder<CheckIn>(
      future: _checkIn,
      builder: (context, snapshot) {
        final checkIn = snapshot.data;
        if (snapshot.hasError) {
          return const Center(child: Text("Couldn't read your data."));
        }
        if (checkIn == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_target.text.isEmpty) {
          _target.text = '${checkIn.proposedTargetKcal.round()}';
        }
        final theme = Theme.of(context);
        final capped =
            (checkIn.uncappedTargetKcal - checkIn.proposedTargetKcal).abs() >=
            1;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Past week', style: theme.textTheme.titleMedium),
            _row(
              'Average logged',
              checkIn.averageIntakeKcal == null
                  ? 'nothing logged'
                  : '${_kcal(checkIn.averageIntakeKcal!)} '
                        '(${checkIn.loggedDays} of 7 days)',
            ),
            _row('Weigh-ins', '${checkIn.weighIns}'),
            if (checkIn.trendKg != null) _row('Trend', _kg(checkIn.trendKg!)),
            if (checkIn.weekChangeKg != null)
              _row('Trend change', _kg(checkIn.weekChangeKg!, signed: true)),
            if (!checkIn.enoughData)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Not enough data this week (4 logged days and a weigh-in '
                  'are needed), so the expenditure carries from before.',
                  style: TextStyle(color: theme.colorScheme.tertiary),
                ),
              ),
            const Divider(height: 32),
            _row('Expenditure', _kcal(checkIn.expenditureKcal)),
            _row('Proposed target', _kcal(checkIn.proposedTargetKcal)),
            if (capped)
              Text(
                'A check-in moves the target at most '
                '${maxCheckInChangeKcal.round()} kcal; the full change '
                'would be ${_kcal(checkIn.uncappedTargetKcal)}.',
                style: theme.textTheme.bodySmall,
              ),
            if (checkIn.daysToTargetAtGoal != null)
              _row(
                'Target weight, chosen pace',
                _eta(checkIn.daysToTargetAtGoal!),
              ),
            if (checkIn.daysToTargetAtTrend != null)
              _row(
                'Target weight, current trend',
                _eta(checkIn.daysToTargetAtTrend!),
              ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('check-in-target'),
              controller: _target,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Daily target',
                suffixText: 'kcal',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                final target = double.tryParse(_target.text.trim());
                if (target == null || target <= 0) return;
                await widget.service.accept(checkIn, target);
                if (context.mounted) Navigator.of(context).pop(true);
              },
              child: const Text('Accept'),
            ),
          ],
        );
      },
    ),
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

/// Seam S14: the D13 switches in settings.
class AdaptiveSettingsTile extends StatelessWidget {
  final AdaptiveStore? store;

  const AdaptiveSettingsTile({super.key, this.store});

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.insights_rounded),
    title: const Text('Trend and adaptive target'),
    subtitle: ValueListenableBuilder(
      valueListenable: AdaptiveStore.settings,
      builder: (context, settings, _) => Text(
        '${settings.smoothedTrend ? 'Smoothed trend' : '7-day average'} · '
        '${settings.adaptiveTarget ? 'Adaptive target' : 'Formula target'}',
      ),
    ),
    onTap: () => showDialog<void>(
      context: context,
      builder: (_) => _AdaptiveSettingsDialog(store ?? AdaptiveStore()),
    ),
  );
}

class _AdaptiveSettingsDialog extends StatelessWidget {
  final AdaptiveStore store;

  const _AdaptiveSettingsDialog(this.store);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Trend and adaptive target'),
    content: ValueListenableBuilder(
      valueListenable: AdaptiveStore.settings,
      builder: (context, settings, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Smoothed weight trend'),
            subtitle: const Text(
              'On the weight chart, in place of the 7-day average.',
            ),
            value: settings.smoothedTrend,
            onChanged: (v) => store.save(settings.copyWith(smoothedTrend: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Adaptive calorie target'),
            subtitle: const Text(
              'Measured from your weight and what you log, set at a '
              'weekly check-in. Logged activities are not added to it.',
            ),
            value: settings.adaptiveTarget,
            onChanged: (v) => store.save(settings.copyWith(adaptiveTarget: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Allow for a monthly cycle'),
            subtitle: const Text(
              'Reads a 28-day window, so a cycle\'s water swing moves the '
              'estimate less.',
            ),
            value: settings.cycleWindow,
            onChanged: (v) => store.save(settings.copyWith(cycleWindow: v)),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );
}
