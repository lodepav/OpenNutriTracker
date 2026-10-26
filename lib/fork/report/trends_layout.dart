import 'package:flutter/material.dart';
import 'package:opennutritracker/fork/layout/layout_store.dart';

/// Trends' cards below the tile grid (S120), in their first order, with
/// the names the editor shows. The calorie, macro, water, weight and
/// expenditure cards became tiles; a saved order naming them drops them.
const trendCards = {
  'weekly': 'Weekly report',
  'goalPlan': 'Goal planner',
  'phases': 'Diet phases',
  'body': 'Body measurements',
  'steps': 'Steps',
  'photos': 'Progress photos',
};

/// The cards' layout, per profile in the fork's box.
class TrendsLayoutStore extends LayoutStore {
  static const storeKey = 'trendsLayout';

  TrendsLayoutStore() : super(storeKey);

  /// The active profile's; Trends rebuilds on it.
  static ValueNotifier<Layout> get current => LayoutStore.current(storeKey);
}

/// Trends' tiles, by their metric's name.
class TrendsTilesStore extends LayoutStore {
  static const storeKey = 'trendsTiles';

  TrendsTilesStore() : super(storeKey);

  static ValueNotifier<Layout> get current => LayoutStore.current(storeKey);
}

/// Seam S47: Trends' cards (by the ids of [trendCards]) in the saved
/// order, less the hidden ones; each its own child of Trends' list, so the
/// cards below the fold stay unbuilt.
List<Widget> arrangeTrendCards(Map<String, Widget> cards) =>
    arranged(cards, TrendsLayoutStore.current.value);
