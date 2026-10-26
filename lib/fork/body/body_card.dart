import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/fork/report/chart_touch.dart';

const _cmPerInch = 2.54;

/// Seam S40: body measurements and body fat % on Trends, one metric
/// charted over the picked range, with its latest value, the change, and
/// the entries to delete. Lengths read in inches for imperial users.
class BodyMeasurementsCard extends StatefulWidget {
  final int rangeDays;
  final AppPalette palette;
  final bool imperial;
  final MeasurementStore? store;

  const BodyMeasurementsCard({
    super.key,
    required this.rangeDays,
    required this.palette,
    required this.imperial,
    this.store,
  });

  @override
  State<BodyMeasurementsCard> createState() => _BodyMeasurementsCardState();
}

class _BodyMeasurementsCardState extends State<BodyMeasurementsCard> {
  late final _store = widget.store ?? MeasurementStore();
  late Future<List<Measurement>> _all = _load();
  BodyMetric? _picked;

  @override
  void initState() {
    super.initState();
    MeasurementStore.changes.addListener(_reload);
  }

  @override
  void dispose() {
    MeasurementStore.changes.removeListener(_reload);
    super.dispose();
  }

  /// An unreadable store shows the empty card rather than an error.
  Future<List<Measurement>> _load() =>
      _store.all().catchError((Object _) => <Measurement>[]);

  void _reload() {
    if (!mounted) return;
    setState(() {
      _all = _load();
    });
  }

  String _unit(BodyMetric metric) =>
      metric.isLength && widget.imperial ? 'in' : metric.unit;

  double _shown(BodyMetric metric, double value) =>
      metric.isLength && widget.imperial ? value / _cmPerInch : value;

  String _text(BodyMetric metric, double value, {bool signed = false}) {
    final shown = _shown(metric, value);
    return '${signed && shown > 0 ? '+' : ''}${shown.toStringAsFixed(1)} '
        '${_unit(metric)}';
  }

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _add() async {
    final values = await showDialog<(DateTime, Map<BodyMetric, double>)>(
      context: context,
      builder: (_) => _AddMeasurementsDialog(imperial: widget.imperial),
    );
    if (values == null || values.$2.isEmpty) return;
    await _store.addDay(values.$1, values.$2);
    if (mounted) setState(() => _picked = values.$2.keys.first);
  }

