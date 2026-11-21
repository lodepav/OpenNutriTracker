import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/fork/body/measurement_store.dart';
import 'package:opennutritracker/fork/body/side_compare.dart';
import 'package:opennutritracker/fork/body/waist_ratio.dart';
import 'package:opennutritracker/fork/display/contrast.dart';
import 'package:opennutritracker/fork/report/chart_touch.dart';
import 'package:opennutritracker/fork/undo/undo_delete.dart';
import 'package:opennutritracker/fork/trends/card_title.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart'
    show signedText;
import 'package:opennutritracker/fork/display/chart_semantics.dart';

const _cmPerInch = 2.54;

String _unitOf(BodyMetric metric, bool imperial) =>
    metric.isLength && imperial ? 'in' : metric.unit;

double _shownIn(BodyMetric metric, double value, bool imperial) =>
    metric.isLength && imperial ? value / _cmPerInch : value;

String _valueText(
  BodyMetric metric,
  double value,
  bool imperial, {
  bool signed = false,
}) {
  final shown = _shownIn(metric, value, imperial);
  return '${signed ? signedText(shown, 1) : shown.toStringAsFixed(1)} '
      '${_unitOf(metric, imperial)}';
}

String _dateText(BuildContext context, DateTime d) =>
    DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag()).format(d);

/// What an adult measures, in cm or %: a dropped digit falls outside.
(int, int) _plausible(BodyMetric metric) => switch (metric) {
  BodyMetric.bodyFat => (2, 70),
  BodyMetric.waist => (40, 200),
  BodyMetric.hips || BodyMetric.chest => (50, 200),
  BodyMetric.neck => (20, 60),
  BodyMetric.leftArm || BodyMetric.rightArm => (15, 70),
  BodyMetric.leftThigh || BodyMetric.rightThigh => (30, 100),
};

/// Why [text] typed for [metric] is refused, with the range it takes;
/// null when it is empty or fits. Lengths are typed in the shown unit.
String? measurementError(
  BodyMetric metric,
  String text, {
  required bool imperial,
}) {
  final trimmed = text.trim().replaceAll(',', '.');
  if (trimmed.isEmpty) return null;
  final typed = double.tryParse(trimmed);
  final (lowCm, highCm) = _plausible(metric);
  // Inches: the whole ones inside the cm range, so the message names them.
  final (low, high) = metric.isLength && imperial
      ? ((lowCm / _cmPerInch).ceil(), (highCm / _cmPerInch).floor())
      : (lowCm, highCm);
  if (typed != null && typed >= low && typed <= high) return null;
  // "a hips" reads wrong; every other metric is singular.
  final name = metric == BodyMetric.hips
      ? 'hips'
      : 'a ${metric.label.toLowerCase()}';
  return 'Enter $name between $low and $high ${_unitOf(metric, imperial)}';
}

