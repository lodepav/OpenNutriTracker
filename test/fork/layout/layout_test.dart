import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/layout/arrange_screen.dart';
import 'package:opennutritracker/fork/layout/layout_store.dart';

import '../../helpers/ux_checks.dart';

/// In memory, as real Hive hangs under `testWidgets`.
class _Memory extends LayoutStore {
  _Memory(super.key);

  @override
  Future<void> save(Layout layout) async =>
      LayoutStore.current(key).value = layout;
}

void main() {
  test('a saved order keeps new items in place and drops gone ones', () {
    // 'd' is new: after 'c', its neighbour in the first order.
    expect(arrangeIds(['a', 'b', 'c', 'd'], ['c', 'a', 'gone', 'b']), [
      'c',
      'd',
      'a',
      'b',
    ]);
    // 'b' is new: after 'a', its neighbour in the first order.
    expect(arrangeIds(['a', 'b', 'c'], ['c', 'a']), ['c', 'a', 'b']);
    expect(arrangeIds(['a', 'b'], []), ['a', 'b']);
  });

  test('addable: optional items not switched on', () {
    expect(addable(['x', 'y', 'z'], (order: ['a', 'y', 'z'], hidden: {'z'})), {
      'x',
      'z',
    });
  });

  test('arranged: in the saved order, less the hidden', () {
    expect(
      arranged({'a': 1, 'b': 2, 'c': 3}, (order: ['c', 'a'], hidden: {'a'})),
      [3, 2],
    );
  });

  tearDown(() {
    for (final k in ['one', 'two']) {
      LayoutStore.current(k).value = (order: const [], hidden: const {});
    }
  });

  testWidgets('the editor: each list hidden, added back, reset', (
    tester,
  ) async {
    LayoutStore.current('one').value = (order: ['b', 'a'], hidden: {'c'});
    await tester.pumpWidget(
      MaterialApp(
        home: ArrangeScreen(
          title: 'Arrange',
          lists: [
            ArrangeList(
              title: 'Tiles',
              store: _Memory('one'),
              names: const {'a': 'A', 'b': 'B', 'c': 'C'},
            ),
            ArrangeList(
              title: 'Sections',
              store: _Memory('two'),
              names: const {'x': 'X', 'y': 'Y'},
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tiles'), findsOneWidget);
    expect(find.text('Sections'), findsOneWidget);
    double y(String name) => tester.getTopLeft(find.text(name)).dy;
    expect(y('B'), lessThan(y('A')));
    expect(y('C'), lessThan(y('X')));

    // C was hidden: switched on, it is back.
    await tester.tap(find.byKey(const ValueKey('arrange-c')));
    await tester.pumpAndSettle();
    expect(LayoutStore.current('one').value.hidden, isEmpty);
    await tester.tap(find.byKey(const ValueKey('arrange-y')));
    await tester.pumpAndSettle();
    expect(LayoutStore.current('two').value.order, ['x', 'y']);
    expect(LayoutStore.current('two').value.hidden, {'y'});

    await tester.tap(find.byKey(const ValueKey('arrange-reset')));
    await tester.pumpAndSettle();
    expect(LayoutStore.current('one').value.order, ['a', 'b', 'c']);
    expect(LayoutStore.current('two').value.hidden, isEmpty);
    expect(y('A'), lessThan(y('B')));
  });

  testWidgets('optional items: off until switched on, off again on reset', (
    tester,
  ) async {
    Future<void> pump() async {
      await tester.pumpWidget(
        MaterialApp(
          home: ArrangeScreen(
            title: 'Arrange',
            lists: [
              ArrangeList(
                title: 'Tiles',
                store: _Memory('one'),
                names: const {'a': 'A', 'b': 'B', 'p': 'P'},
                optional: const {'p'},
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    bool on(String id) => tester
        .widget<SwitchListTile>(find.byKey(ValueKey('arrange-$id')))
        .value;

    await pump();
    expect(on('a'), isTrue);
    expect(on('p'), isFalse);
    // A change elsewhere saves P as hidden, not as shown.
    await tester.tap(find.byKey(const ValueKey('arrange-a')));
    await tester.pumpAndSettle();
    expect(LayoutStore.current('one').value.hidden, {'a', 'p'});

    await tester.tap(find.byKey(const ValueKey('arrange-p')));
    await tester.pumpAndSettle();
    expect(LayoutStore.current('one').value.hidden, {'a'});
    expect(LayoutStore.current('one').value.order, ['a', 'b', 'p']);

    await tester.tap(find.byKey(const ValueKey('arrange-reset')));
    await tester.pumpAndSettle();
    expect(on('a'), isTrue);
    expect(on('p'), isFalse);
    expect(LayoutStore.current('one').value.hidden, {'p'});
  });

  testWidgets(
    'the editor at 200% text: nothing cut, the targets and contrast',
    (tester) async {
      await checkScreen(
        tester,
        ArrangeScreen(
          title: 'Arrange',
          lists: [
            ArrangeList(
              title: 'Tiles',
              store: _Memory('one'),
              names: const {'a': 'A', 'b': 'B', 'c': 'C'},
            ),
          ],
        ),
      );
    },
  );

  group('moving and resetting without a drag', () {
    Future<void> pump(WidgetTester tester) async {
      LayoutStore.current('one').value = (
        order: ['b', 'a', 'c'],
        hidden: {'c'},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ArrangeScreen(
            title: 'Arrange',
            lists: [
              ArrangeList(
                title: 'Tiles',
                store: _Memory('one'),
                names: const {'a': 'A', 'b': 'B', 'c': 'C'},
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder handle(String name) => find.descendant(
      of: find.ancestor(of: find.text(name), matching: find.byType(ListTile)),
      matching: find.byType(PopupMenuButton<int>),
    );

    testWidgets('each row\'s handle is a 48 dp target', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      // TalkBack moves the row by the list's own actions
      SemanticsNode? node = tester.getSemantics(handle('A'));
      expect(node.getSemanticsData().label, contains('A'));
      while (node != null &&
          !node.getSemanticsData().hasAction(SemanticsAction.customAction)) {
        node = node.parent;
      }
      expect(node, isNotNull);
      semantics.dispose();
      final size = tester.getSize(handle('A'));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });

    testWidgets('the handle\'s menu moves a row up or down', (tester) async {
      await pump(tester);
      await tester.tap(handle('A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move up'));
      await tester.pumpAndSettle();
      expect(LayoutStore.current('one').value.order, ['a', 'b', 'c']);

      // the first can't go up
      await tester.tap(handle('A'));
      await tester.pumpAndSettle();
      final up = tester.widget<PopupMenuItem<int>>(
        find.ancestor(
          of: find.text('Move up'),
          matching: find.byType(PopupMenuItem<int>),
        ),
      );
      expect(up.enabled, isFalse);
      await tester.tap(find.text('Move down'));
      await tester.pumpAndSettle();
      expect(LayoutStore.current('one').value.order, ['b', 'a', 'c']);
    });

    testWidgets('a drag from the handle still reorders', (tester) async {
      await pump(tester);
      // B, A, C: A dragged below C
      final from = tester.getCenter(handle('A'));
      final gesture = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 16));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, 12));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(LayoutStore.current('one').value.order, ['b', 'c', 'a']);
    });

    testWidgets('a press held on the handle, then dragged, still reorders', (
      tester,
    ) async {
      await pump(tester);
      final gesture = await tester.startGesture(tester.getCenter(handle('A')));
      await tester.pump(const Duration(milliseconds: 600));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, 12));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(LayoutStore.current('one').value.order, ['b', 'c', 'a']);
    });

    testWidgets('Undo after leaving the editor still puts the lists back', (
      tester,
    ) async {
      LayoutStore.current('one').value = (
        order: ['b', 'a', 'c'],
        hidden: {'c'},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ArrangeScreen(
                      title: 'Arrange',
                      lists: [
                        ArrangeList(
                          title: 'Tiles',
                          store: _Memory('one'),
                          names: const {'a': 'A', 'b': 'B', 'c': 'C'},
                        ),
                      ],
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('arrange-reset')));
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ArrangeScreen), findsNothing);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(LayoutStore.current('one').value.order, ['b', 'a', 'c']);
      expect(LayoutStore.current('one').value.hidden, {'c'});
    });

    testWidgets('Reset offers Undo, which puts every list back', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('arrange-reset')));
      await tester.pumpAndSettle();
      expect(LayoutStore.current('one').value.order, ['a', 'b', 'c']);
      expect(LayoutStore.current('one').value.hidden, isEmpty);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(LayoutStore.current('one').value.order, ['b', 'a', 'c']);
      expect(LayoutStore.current('one').value.hidden, {'c'});
      double y(String name) => tester.getTopLeft(find.text(name)).dy;
      expect(y('B'), lessThan(y('A')));
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const ValueKey('arrange-c')))
            .value,
        isFalse,
      );
    });
  });
}
