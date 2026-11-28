/// Weight trends. The one shown, and used by the check-in and Goal planner,
/// is [twoSidedTrend] (D70): a level-and-slope Kalman filter with a backward
/// (RTS) pass, so past days are redrawn as new weigh-ins arrive. The
/// expenditure estimate keeps D13's: weigh-ins interpolated to one value a
/// day ([dailyWeights], MacroFactor), then exponentially smoothed
/// ([smoothedTrend], Walker's Hacker's Diet).
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

// D70's settings, scored on the owner's weigh-ins: how much the level and
// the daily slope may drift each day, and the noise of one weigh-in (kg²).
const _levelDrift = 0.002;
const _slopeDrift = 0.00002;
const _weighInNoise = 0.25;

/// D70's trend, one value per day from day 0 to [days] − 1, from weigh-ins
/// keyed by day index: null before the first weigh-in, the smoothed level
/// from it to the last, then that last level held (the slope is not
/// extrapolated). Only real weigh-ins update it; days between get no point.
List<double?> twoSidedTrend(Map<int, double> weighIns, int days) {
  final known = weighIns.keys.where((d) => d >= 0 && d < days).toList()..sort();
  final out = List<double?>.filled(days, null);
  if (known.isEmpty) return out;
  final first = known.first, span = known.last - first + 1;
  // Filtered (x, P) and predicted (xp, Pp) state per day, P as [p00, p01, p11].
  final xs = <List<double>>[], ps = <List<double>>[];
  final xps = <List<double>>[], pps = <List<double>>[];
  var l = weighIns[first]!, s = 0.0;
  var p00 = 1.0, p01 = 0.0, p11 = 0.01;
  for (var i = 0; i < span; i++) {
    l += s;
    p00 = p00 + 2 * p01 + p11 + _levelDrift;
    p01 = p01 + p11;
    p11 = p11 + _slopeDrift;
    xps.add([l, s]);
    pps.add([p00, p01, p11]);
    final w = weighIns[first + i];
    if (w != null) {
      final sum = p00 + _weighInNoise;
      final k0 = p00 / sum, k1 = p01 / sum;
      final y = w - l;
      l += k0 * y;
      s += k1 * y;
      final n00 = (1 - k0) * p00, n01 = (1 - k0) * p01;
      final n11 = p11 - k1 * p01;
      p00 = n00;
      p01 = n01;
      p11 = n11;
    }
    xs.add([l, s]);
    ps.add([p00, p01, p11]);
  }
  var sl = xs.last[0], ss = xs.last[1];
  out[first + span - 1] = sl;
  for (var i = span - 2; i >= 0; i--) {
    final pi = ps[i], pn = pps[i + 1];
    // P·Fᵀ, then C = P·Fᵀ·Pn⁻¹.
    final f00 = pi[0] + pi[1], f01 = pi[1], f10 = pi[1] + pi[2], f11 = pi[2];
    final det = pn[0] * pn[2] - pn[1] * pn[1];
    final i00 = pn[2] / det, i01 = -pn[1] / det, i11 = pn[0] / det;
    final c00 = f00 * i00 + f01 * i01, c01 = f00 * i01 + f01 * i11;
    final c10 = f10 * i00 + f11 * i01, c11 = f10 * i01 + f11 * i11;
    final d0 = sl - xps[i + 1][0], d1 = ss - xps[i + 1][1];
    sl = xs[i][0] + c00 * d0 + c01 * d1;
    ss = xs[i][1] + c10 * d0 + c11 * d1;
    out[first + i] = sl;
  }
  for (var d = first + span; d < days; d++) {
    out[d] = out[first + span - 1];
  }
  return out;
}
