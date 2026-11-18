import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/dbo/profile_dbo.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/trends/trends_range.dart';
import 'package:opennutritracker/fork/trends/trends_widgets.dart';

import '../../helpers/fake_hive_db_provider.dart';
import '../../helpers/hive_test_setup.dart';

/// Profiles' scoped boxes as plain boxes on disk.
class _Provider extends FakeHiveDBProvider {
  _Provider({required super.profileBox}) : super(activeProfileId: 'a');

  @override
  Future<Box<E>> openScopedBox<E>(String baseName, String boxSuffix) =>
      Hive.openBox<E>(HiveDBProvider.boxNameFor(baseName, boxSuffix));
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('trends_range');
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
  });

  tearDown(() async {
    await locator.unregister<HiveDBProvider>();
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  test('Trends starts at the range picked last, else at a week', () async {
    expect(await TrendsRange.read(), 7);
    await TrendsRange.save(90);
    expect(await TrendsRange.read(), 90);
    await TrendsRange.save(0);
    expect(await TrendsRange.read(), 0, reason: 'All');
  });

  test('a range Trends no longer offers starts at a week', () async {
    await TrendsRange.save(14);
    expect(await TrendsRange.read(), 7);
  });

  testWidgets('a pick on pills given their own ranges is not kept for '
      'Trends', (tester) async {
    Future<void> pick(
      List<({int days, String label, String spoken})>? ranges,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RangePills(rangeDays: 30, onChanged: (_) {}, ranges: ranges),
          ),
        ),
      );
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('trends-range-90')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
    }

    await pick([
      (days: 30, label: '30 d', spoken: '30 days'),
      (days: 90, label: '90 d', spoken: '90 days'),
    ]);
    expect(await tester.runAsync(TrendsRange.read), 7);
    await pick(null);
    expect(await tester.runAsync(TrendsRange.read), 90, reason: 'Trends');
  });
}
