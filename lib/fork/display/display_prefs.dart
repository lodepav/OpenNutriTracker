import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/reload_diary_and_trends.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/basket/basket_ui.dart';
import 'package:opennutritracker/fork/display/settings_tile.dart';

/// The three main macros, in upstream's order.
enum Macro { carbs, fat, protein }

/// How the app shows what it has, per profile in the fork's box: the order
/// the macros are listed in everywhere, and whether the Diary lists a day
/// by the hour rather than by meal.
abstract final class DisplayPrefs {
  static const _orderKey = 'macroOrder';
  static const _byHourKey = 'diaryByHour';

  /// Upstream's order: carbs, fat, protein.
  static const upstreamOrder = [Macro.carbs, Macro.fat, Macro.protein];

  static final macroOrder = ValueNotifier<List<Macro>>(upstreamOrder);
  static final diaryByHour = ValueNotifier<bool>(false);

  static Future<Box<dynamic>> _box() => AdaptiveStore.openActiveBox();

  /// Run at start-up (seam S6): loads the active profile's, and again on a
  /// profile switch.
  static Future<void> start() async {
    await _load();
    locator<HiveDBProvider>().addListener(_load);
  }

  static Future<void> _load() async {
    final box = await _box();
    macroOrder.value = parseOrder(box.get(_orderKey));
    diaryByHour.value = box.get(_byHourKey) == true;
  }

  static Future<void> setMacroOrder(List<Macro> order) async {
    macroOrder.value = order;
    await (await _box()).put(_orderKey, [for (final m in order) m.name]);
  }

  static Future<void> setDiaryByHour(bool on) async {
    diaryByHour.value = on;
    await (await _box()).put(_byHourKey, on);
  }

  /// A stored order, or upstream's for anything that is not all three
  /// macros once each.
  static List<Macro> parseOrder(Object? stored) {
    if (stored is! List) return upstreamOrder;
    final order = [
      for (final name in stored)
        for (final m in Macro.values)
          if (m.name == name) m,
    ];
    return order.length == 3 && order.toSet().length == 3
        ? order
        : upstreamOrder;
  }
}

/// [carbs], [fat] and [protein] in the order the user picked (seams S79).
List<T> inMacroOrder<T>({
  required T carbs,
  required T fat,
  required T protein,
}) => [
  for (final m in DisplayPrefs.macroOrder.value)
    switch (m) {
      Macro.carbs => carbs,
      Macro.fat => fat,
      Macro.protein => protein,
    },
];

/// "Protein, fat, carbs".
String macroOrderLabel(List<Macro> order) {
  const names = {
    Macro.carbs: 'carbs',
    Macro.fat: 'fat',
    Macro.protein: 'protein',
  };
  final text = order.map((m) => names[m]!).join(', ');
  return text[0].toUpperCase() + text.substring(1);
}

/// All six orders, upstream's first.
List<List<Macro>> get macroOrders {
  const m = Macro.values;
  return [
    for (final a in m)
      for (final b in m)
        for (final c in m)
          if (a != b && b != c && a != c) [a, b, c],
  ];
}

/// Home, the Diary and Trends live on in the tab stack: reloaded, they
/// draw again in the new order.
void _reload() {
  refreshAfterLogging();
  reloadDiaryAndTrends();
}

/// Rebuilds [builder] when the macro order changes.
class MacroOrderBuilder extends StatelessWidget {
  final WidgetBuilder builder;

  const MacroOrderBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<Macro>>(
    valueListenable: DisplayPrefs.macroOrder,
    builder: (context, _, _) => builder(context),
  );
}

/// "Macro order" in Settings' display section (seam S79): one of the six
/// orders, for every place the app lists carbs, fat and protein.
class MacroOrderTile extends StatelessWidget {
  const MacroOrderTile({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<Macro>>(
    valueListenable: DisplayPrefs.macroOrder,
    builder: (context, order, _) => Semantics(
      identifier: 'settings-macro-order',
      child: ForkSettingsTile(
        icon: Icons.swap_vert_rounded,
        title: 'Macro order',
        subtitle: Text(macroOrderLabel(order)),
        onTap: () async {
          final picked = await showDialog<List<Macro>>(
            context: context,
            builder: (context) => SimpleDialog(
              title: const Text('Macro order'),
              children: [
                for (final option in macroOrders)
                  RadioListTile<String>(
                    title: Text(macroOrderLabel(option)),
                    value: option.join(),
                    // ignore: deprecated_member_use
                    groupValue: order.join(),
                    // ignore: deprecated_member_use
                    onChanged: (_) => Navigator.pop(context, option),
                  ),
              ],
            ),
          );
          if (picked == null) return;
          await DisplayPrefs.setMacroOrder(picked);
          _reload();
        },
      ),
    ),
  );
}

/// "Diary by the hour" beside it: the Diary lists a day's foods under the
/// hour they were eaten in, not under their meals.
class DiaryByHourTile extends StatelessWidget {
  const DiaryByHourTile({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: DisplayPrefs.diaryByHour,
    builder: (context, on, _) => Semantics(
      identifier: 'settings-diary-by-hour',
      child: ForkSettingsSwitchTile(
        icon: Icons.schedule_rounded,
        title: 'Diary by the hour',
        subtitle: const Text(
          'List each day\'s foods under the hour they were eaten, not by meal',
        ),
        value: on,
        onChanged: (on) async {
          await DisplayPrefs.setDiaryByHour(on);
          _reload();
        },
      ),
    ),
  );
}