  /// Deleted at once, with Undo, as diary entries and weigh-ins are.
  Future<void> _delete(Measurement m) async {
    await _store.remove(m.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        // goes on its own, as the other undo bars do
        persist: false,
        content: const Text('Measurement deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _store.merge([m]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Measurement>>(
    future: _all,
    builder: (context, snapshot) {
      final all = snapshot.data;
      if (all == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: Dimens.spacing16),
        child: _card(context, all),
      );
    },
  );

  Widget _card(BuildContext context, List<Measurement> all) {
    final theme = Theme.of(context);
    final measured = {for (final m in all) m.metric};
    final metric =
        _picked ??
        BodyMetric.values.firstWhere(
          measured.contains,
          orElse: () => BodyMetric.bodyFat,
        );
    final now = DateTime.now();
    // Not a Duration: across a clock change it lands an hour off midnight.
    final from = DateTime(
      now.year,
      now.month,
      now.day - (widget.rangeDays - 1),
    );
    final series = [
      for (final m in all)
        if (m.metric == metric) m,
    ];
    final inRange = [
      for (final m in series)
        if (!m.date.isBefore(from)) m,
    ];

    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Body measurements',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                key: const ValueKey('measure-add'),
                onPressed: _add,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add', semanticsLabel: 'Add measurement'),
              ),
            ],
          ),
          if (all.isEmpty)
            Text(
              'Body fat, waist, hips and more: add a measurement to chart '
              'it. A body fat % also sharpens the expenditure estimate.',
              style: theme.textTheme.bodySmall,
            )
          else ...[
            Wrap(
              spacing: 6,
              children: [
                for (final m in BodyMetric.values)
                  if (measured.contains(m))
                    ChoiceChip(
                      label: Text(m.label),
                      selected: m == metric,
                      onSelected: (_) => setState(() => _picked = m),
                    ),
              ],
            ),
            const SizedBox(height: Dimens.spacing8),
            if (series.isNotEmpty)
              _row(
                'Latest (${_date(series.last.date)})',
                _text(metric, series.last.value),
              ),
            if (inRange.length > 1)
              _row(
                'Change in range',
                _text(
                  metric,
                  inRange.last.value - inRange.first.value,
                  signed: true,
                ),
              ),
            if (inRange.length > 1) ...[
              const SizedBox(height: Dimens.spacing16),
              _chart(context, metric, inRange, from),
            ],
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('${metric.label} entries'),
              children: [
                for (final m in series.reversed)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(_text(metric, m.value)),
                    subtitle: Text(_date(m.date)),
                    trailing: IconButton(
                      key: ValueKey('measure-delete-${m.id}'),
                      tooltip:
                          'Delete ${_text(metric, m.value)}, ${_date(m.date)}',
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => _delete(m),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chart(
    BuildContext context,
    BodyMetric metric,
    List<Measurement> points,
    DateTime from,
  ) {
    final accent = Theme.of(context).colorScheme.primary;
    final spots = [
      for (final m in points)
        FlSpot(m.date.difference(from).inHours / 24, _shown(metric, m.value)),
    ];
    final ys = [for (final s in spots) s.y];
    final low = ys.reduce((a, b) => a < b ? a : b);
    final high = ys.reduce((a, b) => a > b ? a : b);
    final pad = ((high - low) * 0.2).clamp(0.5, double.infinity);
    return Semantics(
      label: metric.label,
      child: SizedBox(
        height: 120,
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: (widget.rangeDays - 1).toDouble(),
            minY: low - pad,
            maxY: high + pad,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: const FlTitlesData(show: false),
            lineTouchData: labelledTouch(
              context,
              (s) =>
                  '${_date(points[s.spotIndex].date)} · '
                  '${_text(metric, points[s.spotIndex].value)}',
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                color: accent,
                barWidth: 2.5,
                dotData: const FlDotData(show: true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

/// A day's measurements, any of them; lengths typed in inches for
/// imperial users and stored in cm.
class _AddMeasurementsDialog extends StatefulWidget {
  final bool imperial;

  const _AddMeasurementsDialog({required this.imperial});

  @override
  State<_AddMeasurementsDialog> createState() => _AddMeasurementsDialogState();
}

class _AddMeasurementsDialogState extends State<_AddMeasurementsDialog> {
  final _fields = {
    for (final m in BodyMetric.values) m: TextEditingController(),
  };
  DateTime _date = DateTime.now();
  String? _error;

  @override
  void dispose() {
    for (final f in _fields.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _save() {
    final values = <BodyMetric, double>{};
    for (final MapEntry(key: metric, value: field) in _fields.entries) {
      final text = field.text.trim().replaceAll(',', '.');
      if (text.isEmpty) continue;
      final typed = double.tryParse(text);
      final valid =
          typed != null &&
          (metric.isLength
              ? typed > 0 && typed < 400
              : typed > 2 && typed < 70);
      if (!valid) {
        setState(() => _error = '${metric.label} is not a measurement.');
        return;
      }
      values[metric] = metric.isLength && widget.imperial
          ? typed * _cmPerInch
          : typed;
    }
    Navigator.pop(context, (_date, values));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add measurements'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_rounded),
            title: Text(
              '${_date.year}-${_date.month.toString().padLeft(2, '0')}-'
              '${_date.day.toString().padLeft(2, '0')}',
            ),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
          for (final MapEntry(key: metric, value: field) in _fields.entries)
            TextField(
              key: ValueKey('measure-${metric.name}'),
              controller: field,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: metric.label,
                suffixText: metric.isLength && widget.imperial
                    ? 'in'
                    : metric.unit,
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}
