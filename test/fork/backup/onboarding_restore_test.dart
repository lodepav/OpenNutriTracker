import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/backup/onboarding_restore.dart';

class _Restore extends OnboardingRestore {
  final bool picked;
  final bool profile;
  final bool fails;
  bool? acceptedDataCollection;
  var imports = 0;

  _Restore({this.picked = true, this.profile = true, this.fails = false});

  @override
  Future<bool> importBackup() async {
    imports++;
    if (fails) throw StateError('unreadable');
    return picked;
  }

  @override
  Future<bool> hasProfile() async => profile;

  @override
  Future<void> accept({required bool dataCollection}) async =>
      acceptedDataCollection = dataCollection;
}

void main() {
  Future<bool> tapRestore(
    WidgetTester tester,
    _Restore restore, {
    bool policy = true,
  }) async {
    var restored = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RestoreBackupButton(
            acceptedPolicy: policy,
            acceptedDataCollection: true,
            restore: restore,
            onRestored: () => restored = true,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('fork-onboarding-restore')));
    await tester.pumpAndSettle();
    return restored;
  }

  testWidgets('a backup with a profile goes into the app, the policy and '
      'the crash-report choice recorded', (tester) async {
    final restore = _Restore();
    expect(await tapRestore(tester, restore), isTrue);
    expect(restore.acceptedDataCollection, isTrue);
  });

  testWidgets('the policy comes first', (tester) async {
    final restore = _Restore();
    expect(await tapRestore(tester, restore, policy: false), isFalse);
    expect(restore.imports, 0);
    expect(find.textContaining('privacy policy'), findsOneWidget);
  });

  testWidgets('without a profile the setup goes on', (tester) async {
    final restore = _Restore(profile: false);
    expect(await tapRestore(tester, restore), isFalse);
    expect(restore.acceptedDataCollection, isNull);
    expect(find.textContaining('finish the setup'), findsOneWidget);
  });

  testWidgets('a dismissed picker does nothing', (tester) async {
    expect(await tapRestore(tester, _Restore(picked: false)), isFalse);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a bad file says so', (tester) async {
    expect(await tapRestore(tester, _Restore(fails: true)), isFalse);
    expect(find.text('That file could not be restored.'), findsOneWidget);
  });
}
