/// The smoothed weight trend (D13): weigh-ins interpolated to one value a
/// day (MacroFactor), then exponentially smoothed (Walker's Hacker's Diet).
library;

/// One value per day from day 0 to [days] − 1, from weigh-ins keyed by day
/// index. Days between weigh-ins are linear between them; days after the
/// last carry it; days before the first are null.
List<double?> dailyWeights(Map<int, double> weighIns, int days) {
  final known = weighIns.keys.where((d) => d >= 0 && d < days).toList()..sort();
  final out = List<double?>.filled(days, null);
  for (var i = 0; i < known.length; i++) {
    final day = known[i];
    out[day] = weighIns[day];
    if (i + 1 < known.length) {
      final next = known[i + 1];
      final from = weighIns[day]!, to = weighIns[next]!;
      for (var d = day + 1; d < next; d++) {
        out[d] = from + (to - from) * (d - day) / (next - day);
      }
    } else {
      for (var d = day + 1; d < days; d++) {
        out[d] = weighIns[day];
      }
    }
  }
  return out;
}

/// The exponential trend of [daily], [alpha] the weight of each new day;
/// it starts at the first known value and is null before it.
List<double?> smoothedTrend(List<double?> daily, {required double alpha}) {
  double? trend;
  return [
    for (final value in daily)
      trend = value == null
          ? trend
          : trend == null
          ? value
          : trend + alpha * (value - trend),
  ];
}