/// The Add measurements dialog, its day saved to [store], with Undo for
/// what it replaced; the first metric saved, or null when cancelled.
Future<BodyMetric?> addMeasurements(
  BuildContext context, {
  required bool imperial,
  MeasurementStore? store,
}) async {
  final values = await showDialog<(DateTime, Map<BodyMetric, double>)>(
    context: context,
    builder: (_) => _AddMeasurementsDialog(imperial: imperial),
  );
  if (values == null || values.$2.isEmpty) return null;
  final target = store ?? MeasurementStore();
  final saved = await target.addDay(values.$1, values.$2);
  if (!context.mounted) return values.$2.keys.first;
  if (saved.replaced.isNotEmpty) {
    final only = saved.replaced.length == 1 ? saved.replaced.single : null;
    final day = _dateText(context, values.$1);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          persist: undoBarPersists(context),
          content: Text(
            only == null
                ? 'Replaced ${saved.replaced.length} measurements from $day'
                : 'Replaced ${only.metric.label} '
                      '${_valueText(only.metric, only.value, imperial)} '
                      'from $day',
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              for (final m in saved.added) {
                await target.remove(m.id);
              }
              await target.merge(saved.replaced);
            },
          ),
        ),
      );
  }
  return values.$2.keys.first;
}

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
  late Future<(List<Measurement>, BodyFrame?)> _all = _load();
  BodyMetric? _picked;

  @override
  void initState() {
    super.initState();
    SidePartPref.ensureLoaded();
    MeasurementStore.changes.addListener(_reload);
  }

  @override
  void dispose() {
    MeasurementStore.changes.removeListener(_reload);
    super.dispose();
  }

  /// An unreadable store shows the empty card rather than an error. The
  /// frame's height decides the Waist to height link.
  Future<(List<Measurement>, BodyFrame?)> _load() => (
    _store.all().catchError((Object _) => <Measurement>[]),
    loadBodyFrame().catchError((Object _) => null),
  ).wait;

  void _reload() {
    if (!mounted) return;
    setState(() {
      _all = _load();
    });
  }

  String _unit(BodyMetric metric) => _unitOf(metric, widget.imperial);

  double _shown(BodyMetric metric, double value) =>
      _shownIn(metric, value, widget.imperial);

  String _text(BodyMetric metric, double value, {bool signed = false}) =>
      _valueText(metric, value, widget.imperial, signed: signed);

  String _date(DateTime d) => _dateText(context, d);

  Future<void> _add() async {
    final first = await addMeasurements(
      context,
      imperial: widget.imperial,
      store: _store,
    );
    if (first != null && mounted) setState(() => _picked = first);
  }

  /// Deleted at once, with Undo, as diary entries and weigh-ins are.
  Future<void> _delete(Measurement m) async {
    await _store.remove(m.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        persist: undoBarPersists(context),
        content: const Text('Measurement deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _store.merge([m]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<(List<Measurement>, BodyFrame?)>(
        future: _all,
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: Dimens.spacing16),
            child: _card(context, data.$1, data.$2),
          );
        },
      );

  Widget _card(BuildContext context, List<Measurement> all, BodyFrame? frame) {
    final theme = Theme.of(context);
    final measured = {for (final m in all) m.metric};
    // The picked metric's last entry can go, by a delete or a restore.
    final metric = measured.contains(_picked)
        ? _picked!
        : BodyMetric.values.firstWhere(
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

    final hasWaistRatio = waistPoints(all, frame?.heightCm ?? 0).isNotEmpty;
    // The pair picked when it has a day of both sides, else one that has;
    // read on the tap, as the page may have changed the pick since.
    SidePart? paired() => [
      for (final p in [SidePartPref.current.value, ...SidePart.values])
        if (sidePairs(all, p).isNotEmpty) p,
    ].firstOrNull;

    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: CardTitle(
                  child: Text(
                    'Body measurements',
                    style: theme.textTheme.titleMedium,
                  ),
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
              runSpacing: 8,
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
                'Change, last ${widget.rangeDays} days',
                // A body fat change in % reads as relative: it is in points.
                metric == BodyMetric.bodyFat
                    ? '${signedText(inRange.last.value - inRange.first.value, 1)} pts'
                    : _text(
                        metric,
                        inRange.last.value - inRange.first.value,
                        signed: true,
                      ),
              ),
            if (inRange.length > 1) ...[
              const SizedBox(height: Dimens.spacing16),
              _chart(context, metric, inRange, from),
              // The sparkline has no axis: its ends in words give the scale.
              Text(
                '${_text(metric, inRange.first.value)} on '
                '${_shortDate(inRange.first.date)} \u2192 '
                '${_text(metric, inRange.last.value)} on '
                '${_shortDate(inRange.last.date)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (hasWaistRatio)
              _link(
                const ValueKey('measure-waist-ratio'),
                'Waist to height',
                () => openWaistRatio(
                  context,
                  imperial: widget.imperial,
                  rangeDays: widget.rangeDays,
                ),
              ),
            if (paired() != null)
              _link(const ValueKey('measure-sides'), 'Left and right', () {
                final part = paired()!;
                if (part != SidePartPref.current.value) {
                  SidePartPref.save(part);
                }
                openSideCompare(
                  context,
                  imperial: widget.imperial,
                  rangeDays: widget.rangeDays,
                );
              }),
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
    final accent = chartAccent(context);
    final spots = [
      for (final m in points)
        FlSpot(m.date.difference(from).inHours / 24, _shown(metric, m.value)),
    ];
    final ys = [for (final s in spots) s.y];
    final low = ys.reduce((a, b) => a < b ? a : b);
    final high = ys.reduce((a, b) => a > b ? a : b);
    final pad = ((high - low) * 0.2).clamp(0.5, double.infinity);
    String digits(double y) => y.toStringAsFixed(1);
    return ChartSemantics(
      label:
          '${metric.label}, '
          '${spokenFromTo(digits(ys.first), digits(ys.last), _unit(metric))}',
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

  String _shortDate(DateTime d) => DateFormat.MMMd(
    Localizations.localeOf(context).toLanguageTag(),
  ).format(d);

  Widget _link(Key key, String label, VoidCallback onTap) => ListTile(
    key: key,
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );

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
  final _focus = {for (final m in BodyMetric.values) m: FocusNode()};
  DateTime _date = DateTime.now();
  Map<BodyMetric, String> _errors = const {};

  @override
  void dispose() {
    for (final f in _fields.values) {
      f.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _save() {
    final errors = {
      for (final MapEntry(key: metric, value: field) in _fields.entries)
        metric: ?measurementError(
          metric,
          field.text,
          imperial: widget.imperial,
        ),
    };
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      // Focus scrolls the first refused field into view.
      _focus[errors.keys.first]!.requestFocus();
      return;
    }
    final values = <BodyMetric, double>{};
    for (final MapEntry(key: metric, value: field) in _fields.entries) {
      final text = field.text.trim().replaceAll(',', '.');
      if (text.isEmpty) continue;
      final typed = double.parse(text);
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
              DateFormat.yMMMd(
                Localizations.localeOf(context).toLanguageTag(),
              ).format(_date),
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
            // Room for the floating label above each filled field.
            Padding(
              padding: const EdgeInsets.only(top: Dimens.spacing12),
              child: TextField(
                key: ValueKey('measure-${metric.name}'),
                controller: field,
                focusNode: _focus[metric],
                // A refusal stays only until the field is typed in again.
                onChanged: (_) {
                  if (!_errors.containsKey(metric)) return;
                  setState(
                    () => _errors = {
                      for (final e in _errors.entries)
                        if (e.key != metric) e.key: e.value,
                    },
                  );
                },
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: metric.label,
                  // The label floats so the unit shows before anything is typed.
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  suffixText: _unitOf(metric, widget.imperial),
                  errorText: _errors[metric],
                  errorMaxLines: 3,
                ),
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
