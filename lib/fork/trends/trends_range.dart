import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart';

/// The Trends range last picked, in days (0 for All), per profile in the
/// fork's box; Trends opens at it.
class TrendsRange {
  static const key = 'trendsRange';

  /// The range Trends starts at before one is picked, as upstream's.
  static const first = 7;

  static Future<int> read() async {
    try {
      final days = (await AdaptiveStore.openActiveBox()).get(key);
      return trendRanges.any((r) => r.days == days) ? days as int : first;
    } catch (_) {
      // No box (widget tests): the first range.
      return first;
    }
  }

  static Future<void> save(int days) async {
    try {
      await (await AdaptiveStore.openActiveBox()).put(key, days);
    } catch (_) {
      // No box (widget tests): picked for the session only.
    }
  }
}
