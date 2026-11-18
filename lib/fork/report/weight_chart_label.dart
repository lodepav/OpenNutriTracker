import 'package:intl/intl.dart' show DateFormat;

/// What a screen reader says for the weight chart, in place of its axis
/// labels: "Weight chart, Nov 12 to Nov 18: trend from 87.3 to 87.1 kg,
/// 3 weigh-ins, from 86.9 to 87.4 kg." [weighIns] and [trend] are oldest
/// first, in the chart's [unit]; an empty [trend] is left unsaid.
String weightChartLabel({
  required DateTime from,
  required DateTime to,
  required String locale,
  required List<double> weighIns,
  required List<double> trend,
  required String unit,
}) {
  final date = DateFormat.MMMd(locale);
  String w(double v) => v.toStringAsFixed(1);
  final low = weighIns.reduce((a, b) => a < b ? a : b);
  final high = weighIns.reduce((a, b) => a > b ? a : b);
  return [
    'Weight chart, ${date.format(from)} to ${date.format(to)}: ',
    if (trend.isNotEmpty)
      'trend from ${w(trend.first)} to ${w(trend.last)} $unit, ',
    '${weighIns.length} weigh-in${weighIns.length == 1 ? '' : 's'}, ',
    w(low) == w(high)
        ? 'all ${w(low)} $unit.'
        : 'from ${w(low)} to ${w(high)} $unit.',
  ].join();
}
