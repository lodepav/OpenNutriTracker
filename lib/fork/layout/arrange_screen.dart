import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/fork/layout/layout_store.dart';

/// One list the editor arranges: its heading, its store, and its items'
/// names by id in their first order.
class ArrangeList {
  final String title;
  final LayoutStore store;
  final Map<String, String> names;

  /// Items off until switched on: hidden while the saved order does not
  /// know them.
  final Set<String> optional;

  const ArrangeList({
    required this.title,
    required this.store,
    required this.names,
    this.optional = const {},
  });
}

/// Drag to reorder, or tap the handle for Move up and Move down; switch off
/// to hide and on to add back; saved as it changes. Reset puts every list
/// back in its first order, all shown but the optional items, with Undo.
class ArrangeScreen extends StatefulWidget {
  final String title;
  final List<ArrangeList> lists;

  const ArrangeScreen({super.key, required this.title, required this.lists});

  @override
  State<ArrangeScreen> createState() => _ArrangeScreenState();
}

class _ArrangeScreenState extends State<ArrangeScreen> {
  late final _layouts = [
    for (final l in widget.lists)
      (
        order: arrangeIds(
          l.names.keys.toList(),
          LayoutStore.current(l.store.key).value.order,
        ),
        hidden: {
          ...LayoutStore.current(l.store.key).value.hidden,
          ...addable(l.optional, LayoutStore.current(l.store.key).value),
        },
      ),
  ];

  void _save(int i) => widget.lists[i].store.save((
    order: [..._layouts[i].order],
    hidden: {..._layouts[i].hidden},
  ));

  void _move(int i, int from, int to) {
    final order = _layouts[i].order;
    setState(() => order.insert(to, order.removeAt(from)));
    _save(i);
  }

  /// Puts each list's [layouts] in place and saves them.
  void _restore(List<Layout> layouts) {
    void apply() {
      for (final (i, l) in layouts.indexed) {
        _layouts[i].order
          ..clear()
          ..addAll(l.order);
        _layouts[i].hidden
          ..clear()
          ..addAll(l.hidden);
      }
    }

    // Undo may come after the screen has closed: the stores save it then.
    mounted ? setState(apply) : apply();
    for (var i = 0; i < widget.lists.length; i++) {
      _save(i);
    }
  }

  void _reset() {
    final before = [
      for (final l in _layouts) (order: [...l.order], hidden: {...l.hidden}),
    ];
    _restore([
      for (final l in widget.lists)
        (order: l.names.keys.toList(), hidden: {...l.optional}),
    ]);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Layout reset'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _restore(before),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            key: const ValueKey('arrange-reset'),
            onPressed: _reset,
            child: const Text('Reset'),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.only(
          bottom: Dimens.spacing32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Dimens.spacing16,
              Dimens.spacing8,
              Dimens.spacing16,
              0,
            ),
            child: Text(
              'Drag or tap the handle to move. Switch one off to hide it, on '
              'to add it back.',
              style: text.bodySmall?.copyWith(
                color: paletteOf(context).textMuted,
              ),
            ),
          ),
          for (final (i, list) in widget.lists.indexed) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Dimens.spacing16,
                Dimens.spacing16,
                Dimens.spacing16,
                Dimens.spacing4,
              ),
              child: Semantics(
                header: true,
                child: Text(list.title, style: text.titleSmall),
              ),
            ),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderItem: (from, to) => _move(i, from, to),
              children: [
                for (final (j, id) in _layouts[i].order.indexed)
                  SwitchListTile(
                    key: ValueKey('arrange-$id'),
                    // drag it, or tap it for a menu: a 48 dp target either
                    // way, and a way to move with no drag (WCAG 2.5.7)
                    secondary: ReorderableDragStartListener(
                      index: j,
                      child: SizedBox.square(
                        dimension: 48,
                        // For touch: no tooltip, as its long-press would
                        // take a press held before a drag. TalkBack has the
                        // list's own Move actions on the row, which merges
                        // what is in it.
                        child: ExcludeSemantics(
                          child: TooltipVisibility(
                            visible: false,
                            child: PopupMenuButton<int>(
                              tooltip: 'Move ${list.names[id] ?? id}',
                              icon: const Icon(Icons.drag_handle_rounded),
                              onSelected: (to) => _move(i, j, to),
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: j - 1,
                                  enabled: j > 0,
                                  child: const Text('Move up'),
                                ),
                                PopupMenuItem(
                                  value: j + 1,
                                  enabled: j < _layouts[i].order.length - 1,
                                  child: const Text('Move down'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    title: Text(list.names[id] ?? id),
                    value: !_layouts[i].hidden.contains(id),
                    onChanged: (shown) {
                      final hidden = _layouts[i].hidden;
                      setState(
                        () => shown ? hidden.remove(id) : hidden.add(id),
                      );
                      _save(i);
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
