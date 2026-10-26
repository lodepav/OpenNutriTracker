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

  const ArrangeList({
    required this.title,
    required this.store,
    required this.names,
  });
}

/// Drag to reorder, switch off to hide and on to add back; saved as it
/// changes. Reset puts every list back in its first order, all shown.
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
        hidden: {...LayoutStore.current(l.store.key).value.hidden},
      ),
  ];

  void _save(int i) => widget.lists[i].store.save((
    order: [..._layouts[i].order],
    hidden: {..._layouts[i].hidden},
  ));

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            key: const ValueKey('arrange-reset'),
            onPressed: () {
              setState(() {
                for (final (i, l) in widget.lists.indexed) {
                  _layouts[i].order
                    ..clear()
                    ..addAll(l.names.keys);
                  _layouts[i].hidden.clear();
                }
              });
              for (var i = 0; i < widget.lists.length; i++) {
                _save(i);
              }
            },
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
              'Drag to reorder. Switch one off to hide it, on to add it back.',
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
              onReorderItem: (from, to) {
                final order = _layouts[i].order;
                setState(() => order.insert(to, order.removeAt(from)));
                _save(i);
              },
              children: [
                for (final (j, id) in _layouts[i].order.indexed)
                  SwitchListTile(
                    key: ValueKey('arrange-$id'),
                    secondary: ReorderableDragStartListener(
                      index: j,
                      child: const Icon(Icons.drag_handle_rounded),
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
