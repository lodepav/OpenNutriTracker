import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/bulk/discard_guard.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../helpers/test_l10n.dart';

// Crit r4 g2: Discard loses work, so it takes the error colour.
void main() {
  testWidgets('Discard is filled in the error colour', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => confirmDiscard(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final label = find.text(l10nEn.discardChangesConfirmLabel);
    final discard = tester.widget<FilledButton>(
      find.ancestor(of: label, matching: find.byType(FilledButton)),
    );
    expect(
      discard.style?.backgroundColor?.resolve(const {}),
      Theme.of(tester.element(label)).colorScheme.error,
    );
  });
}
