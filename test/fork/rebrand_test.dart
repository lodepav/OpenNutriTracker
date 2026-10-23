import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Seam S31: an upstream merge can bring the old name back into a
/// translation; `fork/tools/rebrand.sh` puts it right.
void main() {
  test('no translation calls the app OpenNutriTracker', () {
    final stale = [
      for (final file in Directory('lib/l10n').listSync())
        if (file is File &&
            file.path.endsWith('.arb') &&
            file.readAsStringSync().contains('OpenNutriTracker'))
          file.path,
    ];
    expect(stale, isEmpty, reason: 'run fork/tools/rebrand.sh');
  });
}
