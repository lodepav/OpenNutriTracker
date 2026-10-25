import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';

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

/// The order and the hidden cards.
typedef TrendsLayout = ({List<String> order, Set<String> hidden});

/// [defaults] in the [saved] order; a card the saved order does not know
/// (one added since) keeps its place after the card it follows in
/// [defaults], and a saved id no longer among them is dropped.
List<String> arrangeIds(List<String> defaults, List<String> saved) {
  final order = [
    for (final id in saved)
      if (defaults.contains(id)) id,
  ];
  for (final (i, id) in defaults.indexed) {
    if (order.contains(id)) continue;
    final before = i == 0 ? -1 : order.indexOf(defaults[i - 1]);
    order.insert(before + 1, id);
  }
  return order;
}

/// The layout, per profile in the fork's box.
class TrendsLayoutStore {
  static const _key = 'trendsLayout';

  /// The active profile's, read once Trends first asks
  /// ([arrangeTrendCards]) and again on a profile switch; Trends rebuilds
  /// on it.
  static final current = ValueNotifier<TrendsLayout>((
    order: const [],
    hidden: const {},
  ));
  static var _loading = false;

  final Future<Box<dynamic>> Function() _box;

  TrendsLayoutStore([Future<Box<dynamic>> Function()? box])
    : _box = box ?? AdaptiveStore.openActiveBox;

  Future<TrendsLayout> layout() async {
    final json = (await _box()).get(_key);
    if (json is! Map) return (order: <String>[], hidden: <String>{});
    return (
      order: [for (final id in json['order'] as List) id as String],
      hidden: {for (final id in json['hidden'] as List) id as String},
    );
  }

  Future<void> save(TrendsLayout layout) async {
    current.value = layout;
    await (await _box()).put(_key, {
      'order': layout.order,
      'hidden': layout.hidden.toList(),
    });
  }

  static Future<void> _load() async {
    try {
      current.value = await TrendsLayoutStore().layout();
    } catch (_) {
      // No box (widget tests): upstream's order.
    }
  }

  /// Reads [current] the first time; a no-op after.
  static void ensureLoaded() {
    if (_loading) return;
    _loading = true;
    _load();
    try {
      locator<HiveDBProvider>().addListener(_load);
    } catch (_) {
      // No locator in widget tests.
    }
  }
}

/// Seam S47: Trends' cards (by the ids of [trendCards]) in the saved
/// order, less the hidden ones, then the link to the editor; each its own
/// child of Trends' list, so the cards below the fold stay unbuilt.
List<Widget> arrangeTrendCards(
  Map<String, Widget> cards, {
  TrendsLayoutStore? store,
}) {
  TrendsLayoutStore.ensureLoaded();
  final layout = TrendsLayoutStore.current.value;
  final order = arrangeIds(cards.keys.toList(), layout.order);
  return [
    for (final id in order)
      if (!layout.hidden.contains(id)) cards[id]!,
    const SizedBox(height: 16),
    Builder(
      builder: (context) => Center(
        child: TextButton.icon(
          key: const ValueKey('trends-arrange'),
          icon: const Icon(Icons.tune_rounded),
          label: const Text('Arrange cards'),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => TrendsLayoutScreen(
                store: store ?? TrendsLayoutStore(),
                layout: (order: order, hidden: layout.hidden),
              ),
            ),
          ),
        ),
      ),
    ),
  ];
}

/// Drag to reorder, switch off to hide; saved as it changes.
class TrendsLayoutScreen extends StatefulWidget {
  final TrendsLayoutStore store;
  final TrendsLayout layout;

  const TrendsLayoutScreen({
    super.key,
    required this.store,
    required this.layout,
  });

  @override
  State<TrendsLayoutScreen> createState() => _TrendsLayoutScreenState();
}

class _TrendsLayoutScreenState extends State<TrendsLayoutScreen> {
  late final List<String> _order = [...widget.layout.order];
  late final Set<String> _hidden = {...widget.layout.hidden};

  void _save() => widget.store.save((order: [..._order], hidden: {..._hidden}));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Arrange cards'),
      actions: [
        TextButton(
          key: const ValueKey('trends-reset'),
          onPressed: () {
            setState(() {
              _order
                ..clear()
                ..addAll(trendCards.keys);
              _hidden.clear();
            });
            _save();
          },
          child: const Text('Reset'),
        ),
      ],
    ),
    body: ReorderableListView(
      buildDefaultDragHandles: false,
      onReorderItem: (from, to) {
        setState(() => _order.insert(to, _order.removeAt(from)));
        _save();
      },
      children: [
        for (final (i, id) in _order.indexed)
          SwitchListTile(
            key: ValueKey('arrange-$id'),
            secondary: ReorderableDragStartListener(
              index: i,
              child: const Icon(Icons.drag_handle_rounded),
            ),
            title: Text(trendCards[id] ?? id),
            value: !_hidden.contains(id),
            onChanged: (shown) {
              setState(() => shown ? _hidden.remove(id) : _hidden.add(id));
              _save();
            },
          ),
      ],
    ),
  );
}
