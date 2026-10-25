// A new OpenBite offers itself once per version (D16).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/update/update_notice.dart';
import 'package:opennutritracker/fork/update/updater.dart';

class _Updater extends Updater {
  UpdateInfo info;

  _Updater(this.info);

  int checks = 0;

  @override
  Future<UpdateInfo> check() async {
    checks++;
    return info;
  }
}

const _newer = UpdateInfo(
  hasUpdate: true,
  latestVersion: '0.2.0',
  apkUrl: 'a',
  hashUrl: 'h',
);

void main() {
  test('offers a newer version with an APK, not the one already offered', () {
    expect(shouldOffer(_newer, null), isTrue);
    expect(shouldOffer(_newer, '0.1.1'), isTrue);
    expect(shouldOffer(_newer, '0.2.0'), isFalse);
    expect(shouldOffer(const UpdateInfo.none('0.1.0'), null), isFalse);
    expect(
      shouldOffer(
        const UpdateInfo(hasUpdate: true, latestVersion: '0.2.0'),
        null,
      ),
      isFalse,
    );
    expect(shouldOffer(null, null), isFalse);
  });

  group('the notice', () {
    String? seen;

    setUp(() => seen = null);

    Widget app(Updater updater) => MaterialApp(
      home: UpdateNotice(
        updater: updater,
        readSeen: () async => seen,
        writeSeen: (v) async => seen = v,
        child: const Scaffold(body: Text('diary')),
      ),
    );

    testWidgets('asks after launch, once; Not now waits for the next', (
      tester,
    ) async {
      final updater = _Updater(_newer);
      await tester.pumpWidget(app(updater));
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('OpenBite 0.2.0 is available'), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('OpenBite 0.2.0 is available'), findsOneWidget);
      expect(seen, '0.2.0');

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('OpenBite 0.2.0 is available'), findsNothing);

      // A return to the app does not ask again about the same version...
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('OpenBite 0.2.0 is available'), findsNothing);

      // ...but does about the next one.
      updater.info = const UpdateInfo(
        hasUpdate: true,
        latestVersion: '0.3.0',
        apkUrl: 'a',
        hashUrl: 'h',
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('OpenBite 0.3.0 is available'), findsOneWidget);
    });

    testWidgets('says nothing without an update', (tester) async {
      await tester.pumpWidget(app(_Updater(const UpdateInfo.none('0.1.0'))));
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(seen, isNull);
    });
  });

  group('the Updates row', () {
    Future<void> row(WidgetTester tester, Updater updater) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UpdateStatus(
              version: '0.1.0',
              updater: updater,
              builder: (subtitle, onTap) =>
                  ListTile(title: Text(subtitle), onTap: onTap),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('names the version running and the update there is', (
      tester,
    ) async {
      await row(tester, _Updater(_newer));
      expect(
        find.text(
          'Version 0.1.0. OpenBite 0.2.0 is available; tap to install.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('up to date, a tap asks again', (tester) async {
      final updater = _Updater(const UpdateInfo.none('0.1.0'));
      await row(tester, updater);
      expect(
        find.text('Version 0.1.0, the latest. Tap to check again.'),
        findsOneWidget,
      );
      expect(updater.checks, 1);
      updater.info = _newer;
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();
      expect(updater.checks, 2);
      expect(
        find.textContaining('OpenBite 0.2.0 is available'),
        findsOneWidget,
      );
    });

    testWidgets('a build that never asks says so', (tester) async {
      await row(
        tester,
        _Updater(const UpdateInfo.none('0.1.0', checked: false)),
      );
      expect(
        find.textContaining('This build does not update itself'),
        findsOneWidget,
      );
    });
  });
}
