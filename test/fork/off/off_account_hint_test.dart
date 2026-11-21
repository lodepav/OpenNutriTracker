// The Open Food Facts account's user-name hint at 200% (round-3 settings
// critique, 2026-11-21, G6): "not the e-mail" was cut from the label, so it
// is a helper line that wraps.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/off/off_contribution.dart';
import 'package:opennutritracker/fork/off/off_contribution_ui.dart';

import '../../helpers/ux_checks.dart';

void main() {
  testWidgets('at 200% the field says "User name", and not the e-mail', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = OffAccountStore(const FlutterSecureStorage());
    await pumpOnPhone(tester, Scaffold(body: OffAccountTile(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fork-off-account')));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const Key('fork-off-user')),
    );
    expect(field.decoration?.labelText, 'User name');
    final helper = find.text('Not your e-mail address');
    expect(helper, findsOneWidget);
    expect(
      tester.renderObject<RenderParagraph>(helper).didExceedMaxLines,
      isFalse,
    );
  });
}
