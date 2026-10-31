import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/settings/settings_index.dart';

import '../../helpers/ux_checks.dart';

void main() {
  testWidgets('the index at 200% text: nothing cut, the targets and contrast', (
    tester,
  ) async {
    await checkScreen(
      tester,
      SettingsIndex(
        summaries: {
          for (final s in SettingsSection.values) s: 'A summary of it',
        },
        onOpen: (_) {},
      ),
    );
  });
}
