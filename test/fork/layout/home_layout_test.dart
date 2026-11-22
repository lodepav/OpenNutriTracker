import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/layout/arrange_screen.dart';
import 'package:opennutritracker/fork/layout/home_layout.dart';
import 'package:opennutritracker/fork/layout/layout_store.dart';
import 'package:opennutritracker/generated/l10n.dart';

void main() {
  final layout = LayoutStore.current(homeSectionsKey);
  tearDown(() => layout.value = (order: const [], hidden: const {}));

  Future<void> pump(WidgetTester tester) async {
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
              'dashboard': const Text('summary'),
              'recentFoods': const Text('recent'),
              'tiles': const Text('tiles'),
              'plan': const Text('plan'),
              'notices': const Text('notices'),
              'diaryActivity': null,
              'diaryBreakfast': const Text('breakfast'),
              'diaryLunch': const Text('lunch'),
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double y(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dy;

  testWidgets('strength is a section of its own, apart from the check-in', (
    tester,
  ) async {
    late Map<String, String> names;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: S.supportedLocales,
        home: Builder(
          builder: (context) {
            names = homeSectionNames(context);
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(names, containsPair('strength', 'Strength'));
    expect(names, containsPair('checkIn', 'Weekly check-in'));
    // A due check-in is a decision: above the tiles, not under the fold.
    final ids = names.keys.toList();
    expect(ids.indexOf('checkIn'), ids.indexOf('tiles') - 1);
  });

  testWidgets('the sections as arranged; the notices follow the plan', (
    tester,
  ) async {
    // As the editor saves it: every section but the notices.
    layout.value = (
      order: [
        'diaryLunch',
        'plan',
        'dashboard',
        'tiles',
        'diaryActivity',
        'diaryBreakfast',
      ],
      hidden: {'tiles'},
    );
    await pump(tester);
    expect(find.text('tiles'), findsNothing);
    expect(y(tester, 'lunch'), lessThan(y(tester, 'plan')));
    expect(y(tester, 'plan'), lessThan(y(tester, 'notices')));
    expect(y(tester, 'notices'), lessThan(y(tester, 'summary')));
    expect(y(tester, 'summary'), lessThan(y(tester, 'breakfast')));
  });

  testWidgets('today\'s diary is off, also under a layout saved before', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('summary'), findsOneWidget);
    expect(find.text('breakfast'), findsNothing);
    expect(find.text('lunch'), findsNothing);

    // Saved while the meals were on by default, under their old ids.
    layout.value = (
      order: ['dashboard', 'tiles', 'plan', 'activity', 'breakfast', 'lunch'],
      hidden: const {},
    );
    await tester.pumpAndSettle();
    expect(find.text('breakfast'), findsNothing);
    expect(find.text('lunch'), findsNothing);
  });

  testWidgets('Recent foods is off, but under a saved order that lists it', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('summary'), findsOneWidget);
    expect(find.text('recent'), findsNothing);

    layout.value = (order: ['dashboard', 'recentFoods'], hidden: const {});
    await tester.pumpAndSettle();
    expect(find.text('recent'), findsOneWidget);
  });

  testWidgets('a meal switched on in Arrange Home shows', (tester) async {
    layout.value = (order: ['dashboard', 'diaryLunch'], hidden: const {});
    await pump(tester);
    expect(find.text('lunch'), findsOneWidget);
    expect(find.text('breakfast'), findsNothing);
  });

  testWidgets('Arrange Home: sections and tiles; a hidden one added back', (
    tester,
  ) async {
    // Tall enough to build every list.
    tester.view.physicalSize = const Size(800, 6000);
    addTearDown(tester.view.reset);
    layout.value = (order: const [], hidden: {'tiles'});
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('home-arrange')));
    await tester.pumpAndSettle();
    expect(find.byType(ArrangeScreen), findsOneWidget);
    expect(find.text('Sections'), findsOneWidget);
    // Not in the editor: it goes with the plan.
    expect(find.byKey(const ValueKey('arrange-notices')), findsNothing);
    final tiles = find.byKey(const ValueKey('arrange-tiles'));
    expect(tester.widget<SwitchListTile>(tiles).value, isFalse);
    // Tapping saves through the real store; with no box here it only
    // fails to write, so the notifier is what the screen shows.
    final snack = find.byKey(const ValueKey('arrange-diarySnack'));
    expect(tester.widget<SwitchListTile>(snack).value, isFalse);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('arrange-quickActions')),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('arrange-recentFoods')),
          )
          .value,
      isFalse,
    );
    // The quick actions, a list of their own: search off, the rest on.
    expect(find.text('Quick actions'), findsNWidgets(2));
    bool on(String id) => tester
        .widget<SwitchListTile>(find.byKey(ValueKey('arrange-$id')))
        .value;
    expect(on('search'), isFalse);
    for (final id in ['scan', 'quick-add', 'weigh-in', 'meal-plan']) {
      expect(on(id), isTrue, reason: id);
    }
    // AI meal assistance is off here.
    expect(find.byKey(const ValueKey('arrange-photo')), findsNothing);
  });
}
