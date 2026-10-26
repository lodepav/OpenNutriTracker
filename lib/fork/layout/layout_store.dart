import 'package:flutter/material.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';

/// The order and the hidden items of one arrangeable list.
typedef Layout = ({List<String> order, Set<String> hidden});

const Layout _none = (order: [], hidden: {});

/// [defaults] in the [saved] order; an item the saved order does not know
/// (one added since) keeps its place after the item it follows in
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

/// [items] (by id, in their first order) as [layout] arranges them, less
/// the hidden ones.
List<T> arranged<T>(Map<String, T> items, Layout layout) => [
  for (final id in arrangeIds(items.keys.toList(), layout.order))
    if (!layout.hidden.contains(id)) items[id] as T,
];

/// Of [optional] items, those not switched on: hidden, or not in the
/// saved order yet.
Set<String> addable(Iterable<String> optional, Layout layout) => {
  for (final id in optional)
    if (!layout.order.contains(id) || layout.hidden.contains(id)) id,
};

/// One list's layout under [key], per profile in the fork's box.
class LayoutStore {
  final String key;

  LayoutStore(this.key);

  static final _current = <String, ValueNotifier<Layout>>{};
  static var _listening = false;

  /// [key]'s layout for the active profile, read the first time it is
  /// asked for and again on a profile switch; screens rebuild on it.
  static ValueNotifier<Layout> current(String key) {
    final known = _current[key];
    if (known != null) return known;
    final notifier = _current[key] = ValueNotifier(_none);
    _load(key);
    if (!_listening) {
      _listening = true;
      try {
        locator<HiveDBProvider>().addListener(() {
          for (final k in _current.keys) {
            _load(k);
          }
        });
      } catch (_) {
        // No locator in widget tests.
      }
    }
    return notifier;
  }

  static Future<void> _load(String key) async {
    try {
      _current[key]!.value = await LayoutStore(key).layout();
    } catch (_) {
      // No box (widget tests): the first order.
    }
  }

  Future<Layout> layout() async {
    final json = (await AdaptiveStore.openActiveBox()).get(key);
    if (json is! Map) return (order: <String>[], hidden: <String>{});
    return (
      order: [for (final id in json['order'] as List) id as String],
      hidden: {for (final id in json['hidden'] as List) id as String},
    );
  }

  Future<void> save(Layout layout) async {
    current(key).value = layout;
    await (await AdaptiveStore.openActiveBox()).put(key, {
      'order': layout.order,
      'hidden': layout.hidden.toList(),
    });
  }
}
