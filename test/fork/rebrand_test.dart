import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Seam S31: the fork's edits to upstream's translations are applied by
/// `fork/tools/l10n_overlay.py`. An upstream merge that conflicts in one is
/// resolved by taking upstream's side and running the script; these fail
/// until then.
void main() {
  test('no translation calls the app OpenNutriTracker', () {
    final stale = [
      for (final file in Directory('lib/l10n').listSync())
        if (file is File &&
            file.path.endsWith('.arb') &&
            file.readAsStringSync().contains('OpenNutriTracker'))
          file.path,
    ];
    expect(stale, isEmpty, reason: 'run fork/tools/l10n_overlay.py');
  });

  test('the English translation has the fork\'s overlay', () {
    final overlay =
        jsonDecode(File('fork/l10n/intl_en_overlay.json').readAsStringSync())
            as Map<String, dynamic>;
    final english =
        jsonDecode(File('lib/l10n/intl_en.arb').readAsStringSync())
            as Map<String, dynamic>;
    final stale = [
      for (final MapEntry(:key, :value) in overlay.entries)
        if (jsonEncode(english[key]) != jsonEncode(value)) key,
    ];
    expect(stale, isEmpty, reason: 'run fork/tools/l10n_overlay.py');
  });
}
