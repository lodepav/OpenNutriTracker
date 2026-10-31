import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Every fork screen is run through checkScreen (test/helpers/ux_checks.dart) in its own test
// file, or is listed here with why not. A new screen fails this until it is one or the other.
const _notYet = {
  'lib/fork/adaptive/adaptive_ui.dart':
      'its Scaffolds are sub-pages of the settings tile',
  'lib/fork/backup/auto_backup_ui.dart': 'needs an AutoBackup over a Hive box',
  'lib/fork/phases/phases_ui.dart':
      'its Scaffolds are sub-pages of the phases card',
  'lib/fork/photos/photo_card.dart':
      'a full-screen photo, opened from the card',
  'lib/fork/screens/add_meal/add_meal_screen.dart': 'blocs from the locator',
  'lib/fork/screens/add_meal/bulk_add_screen.dart': 'blocs from the locator',
  'lib/fork/screens/fasting/fasting_screen.dart':
      'a bloc from the locator, and a running timer',
  'lib/fork/screens/profile/weight_history_screen.dart':
      'a wrapper: WeightHistoryView has the check',
  'lib/fork/screens/settings/settings_screen.dart': 'blocs from the locator',
  'lib/fork/trends/calories_detail.dart': 'needs TrendsBloc and TrendsDeps',
  'lib/fork/trends/trend_detail.dart': 'needs TrendsBloc and TrendsDeps',
};

Iterable<File> _dart(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

void main() {
  test('every fork screen has a screen check, or a reason it has none', () {
    final checked = {
      for (final f in _dart('test'))
        for (final m in RegExp(
          r'checkScreen\(\s*tester,\s*(?:const\s+)?(\w+)\(',
        ).allMatches(f.readAsStringSync()))
          m.group(1)!,
    };
    expect(checked, isNotEmpty);

    final missing = <String>[];
    final covered = <String>[];
    for (final f in _dart('lib/fork')) {
      final source = f.readAsStringSync();
      if (!source.contains('Scaffold(')) continue;
      final classes = RegExp(
        r'^class (\w+)',
        multiLine: true,
      ).allMatches(source).map((m) => m.group(1)!);
      if (classes.any(checked.contains)) {
        covered.add(f.path);
      } else {
        missing.add(f.path);
      }
    }
    expect(
      missing.where((p) => !_notYet.containsKey(p)),
      isEmpty,
      reason: 'add checkScreen to its test file, or a reason to _notYet',
    );
    // A screen that got its check, or went away, leaves the list.
    expect(covered.where(_notYet.containsKey), isEmpty);
    expect(_notYet.keys.where((p) => !missing.contains(p)), isEmpty);
  });
}
