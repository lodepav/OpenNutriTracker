import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/off/off_contribution.dart';
import 'package:opennutritracker/fork/off/off_contribution_ui.dart';

void main() {
  testWidgets('the account is saved to the keychain and shown on the tile', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = OffAccountStore(const FlutterSecureStorage());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: OffAccountTile(store: store)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Off.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('fork-off-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Offer to add my foods'));
    await tester.enterText(find.byKey(const Key('fork-off-user')), ' me ');
    await tester.enterText(find.byKey(const Key('fork-off-password')), 'pw');
    await tester.tap(find.byKey(const Key('fork-off-save')));
    await tester.pumpAndSettle();

    expect(find.text('On, as me, test server'), findsOneWidget);
    final saved = await store.load();
    expect(saved.isReady, isTrue);
    expect(saved.userId, 'me');
    expect(saved.useTestServer, isTrue);
  });
}
