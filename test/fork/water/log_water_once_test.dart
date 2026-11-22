import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/home/presentation/widgets/log_water_dialog.dart';
import 'package:opennutritracker/generated/l10n.dart';

// Log water (S473, S474): the slider says the amount in its unit, and OK
// writes the drink once however often it is tapped.

class _Home extends Fake implements HomeBloc {
  final List<int> added = [];
  // made in each test, in its fake-async zone
  late Completer<void> write;

  @override
  Future<void> addWaterIntake(int amountMl) {
    added.add(amountMl);
    return write.future;
  }
}

Widget _app({bool imperial = false}) => MaterialApp(
  localizationsDelegates: const [S.delegate],
  supportedLocales: S.supportedLocales,
  home: Scaffold(
    body: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => LogWaterDialog(usesImperialUnits: imperial),
        ),
        child: const Text('Open'),
      ),
    ),
  ),
);

Future<void> _open(WidgetTester tester, {bool imperial = false}) async {
  await tester.pumpWidget(_app(imperial: imperial));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

final _save = find.bySemanticsIdentifier('log-water-save');

void main() {
  late _Home home;

  setUp(() {
    home = _Home();
    locator.registerSingleton<HomeBloc>(home);
  });

  tearDown(() async => locator.reset());

  testWidgets('a second tap while the write runs logs nothing more', (
    tester,
  ) async {
    home.write = Completer<void>();
    await _open(tester);
    await tester.tap(_save);
    await tester.pump();
    await tester.tap(_save, warnIfMissed: false);
    await tester.pump();
    expect(home.added, [250]);

    home.write.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LogWaterDialog), findsNothing);
    expect(home.added, [250]);
  });

  testWidgets('the slider says the amount shown, with its unit', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _open(tester);
    expect(find.semantics.byValue('250 ml'), findsOne);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.semantics.byValue('0 ml'), findsOne);
    semantics.dispose();
  });

  testWidgets('in fl oz with imperial units', (tester) async {
    final semantics = tester.ensureSemantics();
    await _open(tester, imperial: true);
    expect(find.semantics.byValue('8 fl.oz'), findsOne);
    semantics.dispose();
  });
}
