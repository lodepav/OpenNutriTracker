import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/dbo/profile_dbo.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/layout/arrange_screen.dart';
import 'package:opennutritracker/fork/layout/home_layout.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../helpers/fake_hive_db_provider.dart';
import '../../helpers/hive_test_setup.dart';

/// Profiles' scoped boxes as plain boxes on disk.
class _Provider extends FakeHiveDBProvider {
  _Provider({required super.profileBox}) : super(activeProfileId: 'a');

  @override
  Future<Box<E>> openScopedBox<E>(String baseName, String boxSuffix) =>
      Hive.openBox<E>(HiveDBProvider.boxNameFor(baseName, boxSuffix));
}

// A file of its own: the layouts in memory are static, and this needs
// them never read, as for a profile whose Home hides the quick actions.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('arrange_home');
    Hive.init(dir.path);
    registerHiveAdaptersOnce();
    final profiles = await Hive.openBox<ProfileDBO>('profiles');
    await profiles.put(
      'a',
      ProfileDBO(
        id: 'a',
        name: 'a',
        createdAt: DateTime(2026),
        boxSuffix: '_a',
      ),
    );
    locator.registerSingleton<HiveDBProvider>(_Provider(profileBox: profiles));
    // Written straight to the box, so no layout is in memory yet.
    final box = await AdaptiveStore.openActiveBox();
    await box.put(homeSectionsKey, {
      'order': ['dashboard', 'quickActions'],
      'hidden': ['quickActions'],
    });
    await box.put(homeQuickActionsKey, {
      'order': ['search', 'scan', 'quick-add', 'weigh-in', 'meal-plan'],
      'hidden': ['scan'],
    });
  });

  tearDown(() async {
    await locator.unregister<HiveDBProvider>();
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  testWidgets('Arrange Home shows the saved quick actions, though Home '
      'never showed them', (tester) async {
    tester.view.physicalSize = const Size(800, 6000);
    addTearDown(tester.view.reset);
    late BuildContext home;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: S.supportedLocales,
        home: Builder(
          builder: (context) {
            home = context;
            return const Scaffold();
          },
        ),
      ),
    );
    // The box is real IO: let it run before the editor builds.
    await tester.runAsync(() async {
      openArrangeHome(home);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();
    expect(find.byType(ArrangeScreen), findsOneWidget);
    bool on(String id) => tester
        .widget<SwitchListTile>(find.byKey(ValueKey('arrange-$id')))
        .value;
    expect(on('search'), isTrue);
    expect(on('scan'), isFalse);
    expect(on('quickActions'), isFalse);
  });
}
