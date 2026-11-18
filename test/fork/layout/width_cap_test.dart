import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/layout/home_layout.dart';
import 'package:opennutritracker/fork/layout/layout_store.dart';
import 'package:opennutritracker/fork/layout/width_cap.dart';
import 'package:opennutritracker/generated/l10n.dart';

void main() {
  final layout = LayoutStore.current(homeSectionsKey);
  tearDown(() => layout.value = (order: const [], hidden: const {}));

  Future<void> pumpHome(WidgetTester tester, double width) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = Size(width, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: HomeSectionsList(
            sections: {
              'dashboard': Container(
                key: const ValueKey('summary'),
                height: 100,
                color: Colors.green,
              ),
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('wide: Home\'s cards are 600 dp, centred', (tester) async {
    await pumpHome(tester, 1200);
    final card = tester.getRect(find.byKey(const ValueKey('summary')));
    expect(card.width, 600);
    expect(card.left, 300);
  });

  testWidgets('a phone: the cards span the screen as before', (tester) async {
    await pumpHome(tester, 411);
    final card = tester.getRect(find.byKey(const ValueKey('summary')));
    expect(card.width, 411);
    expect(card.left, 0);
  });

  testWidgets('a phone: a child that sizes to its content keeps its width', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(411, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: WidthCap(child: Row(children: [SizedBox(width: 10)])),
      ),
    );
    expect(tester.getSize(find.byType(Row)).width, 411);
  });

  testWidgets('wide: the sides of the list still scroll it', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1200, 600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              for (var i = 0; i < 30; i++)
                WidthCap(child: SizedBox(height: 100, child: Text('row $i'))),
            ],
          ),
        ),
      ),
    );
    await tester.dragFrom(const Offset(50, 400), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('row 0'), findsNothing);
  });

  testWidgets('crossing 600 dp keeps the child\'s State', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(400, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: WidthCap(child: _Counter())),
      ),
    );
    await tester.tap(find.text('0'));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    tester.view.physicalSize = const Size(800, 900);
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
  });
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int taps = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => setState(() => taps++),
    child: Text('$taps'),
  );
}
