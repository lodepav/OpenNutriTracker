import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/report/trends_layout.dart';

/// In memory, as real Hive hangs under `testWidgets`.
class _Memory extends TrendsLayoutStore {
  @override
  Future<void> save(TrendsLayout layout) async =>
      TrendsLayoutStore.current.value = layout;
}

void main() {
  test('a saved order keeps new cards in place and drops gone ones', () {
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

  tearDown(
    () => TrendsLayoutStore.current.value = (order: const [], hidden: const {}),
  );

  testWidgets('cards follow the layout; hidden and reset in the editor', (
    tester,
  ) async {
    TrendsLayoutStore.current.value = (
      order: ['weight', 'calories'],
      hidden: {'water'},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: TrendsLayoutStore.current,
            builder: (context, _, _) => ListView(
              children: arrangeTrendCards({
                for (final id in ['calories', 'water', 'weight'])
                  id: Text('card $id'),
              }, store: _Memory()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    double y(String id) => tester.getTopLeft(find.text('card $id')).dy;
    expect(y('weight'), lessThan(y('calories')));
    expect(find.text('card water'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('trends-arrange')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('arrange-weight')));
    await tester.pumpAndSettle();
    expect(TrendsLayoutStore.current.value.hidden, {'water', 'weight'});

    await tester.tap(find.byKey(const ValueKey('trends-reset')));
    await tester.pumpAndSettle();
    expect(TrendsLayoutStore.current.value.hidden, isEmpty);
    expect(TrendsLayoutStore.current.value.order.first, 'calories');

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(y('calories'), lessThan(y('water')));
    expect(y('water'), lessThan(y('weight')));
  });
}
